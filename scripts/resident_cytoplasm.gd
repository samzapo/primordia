extends RefCounted
## Intracellular component of the main-device resident backend. GPU buffers own
## particles; GDScript holds anatomy, derived totals and exactly-once receipts.
const Catalog=preload("res://scripts/chemistry_catalog.gd")
const STRIDE:=80
# Control doubles: 0..7 slot/identity/clock/vacuole header; 20..26 cumulative
# chemistry; 32..50 species totals; 64..68 derived inventories; 70..84 current
# transaction result/body deltas; 96..127 flux/limits; 128..223 vacuoles.
const CONTROL_BYTES:=4096
const MAX_CAPACITY:=32
var rd: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var bindings:=RID()
var image:=RID()
var texture:=Texture2DRD.new()
var buffers: Array[RID]=[]
var backup: Array[RID]=[]
var _index_ready:=false
var _capacity_limit:=MAX_CAPACITY # Bounded infrastructure fixtures may lower this.
var capacity:=0
var count:=0
var live_count:=0
var calls:=0
var readback_bytes:=0
var exports:=0
var grows:=0
var chemistry: WeakRef
var body: WeakRef
var metadata: Dictionary={} # Sparse non-physical facts, never a pose/quantity mirror.
var species: Array=[]
var modules: Array=[]
var summary:=PackedByteArray()
var result:=PackedByteArray()
var transfer:=PackedByteArray()
var semaphore:=Semaphore.new()
var error:=""
var anatomy_dirty:=false
var source:=""
var closed:=false
var presentation: Array=[]
var presented_at:=-1000000

static func _table(name: String,values: Array,type: String="double") -> String:
	var parts:=PackedStringArray()
	for value in values:parts.append(str(value)+(".0" if value is int and type=="double" else ""))
	return "const %s %s[%d]=%s[%d](%s);\n" % [type,name,parts.size(),type,parts.size(),",".join(parts)]

func prepare(chem,cell) -> void:
	chemistry=weakref(chem);body=weakref(cell)
	species=Catalog.data().species.keys()
	var constants:="const int SPECIES=%d;\nconst int FOOD=%d;\nconst int WASTE=%d;\n" % [species.size(),species.find("food"),species.find("waste")]
	source=FileAccess.get_file_as_string("res://shaders/compute/resident_cytoplasm.glsl.txt").replace("/*CYTOPLASM_CATALOG*/",constants)
	capacity=32

func _pack(packets: Array) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(packets.size()*STRIDE)
	for i in packets.size():
		var packet: Dictionary=packets[i];var at:=i*STRIDE
		var facts:=packet.duplicate(true)
		for key in ["id","species","amount","fuel","p","previous","v","angle","source","compartment","alive"]:facts.erase(key)
		if not facts.is_empty():metadata[packet.id]=facts
		bytes.encode_float(at+44,0.0 if facts.is_empty() else 1.0)
		bytes.encode_double(at,packet.amount);bytes.encode_double(at+8,packet.fuel)
		for j in 7:bytes.encode_float(at+16+j*4,[packet.p.x,packet.p.y,packet.previous.x,packet.previous.y,packet.v.x,packet.v.y,packet.angle][j])
		bytes.encode_s32(at+48,species.find(packet.species));bytes.encode_u32(at+52,packet.source&0xffffffff);bytes.encode_u32(at+56,packet.compartment&0xffffffff);bytes.encode_s32(at+60,1 if packet.alive else 0)
		bytes.encode_s64(at+64,packet.id);bytes.encode_u32(at+72,(packet.source>>32)&0xffffffff);bytes.encode_u32(at+76,(packet.compartment>>32)&0xffffffff)
	return bytes

func _unpack(bytes: PackedByteArray) -> Array:
	var packets: Array=[]
	for i in bytes.size()/STRIDE:
		var at:=i*STRIDE
		if bytes.decode_s32(at+60)==0:continue
		packets.append({"id":bytes.decode_s64(at+64),"species":species[bytes.decode_s32(at+48)],"amount":bytes.decode_double(at),"fuel":bytes.decode_double(at+8),"p":Vector2(bytes.decode_float(at+16),bytes.decode_float(at+20)),"previous":Vector2(bytes.decode_float(at+24),bytes.decode_float(at+28)),"v":Vector2(bytes.decode_float(at+32),bytes.decode_float(at+36)),"angle":bytes.decode_float(at+40),"source":(int(bytes.decode_s32(at+72))<<32)|bytes.decode_u32(at+52),"compartment":(int(bytes.decode_s32(at+76))<<32)|bytes.decode_u32(at+56),"alive":true})
	for packet in packets:packet.merge(metadata.get(packet.id,{}),false)
	return packets

