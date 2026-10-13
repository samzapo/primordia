extends RefCounted
const Catalog=preload("res://scripts/chemistry_catalog.gd")
## Bounded GPU exchange transport. It returns receipts; it never credits cells.
const MAX_BODIES:=64
const MAX_FEEDS:=256
const MAX_EMISSIONS:=256
const MAX_INSPECTIONS:=32
const MAX_POINTS:=8960
const MAX_RECEIPTS:=MAX_BODIES+MAX_FEEDS+MAX_EMISSIONS+MAX_INSPECTIONS*4+256*5+774+8512+256*385
var shader:=RID()
var pipeline:=RID()
var bindings: Array[RID]=[]
var receipt_buffers: Array[RID]=[]
var buffers: Array[RID]=[]
var camera_regions:=RID()
var rd: RenderingDevice
var count:=0
static func prepare(cells: Array, emissions: Array, handles: Array, feeding: bool=true, coarse: Dictionary={}) -> Dictionary:
	var bodies:=PackedFloat32Array()
	var points:=PackedVector2Array()
	var feeds:=PackedFloat32Array()
	var products:=PackedByteArray()
	var inspections:=PackedByteArray()
	if cells.size()>MAX_BODIES or emissions.size()>MAX_EMISSIONS or handles.size()>MAX_INSPECTIONS:
		return {"error":"Exchange capacity exceeded"}
	var body_ids: Array[int]=[]
	for cell in cells:
		if cell.id in body_ids: return {"error":"Duplicate body identity"}
		body_ids.append(cell.id)
		if cell.dead or cell.activity<=0 or cell.id<0 or cell.id>16777215:
			return {"error":"Only active living cells with exact numeric IDs may exchange"}
		var rates: Dictionary=coarse.get(cell.id,{})
		if not rates.is_empty():
			for name in ["dt","radius","nutrient","oxygen","carbon","seed"]:
				if not rates.has(name) or not (rates[name] is float or rates[name] is int) or not is_finite(rates[name]) or rates[name]<0:
					return {"error":"Invalid coarse encounter parameters"}
			if rates.dt<=0 or rates.radius<=0 or rates.seed>16777215 or floor(rates.seed)!=rates.seed:
				return {"error":"Invalid coarse interval, radius or seed"}
		var b: int=bodies.size()/16
		var visual: PackedVector2Array=cell.membrane.outline()
		var physical: PackedVector2Array=cell.membrane.points
		var start:=points.size()
		points.append_array(visual)
		var physical_start:=points.size()
		points.append_array(physical)
		if visual.size()<3 or physical.size()<3 or points.size()>MAX_POINTS:
			return {"error":"Invalid membrane geometry"}
		bodies.append_array(PackedFloat32Array([cell.position.x,cell.position.y,cell.angle,cell.extent(),
			start,visual.size(),physical_start,physical.size(),
			maxf(0,cell.gut_capacity()-cell.substrate),maxf(0,cell.oxygen_capacity()-cell.oxygen),
			maxf(0,float(preload("res://scripts/chemistry_catalog.gd").data().ecology.carbon_capacity)*cell.growth_scale()-cell.carbon),cell.id,rates.get("dt",0),rates.get("radius",0),rates.get("seed",0),0]))
		if feeding:
			var first := true
			for organ in cell.organs:
				if organ.kind!="feeding": continue
				var center: Vector2=cell.pore_center(organ) if rates.is_empty() else cell.position
				feeds.append_array(PackedFloat32Array([center.x,center.y,cell.pore_radius(organ)+8 if rates.is_empty() else rates.radius,0,b,rates.get("nutrient",0) if first else 0,rates.get("dt",0),0]))
				first=false
			feeds.append_array(PackedFloat32Array([cell.position.x,cell.position.y,cell.extent()+14 if rates.is_empty() else rates.radius,1,b,rates.get("oxygen",0),rates.get("dt",0),0]))
			if cell.count("photosynthesis")>0:
				feeds.append_array(PackedFloat32Array([cell.position.x,cell.position.y,cell.extent()+18 if rates.is_empty() else rates.radius,5,b,rates.get("carbon",0),rates.get("dt",0),0]))
	if feeds.size()/8>MAX_FEEDS: return {"error":"Too many feeding requests"}
	for v in bodies+feeds:
		if not is_finite(v): return {"error":"Nonfinite cell state"}
	for p in points:
		if not p.is_finite(): return {"error":"Nonfinite membrane"}
	for emission in emissions:
		if not emission is Dictionary or not emission.has("state") or not emission.has("owner"):
			return {"error":"Emission needs state and owner"}
		var value: PackedFloat32Array=emission.state
		if value.size()!=12 or emission.owner<-1 or emission.owner>2147483647:
			return {"error":"Invalid emission"}
		for v in value:
			if not is_finite(v): return {"error":"Nonfinite emission"}
		if value[7]<0 or value[7]>25 or floor(value[7])!=value[7] or value[8]<=0 or value[8]>17 or value[9]<=0 or value[10]<0 or value[11]!=0:
			return {"error":"Unsupported emission material, diameter or product reserve: "+str(value)}
		value=value.duplicate()
		value[0]=fposmod(value[0],4096);value[1]=fposmod(value[1],2560)
		var at:=products.size()
		products.append_array(value.to_byte_array());products.resize(at+64)
		products.encode_s32(at+48,emission.owner)
	for handle in handles:
		if not handle is Vector2i or handle.x<0 or handle.y<0:
			return {"error":"Invalid inspection handle"}
		var at:=inspections.size();inspections.resize(at+8)
		inspections.encode_u32(at,handle.x);inspections.encode_u32(at+4,handle.y)
	return {"bodies":bodies.to_byte_array(),"points":points.to_byte_array(),"feeds":feeds.to_byte_array(),
		"emissions":products,"inspections":inspections,
		"body_count":cells.size(),"feed_count":feeds.size()/8,"emit_count":emissions.size(),"inspect_count":handles.size()}
