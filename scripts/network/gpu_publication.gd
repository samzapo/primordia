extends RefCounted
## Compact, deduplicated view gather. Single bounded async readback in flight.
const LIMIT := 100000
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var bindings := RID()
var output := RID()
var views := RID()
var inflight := false
var closed := false
var bytes_read := 0
var requests := 0
var skipped := 0
var callback: Callable
var closed_callback: Callable

func initialize(device: RenderingDevice,state: RID,identity: RID) -> bool:
	rd = device
	output = rd.storage_buffer_create(16+LIMIT*32)
	views = rd.storage_buffer_create(8*16)
	var source := RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string("res://shaders/compute/resident_publish.glsl.txt").replace("#[compute]","")
	var spirv := rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "": push_error(spirv.compile_error_compute); return false
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var uniforms: Array[RDUniform] = []
	for i in 4:
		var uniform := RDUniform.new()
		uniform.binding = i
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE if i == 0 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.add_id([state,identity,views,output][i]); uniforms.append(uniform)
	bindings = rd.uniform_set_create(uniforms,shader,0)
	return pipeline.is_valid() and bindings.is_valid()

func request(regions: Array,count: int,done: Callable) -> bool:
	if inflight or closed: skipped += 1; return false
	inflight = true; callback = done; requests += 1
	var data := PackedFloat32Array()
	for region in regions:
		for i in 4: data.append(region[i])
	if not data.is_empty(): rd.buffer_update(views,0,data.size()*4,data.to_byte_array())
	rd.buffer_clear(output,0,16)
	var pc := PackedInt32Array([count,LIMIT,regions.size(),0]).to_byte_array()
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline); rd.compute_list_bind_uniform_set(list,bindings,0)
	rd.compute_list_set_push_constant(list,pc,16); rd.compute_list_dispatch(list,maxi(1,ceili(count/128.0)),1,1); rd.compute_list_end()
	var error := rd.buffer_get_data_async(output,_received)
	if error != OK: inflight = false; return false
	return true

func _received(data: PackedByteArray) -> void:
	inflight = false; bytes_read += data.size()
	var count := data.decode_u32(0)
	callback.call_deferred({"bytes":data.slice(16,16+mini(count,LIMIT)*32),"count":mini(count,LIMIT),"overflow":count>LIMIT})
	if closed: close()

func close() -> void:
	closed = true
	if inflight: return
	for resource in [bindings,pipeline,shader,views,output]:
		if resource.is_valid(): rd.free_rid(resource)
	bindings = RID(); pipeline = RID(); shader = RID(); views = RID(); output = RID()
	if closed_callback.is_valid(): closed_callback.call_deferred()