func _control(chem) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(CONTROL_BYTES)
	for pair in [[0,chem.particles.size()],[1,capacity],[2,chem.next_packet&0xffffffff],[3,chem.next_packet>>32],[4,chem.tick&0xffffffff],[5,chem.tick>>32],[7,chem.vacuoles.size()],[20,chem.heat],[21,chem.solar_work],[22,chem.expelled]]:bytes.encode_double(pair[0]*8,float(pair[1]))
	for j in chem.vacuoles.size():
		var v: Dictionary=chem.vacuoles[j]
		var values: Array=[v.id,v.p.x,v.p.y,v.radius,v.acid,v.material,v.age,0]
		for k in 8:bytes.encode_double((128+j*8+k)*8,float(values[k]))
	return bytes

func _anatomy(cell,external: float=.15) -> PackedByteArray:
	var chem=chemistry.get_ref();var values:=PackedFloat32Array();values.resize(768)
	values[0]=cell.radius;values[1]=cell.growth_scale();values[2]=cell.holes.size();values[3]=cell.biomass;values[7]=external
	values[8]=cell.id&0xffffffff;values[9]=cell.id>>32;values[10]=0
	var outlet: Vector2=cell.local_point(cell.excretion_angle())*.88
	values[12]=outlet.x;values[13]=outlet.y
	for j in chem.nodes.size():
		var node: Dictionary=chem.nodes[j];var at: Vector2=chem.site(node)
		for k in 6:values[32+j*8+k]=[node.id,modules.find(node.module),node.allocation,1 if node.enabled else 0,at.x,at.y][k]
	for j in 28:values[200+j*2]=cell.membrane.points[j].x;values[201+j*2]=cell.membrane.points[j].y
	for edge in chem.edges:
		var from: int=-1;var to: int=-1
		for j in chem.nodes.size():
			if chem.nodes[j].id==edge.from:from=j
			if chem.nodes[j].id==edge.to:to=j
		if from>=0 and to>=0:values[512+from*16+to]=int(values[512+from*16+to])|(1<<species.find(edge.species))
	return values.to_byte_array()

func initialize(device: RenderingDevice,packets: PackedByteArray,control: PackedByteArray,anatomy: PackedByteArray) -> bool:
	rd=device
	if packets.size()>capacity*STRIDE or control.decode_double(0)>24:
		error="Food/waste input exceeds bounded allocation";return false
	if capacity>_capacity_limit:error="Intracellular resident capacity exceeded";return false
	var code:=RDShaderSource.new();code.source_compute=source
	var spirv:=rd.shader_compile_spirv_from_source(code)
	if not spirv.compile_error_compute.is_empty():error=spirv.compile_error_compute;return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var initial:=packets.duplicate();initial.resize(capacity*STRIDE)
	buffers=[rd.storage_buffer_create(initial.size(),initial),rd.storage_buffer_create(CONTROL_BYTES,control),rd.storage_buffer_create(anatomy.size(),anatomy),rd.storage_buffer_create(256),rd.storage_buffer_create(256*STRIDE),rd.storage_buffer_create(256*species.size()*8),rd.storage_buffer_create(capacity*4)]
	backup=[rd.storage_buffer_create(capacity*STRIDE),rd.storage_buffer_create(CONTROL_BYTES)]
	var format:=RDTextureFormat.new();format.width=512;format.height=1;format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT;format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	image=rd.texture_create(format,RDTextureView.new())
	_rebind()
	return pipeline.is_valid() and bindings.is_valid()

func _rebind() -> void:
	if bindings.is_valid() and rd.uniform_set_is_valid(bindings):rd.free_rid(bindings)
	var uniforms: Array[RDUniform]=[]
	for j in buffers.size():
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=j if j<5 else j+1;u.add_id(buffers[j]);uniforms.append(u)
	var output:=RDUniform.new();output.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;output.binding=5;output.add_id(image);uniforms.append(output)
	bindings=rd.uniform_set_create(uniforms,shader,0)

