extends RefCounted
## Bounded ownership transfer, distinct from whole-pool diagnostic snapshots.
const LIMIT:=512
const STRIDE:=128
var rd: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var bindings:=RID()
var output:=RID()
var count:=0
func initialize(device: RenderingDevice,state: RID,metadata: RID,identity: RID,slots: int,source: String) -> bool:
	rd=device;count=slots
	output=rd.storage_buffer_create(16+LIMIT*STRIDE)
	var text:=RDShaderSource.new();text.source_compute=source
	var spirv:=rd.shader_compile_spirv_from_source(text)
	if spirv.compile_error_compute!="": push_error(spirv.compile_error_compute);return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var uniforms: Array[RDUniform]=[]
	var resources: Array=[state,metadata,identity,output]
	for i in resources.size():
		var u:=RDUniform.new();u.binding=i;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if i==0 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.add_id(resources[i]);uniforms.append(u)
	bindings=rd.uniform_set_create(uniforms,shader,0)
	return pipeline.is_valid() and bindings.is_valid() and output.is_valid()
func take(region: Vector4) -> Dictionary:
	rd.buffer_clear(output,0,16)
	var pc:=PackedByteArray();pc.resize(32);pc.encode_u32(0,count);pc.encode_u32(4,LIMIT)
	for i in 4: pc.encode_float(16+i*4,region[i])
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,bindings,0)
	rd.compute_list_set_push_constant(list,pc,32);rd.compute_list_dispatch(list,ceili(count/128.0),1,1);rd.compute_list_end()
	var bytes:=rd.buffer_get_data(output)
	var found:=bytes.decode_u32(0)
	return {"bytes":bytes.slice(16,16+mini(found,LIMIT)*STRIDE),"count":mini(found,LIMIT),"deferred":maxi(0,found-LIMIT),"readback_bytes":bytes.size()}
func close() -> void:
	for resource in [bindings,pipeline,shader,output]:
		if resource.is_valid(): rd.free_rid(resource)
