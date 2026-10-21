extends RefCounted
## Immutable emission reports; no reference to live source cells.
const MAX_QUERIES:=1024 # All64 cells can own every free receptor plus demand queries.
const MAX_SOURCES:=1024
const SUMMARY_VECTORS:=385 # Header + 128 food bins or 64 complete reports.
const Genes=preload("res://scripts/mutations.gd")
var sources: Dictionary={}
var local_sources:=false # Hash/probe sources per query, never retain world history.
var rd: RenderingDevice
var buffers: Array[RID]=[]
var sets: Array[RID]=[]
var shader:=RID()
var pipeline:=RID()
var lineage_image:=RID() # Derived visualization metadata, never physical state.
var visual_lineages: Dictionary={}
var count:=0

static func integer(value, minimum: int=-1) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=minimum and value<=2147483647 and floor(float(value))==float(value)

func encode_metadata(item: Dictionary, kind: int, table: Dictionary) -> Dictionary:
	var owner=item.get("owner",-1)
	if not integer(owner): return {"error":"Invalid owner"}
	var bytes:=PackedByteArray();bytes.resize(64)
	bytes.encode_s32(48,owner)
	var lineage=item.get("lineage",owner)
	if not integer(lineage): return {"error":"Invalid chemical lineage"}
	bytes.encode_s32(52,lineage)
	if kind!=3: return {"bytes":bytes}
	if not item.get("report",{}) is Dictionary: return {"error":"Invalid pheromone report"}
	var report: Dictionary=item.get("report",{})
	for name in ["id","lineage","at","mass","radius","hostile","defended","emitted_at"]:
		if not report.has(name): return {"error":"Pheromone needs an immutable report"}
	if not integer(report.id,0) or not integer(report.lineage,0) or owner!=report.id:
		return {"error":"Invalid pheromone identity"}
	if not report.at is Vector2 or not report.at.is_finite() or not report.hostile is bool or not report.defended is bool:
		return {"error":"Invalid pheromone report"}
	for value in [report.mass,report.radius,report.emitted_at,item.get("expires_at",-1)]:
		if not (value is float or value is int) or not is_finite(value) or value<0 or value>1e30: return {"error":"Invalid report quantity or lifetime"}
	if item.expires_at<=report.emitted_at: return {"error":"Invalid report lifetime"}
	if not local_sources and not table.has(report.id):
		if table.size()>=MAX_SOURCES: return {"error":"Pheromone source capacity exceeded"}
		table[report.id]=table.size()
	for pair in [[0,report.at.x],[4,report.at.y],[8,report.mass],[12,report.radius],[32,report.emitted_at],[36,item.expires_at]]:
		bytes.encode_float(pair[0],pair[1])
	bytes.encode_s32(16,report.id);bytes.encode_s32(20,report.lineage)
	bytes.encode_u32(24,1 if report.hostile else 0);bytes.encode_u32(28,1 if report.defended else 0)
	if not visual_lineages.has(report.lineage) and visual_lineages.size()>=MAX_SOURCES:visual_lineages.erase(visual_lineages.keys()[0])
	visual_lineages[report.lineage]=true
	bytes.encode_u32(40,1);bytes.encode_u32(44,0 if local_sources else table[report.id])
	return {"bytes":bytes}

func prepare_initial(values: PackedFloat32Array, metadata: Array) -> Dictionary:
	var table: Dictionary={}
	var entries: Dictionary={}
	var bytes:=PackedByteArray();bytes.resize(values.size()/12*64)
	for item in metadata:
		if not item is Dictionary or not integer(item.get("slot",-1),0) or item.slot>=values.size()/12 or entries.has(int(item.slot)):
			return {"error":"Invalid or duplicate metadata slot"}
		entries[int(item.slot)]=item
	for i in values.size()/12:
		var encoded:=encode_metadata(entries.get(i,{}),int(values[i*12+7]),table)
		if encoded.has("error"): return encoded
		for j in 64: bytes[i*64+j]=encoded.bytes[j]
	sources=table
	return {"bytes":bytes}