func _dispatch(stage: int,groups: int=1) -> void:
	var push:=PackedByteArray();push.resize(4);push.encode_u32(0,stage)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,bindings,0);rd.compute_list_set_push_constant(list,push,4);rd.compute_list_dispatch(list,groups,1,1);rd.compute_list_end()

func attach(gpu,chem,cell) -> bool:
	if chem.particles.size()>chem.MAX_PACKETS or chem.particles.any(func(packet):return packet.species not in ["food","waste"]):
		error="Invalid food/waste carrier population; CPU ownership retained";return false
	prepare(chem,cell)
	var packets:=_pack(chem.particles);var control:=_control(chem);var anatomy:=_anatomy(cell)
	var ok: Array=[false]
	RenderingServer.call_on_render_thread(func():ok[0]=initialize(gpu.rd,packets,control,anatomy);semaphore.post())
	semaphore.wait()
	if not ok[0]:close();return false
	# Transfer only after successful initialization. The array is never a pose mirror.
	texture.texture_rd_rid=image
	chem.particles=[];chem.bins.clear();chem.accelerator=self
	command(12,0,Vector2.ZERO,0,-1,-1,-1,-1,0,species[0])
	return true

func command(code: int,q: float=0,at: Vector2=Vector2.ZERO,reach: float=0,dest: int=-1,source_id: int=-1,compartment: int=-1,fuel: float=-1,spread: float=0,key: String="food",extra: Dictionary={}) -> float:
	if closed or not error.is_empty():return 0.0
	var chem=chemistry.get_ref();var cell=body.get_ref()
	var args:=PackedFloat64Array([code,q,at.x,at.y,reach,dest,source_id,compartment,fuel,spread,species.find(key),0,0,source_id&0xffffffff,(source_id>>32)&0xffffffff,compartment&0xffffffff,(compartment>>32)&0xffffffff,cell.id&0xffffffff,(cell.id>>32)&0xffffffff]);args.resize(32)
	for index in extra:
		if index is int:args[index]=extra[index]
	var anatomy:=_anatomy(cell,float(extra.get("external",.15))) if code in [0,10,11] or anatomy_dirty else PackedByteArray()
	anatomy_dirty=false
	# This is a scalar deterministic solvent trial, not chemical state or RNG.
	if code==0:
		args[11]=1-exp(-.015*q)
		args[12]=fposmod(sin(float((chem.tick+1)*7919+cell.id*104729))*43758.5453,1)
	RenderingServer.call_on_render_thread(_execute.bind(args.to_byte_array(),anatomy,code))
	semaphore.wait();calls+=1;readback_bytes+=summary.size()+transfer.size()
	if not error.is_empty():push_error(error);return 0.0
	if texture.texture_rd_rid!=image:texture.texture_rd_rid=image
	_apply(summary,code)
	return summary.decode_double(70*8)

func _rebuild_index() -> void:
	_dispatch(5,ceili(256*species.size()/64.0));_dispatch(4);_index_ready=true

func _execute(args: PackedByteArray,anatomy: PackedByteArray,code: int) -> void:
	transfer=PackedByteArray()
	if not anatomy.is_empty():rd.buffer_update(buffers[2],0,anatomy.size(),anatomy)
	rd.buffer_update(buffers[3],0,args.size(),args)
	# Rollback and grow on device: overflow never consumes material or emits a
	# partial receipt, and no full particle download/upload is used for growth.
	while true:
		rd.buffer_copy(buffers[0],backup[0],0,0,capacity*STRIDE);rd.buffer_copy(buffers[1],backup[1],0,0,CONTROL_BYTES)
		_dispatch(0)
		_dispatch(2)
		summary=rd.buffer_get_data(buffers[1])
		if summary.decode_double(6*8)==0:break
		rd.buffer_copy(backup[0],buffers[0],0,0,capacity*STRIDE);rd.buffer_copy(backup[1],buffers[1],0,0,CONTROL_BYTES)
		if capacity>=_capacity_limit:
			summary=rd.buffer_get_data(buffers[1])
			error="Intracellular resident capacity exhausted; transaction rolled back";semaphore.post();return
		var larger:=mini(_capacity_limit,capacity*2);var state:=rd.storage_buffer_create(larger*STRIDE)
		rd.buffer_copy(buffers[0],state,0,0,capacity*STRIDE);rd.free_rid(buffers[0]);rd.free_rid(backup[0]);buffers[0]=state;backup[0]=rd.storage_buffer_create(larger*STRIDE);capacity=larger;grows+=1
		rd.free_rid(buffers[6]);buffers[6]=rd.storage_buffer_create(larger*4)
		var size:=PackedByteArray();size.resize(8);size.encode_double(0,float(capacity));rd.buffer_update(buffers[1],8,8,size);_rebind()
	count=int(summary.decode_double(0))
	if code!=2:_dispatch(3,maxi(1,ceili(count/64.0)))
	if code==11 and summary.decode_double(70*8)>0:transfer=rd.buffer_get_data(buffers[4],0,int(summary.decode_double(70*8))*STRIDE)
	semaphore.post()

