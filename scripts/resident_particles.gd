extends RefCounted
## Main-device diagnostic. All RD work is ordered on the render thread.
## No synchronous readback in advance(); snapshots are validation-only.
signal ready(ok: bool, reason: String)
signal snapshot_ready(data: PackedFloat32Array)
signal contacts_ready(data: Dictionary)
signal exchange_ready(receipt: Dictionary)
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
var _initialized:=false
var _started:=false
var _closing := false
var _close_queued := false
var _source := ""
var interaction_mode := 0
var acidity := 0.4
var contact_sources: Array[String] = []
var contact_shaders: Array[RID] = []
var contact_pipelines: Array[RID] = []
var contact_sets: Array[RID] = []
var contact_buffers: Array[RID] = []
var padded_count := 1
var reaction_tick := 0
var _grid_valid := false
const Exchange=preload("res://scripts/resident_exchange.gd")
var exchange_enabled:=false
var exchange_busy:=false
var exchange_serial:=0
var exchange_readback_bytes:=0
var exchange_upload_bytes:=0
var exchange_fallbacks:=0
var _exchange_source:=""
var _exchange: RefCounted
func configure_exchange() -> bool:
	if _started or interaction_mode==0: return false
	exchange_enabled=true
	return true
func exchange(cells: Array, emissions: Array=[], handles: Array=[], asynchronous: bool=true) -> bool:
	if not exchange_enabled or exchange_busy or _closing or not _initialized: return false
	var batch:=Exchange.prepare(cells,emissions,handles)
	if batch.has("error"): return false
	if batch.body_count+batch.emit_count+batch.inspect_count==0: return false
	exchange_busy=true;exchange_serial+=1
	batch["serial"]=exchange_serial
	RenderingServer.call_on_render_thread(_exchange_rd.bind(batch,asynchronous))
	return true
func _exchange_rd(batch: Dictionary, asynchronous: bool) -> void:
	# Feeding needs a fresh grid after transport, projection or emission.
	if batch.feed_count>0 and not _grid_valid: _prepare_grid_rd()
	exchange_upload_bytes+=_exchange.upload(batch)
	_exchange.dispatch(1,batch,1)
	if batch.body_count>0: _exchange.dispatch(2,batch,ceili(count/128.0))
	if batch.body_count>0 or batch.emit_count>0: _grid_valid=false
	if batch.inspect_count>0: _exchange.dispatch(3,batch,ceili(batch.inspect_count/128.0))
	var size: int=(batch.body_count+batch.feed_count+batch.emit_count+batch.inspect_count*4)*16
	var callback:=_exchange_received.bind(batch)
	if asynchronous:
		var error:=rd.buffer_get_data_async(_exchange.buffers[5],callback,0,size)
		if error==OK: return
		exchange_fallbacks+=1
	# Preserve already-committed receipts if async readback is unsupported.
	callback.call(rd.buffer_get_data(_exchange.buffers[5],0,size))
func _exchange_received(bytes: PackedByteArray,batch: Dictionary) -> void:
	var receipt:=Exchange.decode(bytes,batch)
	receipt["serial"]=batch.serial;receipt["readback_bytes"]=bytes.size()
	_exchange_main.call_deferred(receipt)
func _exchange_main(receipt: Dictionary) -> void:
	exchange_busy=false
	exchange_readback_bytes+=receipt.readback_bytes
	exchange_ready.emit(receipt)
	if _closing and not exchange_busy: _finish_close()

func configure_interactions(mode: String, acid: float = 0.4) -> bool:
	if _started or mode not in ["off","contacts","collisions","chemistry"] or not is_finite(acid) or acid<0 or acid>1: return false
	interaction_mode=["off","contacts","collisions","chemistry"].find(mode)
	acidity=acid
	return true
func initialize(values: PackedFloat32Array, velocity: PackedVector2Array) -> void:
	if _started:
		push_error("Resident pool already initialized");return
	_started=true
	count = values.size()/12
	if count < 1 or count > 100000 or values.size()%12 != 0 or velocity.size()!=2560:
		_ready_main.call_deferred(false,"Invalid resident particle capacity or flow")
		return
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()=="gl_compatibility":
		_ready_main.call_deferred(false,"Requires Mobile/Forward+ and a real RenderingDevice display")
		return
	for k in range(0,values.size(),12):
		for j in 12:
			if not is_finite(values[k+j]):
				_ready_main.call_deferred(false,"Nonfinite particle state");return
		if values[k+7]<-1 or values[k+7]>10 or values[k+7]!=floor(values[k+7]) or values[k+9]<0 or values[k+10]<0 or (values[k+7]>=0 and (values[k+8]<=0 or values[k+8]>17)):
			_ready_main.call_deferred(false,"Invalid particle kind, material or diameter");return
		if exchange_enabled and values[k+11]!=0:
			_ready_main.call_deferred(false,"Product reserves are not supported by the exchange prototype");return
	while padded_count<count: padded_count*=2
	if exchange_enabled:
		_exchange_source=FileAccess.get_file_as_string("res://shaders/compute/resident_exchange.glsl.txt").replace("#[compute]","")
	if interaction_mode>0:
		for name in ["resident_contacts","resident_commit","resident_vote"]:
			contact_sources.append(FileAccess.get_file_as_string("res://shaders/compute/"+name+".glsl.txt").replace("#[compute]",""))
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
	if interaction_mode>0 and not _initialize_contacts():
		_ready_main.call_deferred(false,"Contact pipeline creation failed");return
	if exchange_enabled:
		_exchange=Exchange.new()
		if not _exchange.initialize(rd,state,count,contact_buffers[0],contact_buffers[1],_exchange_source):
			_ready_main.call_deferred(false,"Cell exchange pipeline creation failed");return
	upload_bytes += bytes.size()+velocities.size()
	_ready_main.call_deferred(true,"")