func prepare_batch(emissions: Array, queries: Array) -> Dictionary:
	if queries.size()>MAX_QUERIES: return {"error":"Too many receptor queries"}
	var table:=sources.duplicate()
	var products:=PackedByteArray()
	for item in emissions:
		var encoded:=encode_metadata(item,int(item.state[7]),table)
		if encoded.has("error"): return encoded
		products.append_array(encoded.bytes)
	var requests:=PackedByteArray()
	for query in queries:
		if not query is Dictionary: return {"error":"Invalid receptor query"}
		for name in ["at","reach","id","lineage","mass","mode","target_id","incumbent"]:
			if not query.has(name): return {"error":"Incomplete receptor query"}
		if not query.at is Vector2 or not query.at.is_finite() or query.mode not in ["hunt","flee","graze","waste","toxin","inspect","family","danger"] or not query.incumbent is bool:
			return {"error":"Invalid receptor query"}
		if not integer(query.id,0) or not integer(query.lineage,0) or not integer(query.target_id):
			return {"error":"Invalid receptor identity"}
		if not (query.reach is float or query.reach is int) or not is_finite(query.reach) or query.reach<=0 or query.reach>4096 or not (query.mass is float or query.mass is int) or not is_finite(query.mass) or query.mass<0 or query.mass>1e30:
			return {"error":"Invalid receptor reach/mass"}
		if not query.get("center",query.at) is Vector2 or not (query.get("inner",70) is int or query.get("inner",70) is float):
			return {"error":"Invalid food-patch geometry"}
		var center: Vector2=query.get("center",query.at)
		var inner: float=query.get("inner",0 if query.mode=="inspect" else 70)
		if not center.is_finite() or not is_finite(inner) or inner<0: return {"error":"Invalid food-patch geometry"}
		var at:=requests.size();requests.resize(at+64)
		requests.encode_float(at,fposmod(query.at.x,4096));requests.encode_float(at+4,fposmod(query.at.y,2560))
		requests.encode_float(at+8,query.reach);requests.encode_float(at+12,query.mass)
		requests.encode_s32(at+16,query.id);requests.encode_s32(at+20,query.lineage)
		requests.encode_s32(at+24,query.target_id);requests.encode_u32(at+28,["hunt","flee","graze","waste","toxin","inspect","family","danger"].find(query.mode))
		requests.encode_u32(at+32,1 if query.incumbent else 0)
		requests.encode_float(at+48,fposmod(center.x,4096));requests.encode_float(at+52,fposmod(center.y,2560))
		requests.encode_float(at+56,inner)
	# Caller commits this table only after all exchange validation succeeds.
	return {"report_emissions":products,"queries":requests,"query_count":queries.size(),"sources":table}

static func requests(cells: Array, dt: float=0, now: float=0) -> Array:
	var result: Array=[]
	for cell in cells:
		var local_dt: float=dt*cell.activity
		if cell.dead or cell.activity<=0 or cell.sense_clock>local_dt: continue
		for organ in cell.organs:
			if organ.hp<=0 or organ.kind not in ["hunting","sensing","feeding","counterattack","family_toward","family_away"]: continue
			var mode: String="hunt" if organ.kind=="hunting" else "flee" if organ.kind=="counterattack" else "family" if organ.kind in ["family_toward","family_away"] else organ.mode
			if mode not in ["hunt","flee","graze","waste","toxin","inspect","family","danger"]: continue
			var reach: float=(120 if mode=="hunt" else 90 if mode in ["flee","family"] else 310)*sqrt(organ.scale)*(1-organ.blocked*0.65)*Genes.factor(organ,"sense")*cell.sensory_output(organ)
			result.append({"at":cell.organ_position(organ),"reach":reach,"id":cell.id,"lineage":cell.lineage_id(),
				"mass":cell.organic_mass(),"mode":mode,"target_id":cell.target_id,
				"incumbent":cell.target_memory>local_dt and cell.target_expires_at>now and (mode=="graze" or cell.target_lineage!=cell.lineage_id()) and cell.target_organ_id==organ.id and cell.target_mode==mode,
				"organ_id":organ.id,"output":cell.sensory_output(organ),"center":cell.position,"inner":maxf(70,cell.extent()+22)})
	# Flight reads actual toxin positions, independently of non-family reports.
	for cell in cells:
		if cell.dead or cell.activity<=0 or cell.sense_clock>dt*cell.activity:continue
		for organ in cell.organs:
			if organ.kind!="sensing" or organ.hp<=0:continue
			result.append({"at":cell.organ_position(organ),"reach":90*sqrt(organ.scale)*(1-organ.blocked*.65)*Genes.factor(organ,"sense"),"id":cell.id,"lineage":cell.lineage_id(),"mass":cell.organic_mass(),"mode":"danger","target_id":-1,"incumbent":false,"organ_id":organ.id,"center":cell.position})
	# One bounded extra chemical query per cell, at its first working social receptor.
	# A separate channel keeps hunter targets and family recognition independent.
	for cell in cells:
		var local_dt: float=dt*cell.activity
		if cell.dead or cell.activity<=0 or cell.sense_clock>local_dt:continue
		if cell.organs.any(func(organ):return organ.hp>0 and organ.kind in ["family_toward","family_away"]):continue
		for organ in cell.organs:
			if organ.hp<=0 or organ.kind not in ["feeding","hunting","sensing","counterattack"]:continue
			var reach: float=(120 if organ.kind=="hunting" else 90)*sqrt(organ.scale)*(1-organ.blocked*.65)*Genes.factor(organ,"sense")
			result.append({"at":cell.organ_position(organ),"reach":reach,"id":cell.id,"lineage":cell.lineage_id(),"mass":cell.organic_mass(),"mode":"family","target_id":-1,"incumbent":false,"organ_id":organ.id,"center":cell.position,"inner":70.0})
			break
	return result

