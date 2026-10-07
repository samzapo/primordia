extends RefCounted
## Stable bin-key radix sorting. Resources and dispatches live on the render thread.
var rd: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var sets: Array[RID]=[]
var buffers: Array[RID]=[]
var count:=0
var groups:=0
func initialize(device: RenderingDevice, order: RID, capacity: int, text: String) -> bool:
	rd=device;count=capacity;groups=ceili(count/128.0)
	for size in [count*8,groups*16*4,groups*16*4,16*4]:
		var buffer:=rd.storage_buffer_create(size);buffers.append(buffer)
		if not buffer.is_valid(): return false
	var source:=RDShaderSource.new();source.source_compute=text
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute!="": push_error(spirv.compile_error_compute);return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	for reverse in [false,true]:
		var resources: Array=[buffers[0] if reverse else order,order if reverse else buffers[0],buffers[1],buffers[2],buffers[3]]
		var uniforms: Array[RDUniform]=[]
		for i in resources.size():
			var u:=RDUniform.new();u.binding=i;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id(resources[i]);uniforms.append(u)
		var bindings:=rd.uniform_set_create(uniforms,shader,0);sets.append(bindings)
		if not bindings.is_valid(): return false
	return pipeline.is_valid()
func sort() -> void:
	for digit in 4:
		for stage in 3:
			var params:=PackedByteArray();params.resize(16)
			params.encode_u32(0,count);params.encode_u32(4,groups)
			params.encode_u32(8,digit*4);params.encode_u32(12,stage)
			var list:=rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(list,pipeline)
			rd.compute_list_bind_uniform_set(list,sets[digit%2],0)
			rd.compute_list_set_push_constant(list,params,16)
			rd.compute_list_dispatch(list,16 if stage==1 else groups,1,1)
			rd.compute_list_end()
func close() -> void:
	for resource in sets+[pipeline,shader]+buffers:
		if resource.is_valid(): rd.free_rid(resource)
