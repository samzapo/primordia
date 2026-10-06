extends RefCounted
## Experimental synchronous CPU bridge. Never selected automatically: benchmark it.
const Medium = preload("res://scripts/medium.gd")
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var state := RID()
var flow := RID()
var uniform_set := RID()
var capacity := 0
var data := PackedFloat32Array()
var metrics: Dictionary = {}
func initialize() -> bool:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" or DisplayServer.get_name() == "headless": return false
	rd = RenderingServer.create_local_rendering_device()
	if rd == null: return false
	var source := RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string("res://shaders/compute/transport.glsl").replace("#[compute]","")
	var spirv := rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "":
		push_error(spirv.compile_error_compute)
		close()
		return false
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	flow = rd.storage_buffer_create(64*40*8)
	if not pipeline.is_valid():
		close()
		return false
	return true
func reserve(count: int) -> void:
	if count <= capacity: return
	if uniform_set.is_valid(): rd.free_rid(uniform_set)
	if state.is_valid(): rd.free_rid(state)
	capacity = 256
	while capacity < count: capacity *= 2
	state = rd.storage_buffer_create(capacity*48)
	var a := RDUniform.new()
	a.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	a.binding = 0
	a.add_id(state)
	var b := RDUniform.new()
	b.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	b.binding = 1
	b.add_id(flow)
	uniform_set = rd.uniform_set_create([a,b],shader,0)
func upload(values: PackedFloat32Array, velocity: PackedVector2Array) -> void:
	reserve(values.size()/12)
	var bytes := values.to_byte_array()
	rd.buffer_update(state,0,bytes.size(),bytes)
	bytes = velocity.to_byte_array()
	rd.buffer_update(flow,0,bytes.size(),bytes)
func dispatch(count: int, dt: float, repeats: int = 1) -> void:
	var params := PackedByteArray()
	params.resize(16)
	params.encode_u32(0,count)
	params.encode_float(4,dt)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,uniform_set,0)
	rd.compute_list_set_push_constant(list,params,16)
	for i in repeats:
		rd.compute_list_dispatch(list,ceili(count/128.0),1,1)
		if i+1 < repeats: rd.compute_list_add_barrier(list)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
func download(count: int) -> PackedFloat32Array:
	return rd.buffer_get_data(state,0,count*48).to_float32_array()
func step(particles: Array, ids: Array[int], velocity: PackedVector2Array, camera: Vector2, half: Vector2, dt: float, revision: int, rng: RandomNumberGenerator, clock: float = -1.0) -> int:
	var begin := Time.get_ticks_usec()
	var active: Array[int] = []
	data.resize(ids.size()*12)
	for id in ids:
		var p: Dictionary = particles[id]
		if not p.alive: continue
		var visibility := Medium.visibility(p.p,camera,half)
		if visibility <= 0: continue
		var elapsed := dt if clock < 0 else maxf(0,clock-float(p.get("transport_at",clock-dt)))
		if elapsed <= 0: continue
		var k := active.size()*12
		active.append(id)
		data[k]=p.p.x; data[k+1]=p.p.y; data[k+2]=p.angle; data[k+3]=p.spin
		data[k+4]=p.v.x; data[k+5]=p.v.y; data[k+6]=p.age; data[k+7]=p.kind
		data[k+8]=rng.randfn(); data[k+9]=rng.randfn(); data[k+10]=rng.randfn(); data[k+11]=elapsed/dt
	data.resize(active.size()*12)
	if active.is_empty(): return 0
	var packed := Time.get_ticks_usec()
	upload(data,velocity)
	dispatch(active.size(),dt)
	data = download(active.size())
	var transferred := Time.get_ticks_usec()
	for i in active.size():
		var p: Dictionary = particles[active[i]]
		var k := i*12
		p.transport_jump = (dt if clock < 0 else clock-float(p.get("transport_at",clock-dt))) > 0.05
		if clock >= 0: p.transport_at=clock
		p.previous=p.p; p.previous_angle=p.angle; p.updated=revision
		p.p=Vector2(data[k],data[k+1]); p.angle=data[k+2]
		p.v=Vector2(data[k+4],data[k+5]); p.age=data[k+6]
		p.direction=Vector2.ZERO if p.kind == 3 else Vector2.from_angle(p.angle)
	metrics={"pack_us":packed-begin,"gpu_roundtrip_us":transferred-packed,"unpack_us":Time.get_ticks_usec()-transferred}
	return active.size()
func close() -> void:
	if rd == null: return
	for resource in [uniform_set,state,flow,pipeline,shader]:
		if resource.is_valid(): rd.free_rid(resource)
	rd.free()
	rd = null
