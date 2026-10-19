extends RefCounted
const Catalog=preload("res://scripts/chemistry_catalog.gd")
## Resident unary chemistry and finite acid/buffer field exchange.
const RECEIPT_VECTORS:=775
var rd: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var partials:=RID()
var thinning_stats:=RID()
var carbon_stats:=RID()
var sets: Array[RID]=[]
var count:=0
var seed:=0
var last_dt:=0.0
var last_tick:=0
var last_time:=0.0
func initialize(device: RenderingDevice, state: RID, acid: RID, order: RID, ranges: RID, receipts: Array[RID], pair_stats: RID, identity: RID, events: RID, slots: int, random_seed: int, source: String) -> bool:
	rd=device;count=slots;seed=random_seed
	var zero:=PackedByteArray();zero.resize(ceili(count/128.0)*80)
	partials=rd.storage_buffer_create(zero.size(),zero)
	thinning_stats=rd.storage_buffer_create(32)
	carbon_stats=rd.storage_buffer_create(2560*16)
	var text:=RDShaderSource.new();text.source_compute=Catalog.glsl(source)
	var spirv:=rd.shader_compile_spirv_from_source(text)
	if spirv.compile_error_compute!="": push_error(spirv.compile_error_compute);return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	for receipt in receipts:
		var uniforms: Array[RDUniform]=[]
		var resources: Array=[state,acid,order,ranges,partials,receipt,pair_stats,identity,events,thinning_stats,carbon_stats]
		for i in resources.size():
			var uniform:=RDUniform.new();uniform.binding=i
			uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if i==0 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.add_id(resources[i]);uniforms.append(uniform)
		var bindings:=rd.uniform_set_create(uniforms,shader,0);sets.append(bindings)
		if not pipeline.is_valid() or not bindings.is_valid(): return false
	return partials.is_valid()
func dispatch(stage: int, groups: int, batch: Dictionary={}) -> void:
	var params:=PackedByteArray();params.resize(48)
	params.encode_u32(0,count);params.encode_u32(4,stage);params.encode_float(8,batch.get("probability",last_dt))
	params.encode_u32(12,int(batch.get("thin_serial",last_tick))&0xffffffff);params.encode_float(16,last_time)
	params.encode_u32(20,batch.get("chemistry_offset",0));params.encode_u32(24,ceili(count/128.0))
	params.encode_u32(28,seed&0xffffffff)
	var scope: Vector4=batch.get("count_scope",Vector4(0,0,-1,-1))
	params.encode_float(32,scope.x);params.encode_float(36,scope.y);params.encode_float(40,scope.z);params.encode_float(44,scope.w)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,sets[batch.get("ring_slot",0)],0)
	rd.compute_list_set_push_constant(list,params,48);rd.compute_list_dispatch(list,groups,1,1);rd.compute_list_end()
func advance(dt: float,tick: int,now: float) -> void:
	last_dt=dt;last_tick=tick;last_time=now
	dispatch(0,20);dispatch(1,ceili(count/128.0))
func receipt(batch: Dictionary) -> void:
	dispatch(2,ceili(count/128.0),batch);dispatch(3,1,batch)
static func decode(bytes: PackedByteArray,offset: int) -> Dictionary:
	var at:=offset*16
	var values:=bytes.slice(at,at+2560*4).to_float32_array()
	var losses:=bytes.slice(at+2560*4,at+2560*4+16).to_float32_array()
	var inventory:=bytes.slice(at+2560*4+16,at+2560*4+32).to_float32_array()
	var visible:=bytes.slice(at+774*16,at+775*16).to_float32_array()
	var cues: Array=[]
	for i in 128:
		var base:=at+(646+i)*16
		if bytes.decode_float(base+12)>0: cues.append({"at":Vector2(bytes.decode_float(base),bytes.decode_float(base+4)),"detox":bytes.decode_float(base+12)==2})
	return {"recycled":losses[2],"cues":cues,"acid":values,"loss":losses[0],"decay":int(losses[1]),"alive":int(inventory[0]),"pheromones":int(inventory[1]),
		"high_water":int(visible[3]),"visible":{"chemicals":int(visible[0]),"material":int(visible[1]),"signals":int(visible[2])},"material":inventory[2],"oxygen":inventory[3],"pairs":bytes.slice(at+2560*4+32,at+2560*4+96).to_int32_array()}
func thin(probability: float,serial: int) -> Dictionary:
	dispatch(4,ceili(count/128.0),{"probability":probability,"thin_serial":serial})
	dispatch(5,1)
	var bytes:=rd.buffer_get_data(thinning_stats)
	var values:=bytes.to_float32_array()
	return {"readback_bytes":bytes.size(),"loss":values[0],"removed":int(values[1]),"alive":int(values[2]),"signals":int(values[3]),"high_water":int(values[4]),"fuel_loss":values[5]}

func carbon_supply(cold: PackedFloat32Array,factor: float,target: float,phase: int=-1,phase_seed: int=0,kind: int=5,factors: PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	var input:=PackedFloat32Array();input.resize(2560*4)
	for i in 2560:
		input[i*4]=cold[i];input[i*4+1]=factors[i] if not factors.is_empty() else factor
	rd.buffer_update(carbon_stats,0,input.size()*4,input.to_byte_array())
	dispatch(6,20,{"probability":factor,"count_scope":Vector4(target,phase,kind,phase_seed)})
	var values:=rd.buffer_get_data(carbon_stats).to_float32_array()
	var added:=0.0;var removed:=0.0;var pending:=PackedFloat32Array();pending.resize(2560)
	var ratios:=PackedFloat32Array();ratios.resize(2560)
	for i in 2560:
		added+=maxf(0,values[i*4]);removed+=maxf(0,-values[i*4]);pending[i]=values[i*4+1];ratios[i]=values[i*4+2]
	return {"added":added,"removed":removed,"pending":pending,"ratios":ratios}

func close() -> void:
	for resource in sets+[pipeline,shader,partials,thinning_stats,carbon_stats]:
		if resource.is_valid(): rd.free_rid(resource)