static func for_cell(queries: Array, results: Array, cell) -> Dictionary:
	var received: Dictionary={}
	for i in queries.size():
		if queries[i].id!=cell.id: continue
		var reports: Dictionary={}
		var organ_id: int=queries[i].organ_id
		if queries[i].mode=="danger":
			if not received.has(organ_id):received[organ_id]={"food":{},"reports":{},"patch":{}}
			received[organ_id]["danger"]=results[i].get("danger",{})
			continue
		if queries[i].mode=="family":
			if not received.has(organ_id):received[organ_id]={"food":{},"reports":{},"patch":{}}
			if results[i].valid and results[i].has("report"):reports[results[i].report.id]=results[i]
			received[organ_id]["families"]=reports
			continue
		if queries[i].mode not in ["hunt","flee","graze"]:continue
		if results[i].valid and results[i].has("report"):reports[results[i].report.id]=results[i]
		var families: Dictionary=received.get(organ_id,{}).get("families",{})
		received[organ_id]={"food":{},"reports":reports,"families":families,"patch":results[i].get("patch",{}),"output":queries[i].get("output",1.0)}
	return received

func initialize(device: RenderingDevice, state: RID, identity: RID, order: RID, ranges: RID, receipts: Array[RID], initial: PackedByteArray, source: String, slots: int) -> bool:
	rd=device;count=slots
	# Reports, emitted reports, receptors, per-query latest-source scratch.
	for size in [count*64,256*64,MAX_QUERIES*64,MAX_QUERIES*MAX_SOURCES*16]:
		var buffer:=rd.storage_buffer_create(size,initial if buffers.is_empty() else PackedByteArray())
		buffers.append(buffer)
		if not buffer.is_valid(): return false
	var format:=RDTextureFormat.new();format.width=256;format.height=maxi(1,ceili(count/256.0));format.format=RenderingDevice.DATA_FORMAT_R32G32_SFLOAT;format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	lineage_image=rd.texture_create(format,RDTextureView.new())
	if not lineage_image.is_valid():return false
	var text:=RDShaderSource.new();text.source_compute=source
	var spirv:=rd.shader_compile_spirv_from_source(text)
	if spirv.compile_error_compute!="": push_error(spirv.compile_error_compute);return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	for receipt in receipts:
		var uniforms: Array[RDUniform]=[]
		var resources: Array=[state,identity,order,ranges,receipt]+buffers+[lineage_image]
		for i in resources.size():
			var uniform:=RDUniform.new();uniform.binding=i
			uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if i in [0,9] else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.add_id(resources[i]);uniforms.append(uniform)
		var bindings:=rd.uniform_set_create(uniforms,shader,0);sets.append(bindings)
		if not pipeline.is_valid() or not bindings.is_valid(): return false
	dispatch(0,{},0,ceili(count/64.0))
	return true

func upload(batch: Dictionary) -> int:
	var bytes:=0
	for pair in [[1,"report_emissions"],[2,"queries"]]:
		var data: PackedByteArray=batch[pair[1]]
		if not data.is_empty(): rd.buffer_update(buffers[pair[0]],0,data.size(),data);bytes+=data.size()
	return bytes

