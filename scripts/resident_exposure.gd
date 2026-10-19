extends RefCounted
## Ordered finite contact events for CPU membrane damage and receptor blockage.
const HITS_PER_BODY:=128
const MAX_DECOYS:=1024 # Includes both new family receptors on every pond cell.
const MAX_RECEIPT_VECTORS:=64*(HITS_PER_BODY+1)+MAX_DECOYS
var camera_regions:=RID()
var rd: RenderingDevice
var buffers: Array[RID]=[]
var sets: Array[RID]=[]
var shader:=RID()
var pipeline:=RID()
var count:=0
static func prepare(cells: Array) -> Dictionary:
	var info:=PackedByteArray()
	var decoys:=PackedFloat32Array()
	var organ_ids: Array[int]=[]
	var organ_bodies: Array[int]=[]
	for b in cells.size():
		var cell=cells[b]
		var start:=organ_ids.size()
		for organ in cell.organs:
			if organ.kind not in ["feeding","sensing","hunting","family_toward","family_away"]: continue
			var at: Vector2=cell.organ_position(organ)
			var normal: Vector2=cell.organ_normal(organ).rotated(cell.angle)
			decoys.append_array(PackedFloat32Array([at.x,at.y,normal.x,normal.y,12*organ.scale,b,0,0]))
			organ_ids.append(organ.id);organ_bodies.append(b)
		var at:=info.size();info.resize(at+16)
		info.encode_s32(at,cell.id);info.encode_s32(at+4,cell.lineage_id())
		info.encode_u32(at+8,start);info.encode_u32(at+12,(organ_ids.size()-start)|(0x80000000 if not cell.surface_complexes.is_empty() else 0))
	if organ_ids.size()>MAX_DECOYS: return {"error":"Too many contact receptors"}
	return {"body_info":info,"decoys":decoys.to_byte_array(),"decoy_count":organ_ids.size(),
		"decoy_organs":organ_ids,"decoy_bodies":organ_bodies}
func initialize(device: RenderingDevice, state: RID, identity: RID, reports: RID, bodies: RID, points: RID, order: RID, ranges: RID, receipts: Array[RID], slots: int, source: String) -> bool:
	rd=device;count=slots
	var zero:=PackedByteArray();zero.resize(144)
	camera_regions=rd.storage_buffer_create(144,zero)
	for size in [64*16,MAX_DECOYS*32,count*8]:
		var buffer:=rd.storage_buffer_create(size);buffers.append(buffer)
		if not buffer.is_valid(): return false
	var text:=RDShaderSource.new();text.source_compute=source
	var spirv:=rd.shader_compile_spirv_from_source(text)
	if spirv.compile_error_compute!="": push_error(spirv.compile_error_compute);return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	for receipt in receipts:
		var resources: Array=[state,identity,reports,bodies,points,buffers[0],buffers[1],buffers[2],order,ranges,receipt,camera_regions]
		var uniforms: Array[RDUniform]=[]
		for i in resources.size():
			var uniform:=RDUniform.new();uniform.binding=i
			uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if i==0 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.add_id(resources[i]);uniforms.append(uniform)
		var bindings:=rd.uniform_set_create(uniforms,shader,0);sets.append(bindings)
		if not pipeline.is_valid() or not bindings.is_valid(): return false
	return true
func upload(batch: Dictionary) -> int:
	var bytes:=0
	for pair in [[0,"body_info"],[1,"decoys"]]:
		var data: PackedByteArray=batch[pair[1]]
		if not data.is_empty(): rd.buffer_update(buffers[pair[0]],0,data.size(),data);bytes+=data.size()
	return bytes
func dispatch(stage: int, batch: Dictionary) -> void:
	var params:=PackedByteArray();params.resize(32)
	params.encode_u32(0,count);params.encode_u32(4,batch.body_count);params.encode_u32(8,stage);params.encode_u32(12,batch.exposure_offset)
	var scope: Vector4=batch.get("scope",Vector4(0,0,-1,-1))
	params.encode_float(16,scope.x);params.encode_float(20,scope.y);params.encode_float(24,scope.z);params.encode_float(28,scope.w)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,sets[batch.ring_slot],0)
	rd.compute_list_set_push_constant(list,params,32)
	rd.compute_list_dispatch(list,ceili(count/128.0) if stage==0 else maxi(1,batch.body_count),1,1)
	rd.compute_list_end()
static func decode(bytes: PackedByteArray,batch: Dictionary) -> Dictionary:
	var at: int=batch.exposure_offset*16
	var hits: Array=[]
	var deferred:=0
	for b in batch.body_count:
		var start: int=at+b*(HITS_PER_BODY+1)*16
		var n:=int(bytes.decode_float(start))
		deferred+=int(bytes.decode_float(start+4))
		var events: Array=[]
		for k in n:
			var p: int=start+(k+1)*16
			events.append({"amount":bytes.decode_float(p),"angle":bytes.decode_float(p+4),"slot":bytes.decode_u32(p+8)&0x0fffffff,"kind":(bytes.decode_u32(p+8)>>28) if (bytes.decode_u32(p+8)>>28)>0 else 4,"owner":bytes.decode_s32(p+12)})
		hits.append(events)
	var decoys: Array=[]
	at+=batch.body_count*(HITS_PER_BODY+1)*16
	for i in batch.decoy_count:
		decoys.append({"count":int(bytes.decode_float(at+i*16)),"amount":bytes.decode_float(at+i*16+4),
			"body":batch.decoy_bodies[i],"organ_id":batch.decoy_organs[i]})
	return {"hits":hits,"decoys":decoys,"deferred":deferred}
func close() -> void:
	for resource in sets+[pipeline,shader]+buffers+[camera_regions]:
		if resource.is_valid(): rd.free_rid(resource)

func set_views(views: Array,enabled: bool) -> void:
	var data:=PackedByteArray();data.resize(144)
	data.encode_u32(0,views.size());data.encode_u32(4,1 if enabled else 0)
	for i in views.size():
		for j in 4: data.encode_float(16+i*16+j*4,views[i][j])
	rd.buffer_update(camera_regions,0,144,data)