func initialize(device: RenderingDevice, texture: RID, slots: int, order: RID, ranges: RID, source: String, queue_depth: int=1) -> bool:
	rd=device;count=slots
	var zero:=PackedByteArray();zero.resize(144)
	camera_regions=rd.storage_buffer_create(144,zero)
	for size in [MAX_BODIES*64,MAX_POINTS*8,MAX_FEEDS*32,MAX_EMISSIONS*64,count*8,MAX_RECEIPTS*16,MAX_INSPECTIONS*8,MAX_BODIES*16,count*8]:
		var buffer:=rd.storage_buffer_create(size);buffers.append(buffer)
		if not buffer.is_valid(): return false
	var text:=RDShaderSource.new();text.source_compute=Catalog.glsl(source)
	var spirv:=rd.shader_compile_spirv_from_source(text)
	if spirv.compile_error_compute!="": push_error(spirv.compile_error_compute);return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	for slot in queue_depth:
		var receipt:=buffers[5] if slot==0 else rd.storage_buffer_create(MAX_RECEIPTS*16)
		receipt_buffers.append(receipt)
		if not receipt.is_valid(): return false
		var uniforms: Array[RDUniform]=[]
		var resources: Array=[texture]+buffers.slice(0,7)+[order,ranges,buffers[7],buffers[8],camera_regions]
		resources[6]=receipt
		for i in resources.size():
			var u:=RDUniform.new();u.binding=i
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if i==0 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id(resources[i]);uniforms.append(u)
		var set:=rd.uniform_set_create(uniforms,shader,0);bindings.append(set)
		if not pipeline.is_valid() or not set.is_valid(): return false
	dispatch(0,{},ceili(count/128.0))
	return true
func dispatch(stage: int, batch: Dictionary, groups: int) -> void:
	var params:=PackedByteArray();params.resize(48)
	params.encode_u32(0,count);params.encode_u32(4,batch.get("body_count",0))
	params.encode_u32(8,batch.get("feed_count",0));params.encode_u32(12,batch.get("emit_count",0))
	params.encode_u32(16,batch.get("inspect_count",0));params.encode_u32(20,stage)
	params.encode_u32(24,batch.get("accounts",0));params.encode_u32(28,1 if batch.get("parallel_oxygen",false) else 0)
	var scope: Vector4=batch.get("scope",Vector4(0,0,-1,-1))
	params.encode_float(32,scope.x);params.encode_float(36,scope.y);params.encode_float(40,scope.z);params.encode_float(44,scope.w)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,bindings[batch.get("ring_slot",0)],0)
	rd.compute_list_set_push_constant(list,params,48);rd.compute_list_dispatch(list,groups,1,1)
	rd.compute_list_end()
func upload(batch: Dictionary) -> int:
	var bytes:=0
	for pair in [[0,"bodies"],[1,"points"],[2,"feeds"],[3,"emissions"],[6,"inspections"]]:
		var data: PackedByteArray=batch[pair[1]]
		if not data.is_empty(): rd.buffer_update(buffers[pair[0]],0,data.size(),data);bytes+=data.size()
	return bytes
static func decode(bytes: PackedByteArray,batch: Dictionary) -> Dictionary:
	var result: Dictionary={"intake":[],"pores":[],"pore_fuel":[],"pore_contacts":[],"emissions":[],"inspections":[]}
	var at:=0
	for i in batch.body_count:
		result.intake.append(bytes.slice(at,at+16).to_float32_array());at+=16
	for i in batch.feed_count:
		result.pores.append(bytes.decode_float(at))
		result.pore_fuel.append(bytes.decode_float(at+4))
		result.pore_contacts.append(Vector2(bytes.decode_float(at+8),bytes.decode_float(at+12)))
		at+=16
	for i in batch.emit_count:
		result.emissions.append({"accepted":bytes.decode_u32(at)==1,"handle":Vector2i(bytes.decode_s32(at+4),bytes.decode_s32(at+8))});at+=16
	for i in batch.inspect_count:
		var valid:=bytes.decode_u32(at+48)==1
		result.inspections.append({"valid":valid,"state":bytes.slice(at,at+48).to_float32_array() if valid else PackedFloat32Array(),
			"owner":bytes.decode_s32(at+60) if valid else -1});at+=64
	return result
func close() -> void:
	for resource in bindings+[pipeline,shader]+buffers+receipt_buffers.slice(1)+[camera_regions]:
		if resource.is_valid(): rd.free_rid(resource)
	buffers.clear()

func set_views(views: Array,enabled: bool) -> void:
	var data:=PackedByteArray();data.resize(144)
	data.encode_u32(0,views.size());data.encode_u32(4,1 if enabled else 0)
	for i in views.size():
		for j in 4: data.encode_float(16+i*16+j*4,views[i][j])
	rd.buffer_update(camera_regions,0,144,data)