func dispatch(stage: int, batch: Dictionary, now: float, groups: int) -> void:
	var params:=PackedByteArray();params.resize(48)
	for pair in [[0,count],[4,stage],[8,batch.get("query_count",0)],[12,batch.get("source_count",0)],
		[16,batch.get("body_count",0)+batch.get("feed_count",0)],[20,batch.get("emit_count",0)],
		[24,batch.get("body_count",0)+batch.get("feed_count",0)+batch.get("emit_count",0)+batch.get("inspect_count",0)*4]]:
		params.encode_u32(pair[0],pair[1])
	params.encode_float(28,now)
	params.encode_u32(32,batch.get("summary_offset",0))
	params.encode_u32(36,1 if batch.get("summaries",false) else 0)
	params.encode_u32(40,1 if local_sources else 0)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,sets[batch.get("ring_slot",0)],0)
	rd.compute_list_set_push_constant(list,params,48);rd.compute_list_dispatch(list,maxi(groups,1),1,1)
	rd.compute_list_end()

static func summaries(bytes: PackedByteArray, offset: int, queries: int) -> Array:
	var result: Array=[]
	for i in queries:
		var at: int=(offset+i*SUMMARY_VECTORS)*16
		var item: Dictionary={"food":{},"reports":{}}
		var count: int=bytes.decode_u32(at)
		var kind: int=bytes.decode_u32(at+4)
		if bytes.decode_u32(at+8)!=0:
			item["error"]="Resident sensory summary overflow"
		elif kind==2:
			for j in count:
				var p:=at+16+j*48
				var key:=Vector2i(bytes.decode_s32(p),bytes.decode_s32(p+4))
				item.food[key]={"mass":bytes.decode_float(p+16),"moment":Vector2(bytes.decode_float(p+20),bytes.decode_float(p+24)),
					"distance":bytes.decode_float(p+28),"nearest":Vector2(bytes.decode_float(p+32),bytes.decode_float(p+36))}
		else:
			for j in count:
				var decoded: Dictionary=decode(bytes,at+16+j*80,1)[0]
				if decoded.valid: item.reports[decoded.report.id]=decoded
		result.append(item)
	return result

static func merge(local: Dictionary, remote: Dictionary) -> Dictionary:
	var result: Dictionary=remote.duplicate(true)
	for key in local.food:
		var part: Dictionary=local.food[key]
		if not result.food.has(key): result.food[key]=part.duplicate(true);continue
		var held: Dictionary=result.food[key]
		held.mass+=part.mass;held.moment+=part.moment
		if part.distance<held.distance: held.distance=part.distance;held.nearest=part.nearest
	for id in local.reports:
		var part: Dictionary=local.reports[id]
		if not result.reports.has(id) or part.report.emitted_at>result.reports[id].report.emitted_at:
			result.reports[id]=part
	return result

static func decode(bytes: PackedByteArray, at: int, queries: int) -> Array:
	var result: Array=[]
	for i in queries:
		var p:=at+i*80
		var valid:=bytes.decode_u32(p+40)==1 or bytes.decode_float(p+72)==4
		var item: Dictionary={"valid":valid}
		if bytes.decode_float(p+72)==3:
			push_error("Resident food bins overflowed")
			item["error"]="Food bins overflowed"
		if valid and bytes.decode_float(p+72)==2:
			item["patch"]={"at":Vector2(bytes.decode_float(p),bytes.decode_float(p+4)),"mass":bytes.decode_float(p+8),"inner":bytes.decode_float(p+12)!=0}
		elif valid and bytes.decode_float(p+72)==4:
			item["state"]=bytes.slice(p,p+48).to_float32_array()
			item["handle"]=Vector2i(bytes.decode_s32(p+48),bytes.decode_s32(p+52))
			item["owner"]=bytes.decode_s32(p+56)
		elif valid and bytes.decode_float(p+72)==6:
			item["danger"]={"at":Vector2(bytes.decode_float(p),bytes.decode_float(p+4)),"distance":bytes.decode_float(p+64)}
		elif valid and bytes.decode_float(p+72)!=5:
			item["report"]={"at":Vector2(bytes.decode_float(p),bytes.decode_float(p+4)),"mass":bytes.decode_float(p+8),
				"radius":bytes.decode_float(p+12),"id":bytes.decode_s32(p+16),"lineage":bytes.decode_s32(p+20),
				"hostile":bytes.decode_u32(p+24)!=0,"defended":bytes.decode_u32(p+28)!=0,"emitted_at":bytes.decode_float(p+32)}
			item["expires_at"]=bytes.decode_float(p+36)
			item["distance"]=bytes.decode_float(p+64)
			item["score"]=bytes.decode_float(p+68)
		result.append(item)
	return result

func close() -> void:
	for resource in sets+[pipeline,shader,lineage_image]+buffers:
		if resource.is_valid(): rd.free_rid(resource)