func _initialize_contacts() -> bool:
	for size in [padded_count*8,40960*8,count*4,count*64*4,count*4,16*4,count*8]:
		var buffer := rd.storage_buffer_create(size)
		contact_buffers.append(buffer)
		if not buffer.is_valid(): return false
	for text in contact_sources:
		var source := RDShaderSource.new()
		source.source_compute=text
		var spirv := rd.shader_compile_spirv_from_source(source)
		if spirv.compile_error_compute!="":
			push_error(spirv.compile_error_compute);return false
		var sh := rd.shader_create_from_spirv(spirv)
		contact_shaders.append(sh)
		var pipe := rd.compute_pipeline_create(sh)
		contact_pipelines.append(pipe)
		var uniforms: Array[RDUniform] = []
		for binding in 8:
			var u := RDUniform.new()
			u.binding=binding
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if binding==0 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id(state if binding==0 else contact_buffers[binding-1])
			uniforms.append(u)
		var uniform_set := rd.uniform_set_create(uniforms,sh,0)
		contact_sets.append(uniform_set)
		if not pipe.is_valid() or not uniform_set.is_valid(): return false
	return true
func interact_only() -> void:
	assert(interaction_mode>0 and not _closing)
	RenderingServer.call_on_render_thread(_contacts_rd)
func _contact_pass(stage: int, groups: int, level: int = 0, stride: int = 0, commit: bool = false) -> void:
	var params := PackedByteArray()
	params.resize(32)
	params.encode_u32(0,count);params.encode_u32(4,padded_count);params.encode_u32(8,stage)
	params.encode_u32(12,level);params.encode_u32(16,stride);params.encode_u32(20,interaction_mode)
	params.encode_float(24,acidity);params.encode_u32(28,reaction_tick)
	var index := (2 if stage==5 else 1) if commit else 0
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,contact_pipelines[index])
	rd.compute_list_bind_uniform_set(list,contact_sets[index],0)
	rd.compute_list_set_push_constant(list,params,32)
	rd.compute_list_dispatch(list,groups,1,1)
	rd.compute_list_end()
func _prepare_grid_rd() -> void:
	_contact_pass(0,ceili(maxi(padded_count,40960)/128.0))
	var level := 2
	while level<=padded_count:
		var stride := level/2
		while stride>0:
			_contact_pass(1,ceili(padded_count/128.0),level,stride)
			stride/=2
		level*=2
	_contact_pass(2,ceili(padded_count/128.0))
	_grid_valid=true
func _contacts_rd() -> void:
	_prepare_grid_rd()
	_contact_pass(3,ceili(count/128.0))
	if interaction_mode>=2:
		_contact_pass(5,ceili(count/128.0),0,0,true)
		_contact_pass(4,ceili(count/128.0),0,0,true)
	reaction_tick+=1
func contact_snapshot() -> void:
	RenderingServer.call_on_render_thread(_contact_snapshot_rd)
func _contact_snapshot_rd() -> void:
	var result := {}
	if not contact_buffers.is_empty():
		result={"counts":rd.buffer_get_data(contact_buffers[2]).to_int32_array(),
			"pairs":rd.buffer_get_data(contact_buffers[3]).to_int32_array(),
			"choices":rd.buffer_get_data(contact_buffers[4]).to_int32_array(),
			"stats":rd.buffer_get_data(contact_buffers[5]).to_int32_array()}
	readbacks+=1
	_contact_snapshot_main.call_deferred(result)
func _contact_snapshot_main(result: Dictionary) -> void: contacts_ready.emit(result)
func _ready_main(ok: bool, reason: String) -> void:
	_initialized=ok
	if ok: texture.texture_rd_rid=state
	ready.emit(ok,reason)
func advance(dt: float, tick: int) -> void:
	assert(dt>0 and dt<=2 and tick>=0 and tick<=0xffffffff and not _closing)
	RenderingServer.call_on_render_thread(_advance_rd.bind(dt,tick))
func _advance_rd(dt: float, tick: int) -> void:
	_grid_valid=false
	var params := PackedByteArray()
	params.resize(16);params.encode_u32(0,count);params.encode_float(4,dt);params.encode_u32(8,tick)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,bindings,0)
	rd.compute_list_set_push_constant(list,params,16)
	rd.compute_list_dispatch(list,ceili(count/128.0),1,1)
	rd.compute_list_end()
	if interaction_mode>0: _contacts_rd()
	dispatches += 1
	# Main device submission and barriers are owned by the renderer. No submit/sync.
func upload(values: PackedFloat32Array) -> void:
	if exchange_enabled or values.size()!=count*12 or _closing:
		push_error("Whole-pool upload is unavailable for exchange-owned slots");return
	var padded := values.duplicate()
	padded.resize(width*height*4)
	RenderingServer.call_on_render_thread(_upload_rd.bind(padded.to_byte_array()))
func _upload_rd(bytes: PackedByteArray) -> void:
	_grid_valid=false
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
	if exchange_busy: return
	_finish_close()
func _finish_close() -> void:
	if _close_queued: return
	_close_queued=true
	texture.texture_rd_rid=RID()
	RenderingServer.call_on_render_thread(_close_rd)
func _close_rd() -> void:
	if rd != null:
		if _exchange!=null: _exchange.close()
		for resource in contact_sets+contact_pipelines+contact_shaders+contact_buffers+[bindings,pipeline,shader,state,flow]:
			if resource.is_valid(): rd.free_rid(resource)
	rd=null # Main RenderingDevice belongs to Godot; never free it.
	_closed_main.call_deferred()
func _closed_main() -> void: closed.emit()