func _apply(bytes: PackedByteArray,code: int) -> void:
	var chem=chemistry.get_ref();var cell=body.get_ref()
	var incoming_count:=int(bytes.decode_double(68*8))
	var incoming_id:=int(bytes.decode_double(2*8))|(int(bytes.decode_double(3*8))<<32)
	if incoming_count!=live_count or incoming_id!=chem.next_packet:presented_at=-1000000
	live_count=incoming_count;count=int(bytes.decode_double(0))
	chem.next_packet=int(bytes.decode_double(2*8))|(int(bytes.decode_double(3*8))<<32);chem.tick=int(bytes.decode_double(4*8))|(int(bytes.decode_double(5*8))<<32)
	for j in species.size():chem.totals[species[j]]=bytes.decode_double((32+j)*8)
	for pair in [["heat",20],["solar_work",21]]:chem.set(pair[0],bytes.decode_double(pair[1]*8))
	chem.vacuoles.clear()
	for j in int(bytes.decode_double(7*8)):
		var base:=128+j*8
		chem.vacuoles.append({"id":int(bytes.decode_double(base*8)),"p":Vector2(bytes.decode_double((base+1)*8),bytes.decode_double((base+2)*8)),"radius":bytes.decode_double((base+3)*8),"acid":bytes.decode_double((base+4)*8),"material":bytes.decode_double((base+5)*8),"age":bytes.decode_double((base+6)*8)})
	cell.biomass+=bytes.decode_double(80*8);cell.health=maxf(0,cell.health+bytes.decode_double(81*8))
	var gained:=bytes.decode_double(82*8)
	if gained>0:cell.gain_energy(gained)
	cell.processed+=bytes.decode_double(83*8);cell.fermented+=bytes.decode_double(84*8)
	if bytes.decode_double(84*8)>0:cell.fermentation_activity=2
	if bytes.decode_double(81*8)<0:cell.death_hint="Osmotic overload; contractile pumping failed"

func advance(dt: float,external: float) -> void:
	var chem=chemistry.get_ref();chem.frame_dt=dt
	command(0,dt,Vector2.ZERO,0,-1,-1,-1,-1,0,"food",{"external":external})

func value(index: int) -> float:return summary.decode_double(index*8) if not summary.is_empty() else 0.0

func snapshot(present: bool=false) -> Array:
	if count==0:return []
	if present and Time.get_ticks_msec()-presented_at<100:return presentation
	RenderingServer.call_on_render_thread(func():result=rd.buffer_get_data(buffers[0],0,maxi(1,count)*STRIDE);semaphore.post())
	semaphore.wait();exports+=1;readback_bytes+=result.size()
	var packets:=_unpack(result)
	if present:presentation=packets;presented_at=Time.get_ticks_msec()
	return packets

func release() -> void:
	if closed:return
	var chem=chemistry.get_ref();var packets:=snapshot()
	chem.accelerator=null;chem.particles=packets;chem.bins.clear()
	for packet in packets:chem._index(packet)
	close()

func close() -> void:
	if closed:return
	closed=true;texture.texture_rd_rid=RID()
	RenderingServer.call_on_render_thread(func():
		if rd!=null:
			for rid in [bindings,pipeline,shader,image]+buffers+backup:
				if rid.is_valid():rd.free_rid(rid)
			rd=null
		semaphore.post())
	semaphore.wait()
