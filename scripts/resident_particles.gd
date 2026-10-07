extends RefCounted
## Main-device diagnostic. All RD work is ordered on the render thread.
## No synchronous readback in advance(); snapshots are validation-only.
signal ready(ok: bool, reason: String)
signal snapshot_ready(data: PackedFloat32Array)
signal closed
var texture := Texture2DRD.new()
var rd: RenderingDevice
var state := RID()
var flow := RID()
var shader := RID()
var pipeline := RID()
var bindings := RID()
var count := 0
var upload_bytes := 0
var dispatches := 0
var readbacks := 0
var width := 768
var height := 1
var _closing := false
var _source := ""
func initialize(values: PackedFloat32Array, velocity: PackedVector2Array) -> void:
	count = values.size()/12
	if count < 1 or count > 100000 or values.size()%12 != 0 or velocity.size()!=2560:
		_ready_main.call_deferred(false,"Invalid resident particle capacity or flow")
		return
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()=="gl_compatibility":
		_ready_main.call_deferred(false,"Requires Mobile/Forward+ and a real RenderingDevice display")
		return
	height = ceili(count/256.0)
	_source = FileAccess.get_file_as_string("res://shaders/compute/resident_particles.glsl.txt").replace("#[compute]","")
	var padded := values.duplicate()
	padded.resize(width*height*4)
	RenderingServer.call_on_render_thread(_initialize_rd.bind(padded.to_byte_array(),velocity.to_byte_array()))
func _initialize_rd(bytes: PackedByteArray, velocities: PackedByteArray) -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		_ready_main.call_deferred(false,"Main RenderingDevice unavailable")
		return
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if not rd.texture_is_format_supported_for_usage(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,usage):
		_ready_main.call_deferred(false,"RGBA32F storage/sampling unsupported")
		return
	var source := RDShaderSource.new()
	source.source_compute = _source
	var spirv := rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "":
		_ready_main.call_deferred(false,spirv.compile_error_compute)
		return
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var format := RDTextureFormat.new()
	format.width=width;format.height=height
	format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits=usage
	state=rd.texture_create(format,RDTextureView.new(),[bytes])
	flow=rd.storage_buffer_create(velocities.size(),velocities)
	if not pipeline.is_valid() or not state.is_valid() or not flow.is_valid():
		_ready_main.call_deferred(false,"Resident pipeline/resource allocation failed")
		return
	var a := RDUniform.new()
	a.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;a.binding=0;a.add_id(state)
	var b := RDUniform.new()
	b.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;b.binding=1;b.add_id(flow)
	bindings=rd.uniform_set_create([a,b],shader,0)
	if not bindings.is_valid():
		_ready_main.call_deferred(false,"Resident bindings invalid")
		return
	upload_bytes += bytes.size()+velocities.size()
	_ready_main.call_deferred(true,"")
func _ready_main(ok: bool, reason: String) -> void:
	if ok: texture.texture_rd_rid=state
	ready.emit(ok,reason)
func advance(dt: float, tick: int) -> void:
	assert(dt>0 and dt<=2 and tick>=0 and tick<=0xffffffff and not _closing)
	RenderingServer.call_on_render_thread(_advance_rd.bind(dt,tick))
func _advance_rd(dt: float, tick: int) -> void:
	var params := PackedByteArray()
	params.resize(16);params.encode_u32(0,count);params.encode_float(4,dt);params.encode_u32(8,tick)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,bindings,0)
	rd.compute_list_set_push_constant(list,params,16)
	rd.compute_list_dispatch(list,ceili(count/128.0),1,1)
	rd.compute_list_end()
	dispatches += 1
	# Main device submission and barriers are owned by the renderer. No submit/sync.
func upload(values: PackedFloat32Array) -> void:
	assert(values.size()==count*12 and not _closing)
	var padded := values.duplicate()
	padded.resize(width*height*4)
	RenderingServer.call_on_render_thread(_upload_rd.bind(padded.to_byte_array()))
func _upload_rd(bytes: PackedByteArray) -> void:
	rd.texture_update(state,0,bytes)
	upload_bytes += bytes.size()
func snapshot() -> void:
	RenderingServer.call_on_render_thread(_snapshot_rd)
func _snapshot_rd() -> void:
	# Explicit blocking diagnostic, outside timed windows. Never used by gameplay.
	var values := rd.texture_get_data(state,0).to_float32_array()
	values.resize(count*12)
	readbacks += 1
	_snapshot_main.call_deferred(values)
func _snapshot_main(values: PackedFloat32Array) -> void:
	snapshot_ready.emit(values)
func close() -> void:
	if _closing: return
	_closing=true
	texture.texture_rd_rid=RID()
	RenderingServer.call_on_render_thread(_close_rd)
func _close_rd() -> void:
	if rd != null:
		for resource in [bindings,pipeline,shader,state,flow]:
			if resource.is_valid(): rd.free_rid(resource)
	rd=null # Main RenderingDevice belongs to Godot; never free it.
	_closed_main.call_deferred()
func _closed_main() -> void: closed.emit()
