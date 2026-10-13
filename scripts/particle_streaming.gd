extends RefCounted
## Disjoint CPU ownership outside the fixed widest-view GPU window.
const Regions=preload("res://scripts/particle_regions.gd")
const Transport=preload("res://scripts/particle_transport.gd")
const Medium=preload("res://scripts/medium.gd")
const Perception=preload("res://scripts/resident_perception.gd")
const HALO:=256.0
const ADMISSIONS:=256
var cold=Regions.new()
var center:=Vector2.ZERO
var half:=Vector2.ZERO
var prepared_center:=Vector2.ZERO
var prepared_half:=Vector2.ZERO
var borrowed: Array=[]
var held_chunks: Array=[]
var entered:=0
var exited:=0
var transported:=0
var queue_depth:=0
var eviction_deferred:=0
var last_ticket:=0
var _owner: WeakRef
var owner:
	get: return _owner.get_ref()
var requested_center:=Vector2.ZERO
var request_pending:=false
var region_due:=0.0
var regions: Array=[]
var multiview:=false
var random:=RandomNumberGenerator.new()

func initialize(bridge,sim) -> void:
	_owner=weakref(bridge);cold.dimensions=Vector2i(16,10);cold.kernels=sim.kernels
	random.seed=sim.seed_value ^ 0x71ea9
	update_region(sim)
	prepared_center=center;prepared_half=half

func request_view(at: Vector2) -> Vector2:
	requested_center=at;request_pending=true
	# Keep the displayed rectangle inside prepared water. Its margin uses the
	# widest footprint, so zooming never changes either simulation tier or route.
	var margin: Vector2=(half.min(prepared_half)-owner.detail_half-Vector2.ONE*128).max(Vector2.ZERO)
	var delta:=Medium.offset(prepared_center,at)
	var shift:=Medium.offset(prepared_center,center)
	return Medium.wrap_position(prepared_center+delta.clamp((-margin).max(shift-margin),margin.min(shift+margin)))

func minimum_zoom(size: Vector2) -> float:
	var available:=half.min(prepared_half)-Vector2.ONE*128
	return maxf(size.x/(2*maxf(1,available.x)),size.y/(2*maxf(1,available.y)))

func update_region(sim) -> void:
	multiview=sim.server_mode
	if multiview:
		regions.clear()
		for view in sim.camera_views:
			var c:=Medium.wrap_position((Vector2(view.x,view.y)/Regions.SIZE).floor()*Regions.SIZE+Vector2.ONE*Regions.SIZE*.5)
			var h:=((Vector2(view.z,view.w)+Vector2.ONE*HALO)/Regions.SIZE).ceil()*Regions.SIZE+Vector2.ONE*Regions.SIZE*.5
			regions.append(Vector4(c.x,c.y,h.x,h.y))
		return
	var at: Vector2=requested_center if request_pending else sim.player.position if sim.camera_follows_player else sim.camera_position
	var target:=Medium.wrap_position((at/Regions.SIZE).floor()*Regions.SIZE+Vector2.ONE*Regions.SIZE*.5)
	if half==Vector2.ZERO: center=target
	elif queue_depth==0 and eviction_deferred==0 and owner.pending.is_empty() and sim.time>=region_due:
		# Move at most one chunk per axis; even teleports/death succession prepare
		# an overlapping corridor instead of revealing uninitialized water.
		center=Medium.wrap_position(center+Medium.offset(center,target).clamp(-Vector2.ONE*Regions.SIZE,Vector2.ONE*Regions.SIZE))
		region_due=sim.time+.1
	half=((owner.detail_half+Vector2.ONE*HALO)/Regions.SIZE).ceil()*Regions.SIZE+Vector2.ONE*Regions.SIZE*.5

func contains(at: Vector2) -> bool:
	if multiview:
		for region in regions:
			var d:=Medium.offset(Vector2(region.x,region.y),at).abs()
			if d.x<region.z and d.y<region.w: return true
		return false
	var delta:=Medium.offset(center,at).abs()
	return delta.x<half.x and delta.y<half.y

func receive(sim,receipt: Dictionary) -> bool:
	if receipt.has("error"): return false
	if receipt.ticket<=last_ticket: return receipt.ticket==last_ticket
	cold.put_all(decode_transfer(sim,receipt),sim.time)
	last_ticket=receipt.ticket;exited+=receipt.count
	owner.alive-=receipt.count
	return true

func decode_transfer(sim,receipt: Dictionary) -> Array:
	var result: Array=[]
	var bytes: PackedByteArray=receipt.bytes
	for i in receipt.count:
		var at: int=i*128
		var packet: Dictionary=owner.decode(bytes.slice(at,at+48).to_float32_array(),-1,sim)
		owner.metadata(packet,bytes,at+48)
		packet.transport_at=receipt.time;packet.chemical_at=receipt.time
		result.append(packet)
	return result

func snapshots(sim) -> Array:
	var result: Array=cold.snapshots()
	var receipt: Dictionary=owner.gpu._transfer_pending
	if receipt.get("ticket",0)>last_ticket: result.append_array(decode_transfer(sim,receipt))
	return result

func advance(sim,packets: Array,force: bool=false) -> void:
	var ids: Array[int]=[]
	for i in packets.size():
		var packet: Dictionary=packets[i]
		if not packet.alive: continue
		if packet.kind==sim.PHEROMONE and packet.expires_at<=sim.time:
			packet.alive=false;sim.chemistry_events.decay+=1;continue
		var elapsed: float=maxf(0,sim.transport_clock-packet.get("transport_at",sim.transport_clock))
		if elapsed<=0 or (not force and elapsed<.5): continue
		ids.append(i)
		if sim.kernels==null:
			Transport.advance(packet,sim.fluid,elapsed,sim.revision,random)
			packet.transport_at=sim.transport_clock
	if sim.kernels!=null and not ids.is_empty():
		# Existing native large-step midpoint/Brownian integrator. The negative
		# activity rectangle selects the explicit borrowed IDs as cold everywhere.
		sim.kernels.transport(packets,ids,sim.fluid.velocity,Vector2.ZERO,-Vector2.ONE*256,0,sim.revision,random,sim.transport_clock,true)
	transported+=ids.size()

func _region_keys() -> Array:
	if not multiview: return cold.keys_in(center,half)
	var keys: Dictionary={}
	for region in regions:
		for key in cold.keys_in(Vector2(region.x,region.y),Vector2(region.z,region.w)): keys[key]=true
	return keys.keys()

func service(sim) -> bool:
	entered=0;transported=0
	update_region(sim)
	# Eviction and admission have fixed byte/packet ceilings, independent of the
	# number of stored chunks. Overflow remains owned, never silently dropped.
	if sim.revision%6==0:
		var receipt: Dictionary=owner.gpu.take_outside(Vector4.ZERO,regions,true) if multiview else owner.gpu.take_outside(Vector4(center.x,center.y,half.x,half.y))
		if not receive(sim,receipt): return false
		owner.gpu.acknowledge_transfer(receipt.ticket)
		eviction_deferred=receipt.deferred
	var moving: Array=cold.take_due(sim.time)
	advance(sim,moving)
	cold.put_all(moving,sim.time)
	var admission: Array=[]
	for key in _region_keys():
		if not contains((Vector2(key)+Vector2.ONE*.5)*Regions.SIZE): continue
		admission.append_array(cold.take(key,ADMISSIONS-admission.size()))
		if admission.size()>=ADMISSIONS: break
	advance(sim,admission,true)
	settle(sim,admission)
	for packet in admission:
		if not packet.alive: continue
		if contains(packet.p): owner.pending.append(packet);entered+=1
		else: cold.put(packet,sim.time)
	queue_depth=0
	for key in _region_keys():
		if contains((Vector2(key)+Vector2.ONE*.5)*Regions.SIZE):
			queue_depth+=cold.chunks[key].packets.size()-cold.chunks[key].head
	if queue_depth==0: prepared_center=center;prepared_half=half
	return true

func settle(sim,packets: Array) -> void:
	if packets.is_empty(): return
	# Promotion pays outstanding unary chemistry once before GPU admission.
	var held=sim.resident
	sim.resident=null;sim.particles=packets;sim.grid.rebuild(packets)
	var ids: Array[int]=[]
	for i in packets.size():
		if packets[i].alive and sim.time>packets[i].get("chemical_at",sim.time): ids.append(i)
	var prior: RandomNumberGenerator=sim.rng
	sim.rng=sim.ecology_rng
	if not ids.is_empty(): sim._chemistry(0,ids,true)
	sim.rng=prior;sim.particles=[];sim.grid.rebuild([]);sim.resident=held

func begin(sim,cells: Array,queries: Array=[],chemistry: bool=false) -> void:
	assert(borrowed.is_empty() and held_chunks.is_empty() and sim.particles.is_empty() and not sim.particle_pool)
	for query in queries: held_chunks.append_array(cold.borrow_region(query.at,Vector2.ONE*query.reach))
	for cell in cells: held_chunks.append_array(cold.borrow_region(cell.position,Vector2.ONE*(cell.extent()+160)))
	var ids: Array[int]=[]
	for chunk in held_chunks:
		chunk["rebin"]=chunk.transport_due<=sim.transport_clock
		if chunk.rebin:
			advance(sim,chunk.packets)
			chunk.transport_due=sim.transport_clock+.5
		if chemistry and chunk.chemical_due<=sim.time:
			for i in chunk.packets.size(): ids.append(borrowed.size()+i)
			chunk.chemical_due=sim.time+.5
		borrowed.append_array(chunk.packets)
	sim.resident=null;sim.particles=borrowed
	sim.pheromones=[] # Cold sensing queries the authoritative chunk workset.
	sim.grid.rebuild(borrowed)
	if sim.kernels!=null: sim.kernels.invalidate_particle_render()
	if not ids.is_empty():
		var previous_rng: RandomNumberGenerator=sim.rng
		sim.rng=sim.ecology_rng
		sim._chemistry(0,ids,true)
		sim.rng=previous_rng

func finish(sim) -> void:
	# Most queries only read or consume packets. Return these chunks as units;
	# only advected chunks need individual spatial rebinning. Dead slots are
	# reclaimed on that bounded/coarse transport visit.
	for chunk in held_chunks:
		if chunk.rebin: cold.put_all(chunk.packets,sim.time)
		else: cold.restore(chunk,sim.time)
	assert(sim.particles.size()==borrowed.size())
	held_chunks=[];borrowed=[];sim.particles=[];sim.pheromones=[];sim.grid.rebuild([]);sim.resident=owner

func sense(sim,query: Dictionary) -> Dictionary:
	var result: Dictionary={"food":{},"reports":{},"needed":false}
	var kind: int=sim.NUTRIENT if query.mode=="graze" else sim.WASTE if query.mode=="waste" else sim.TOXIN if query.mode=="toxin" else sim.PHEROMONE
	var candidates: Array[int]=sim.grid.query_kind(sim.particles,query.at,query.reach,kind)
	if query.mode in ["graze","hunt","flee"] and sim.kernels!=null and sim.kernels.has_method("packet_sense"):
		result=sim.kernels.packet_sense(sim.particles,candidates,query.at,query.reach,query.center,query.id,query.lineage,sim.time,query.mode=="graze")
		result["needed"]=false
		return result
	for index in candidates:
		var packet: Dictionary=sim.particles[index]
		if not packet.alive: continue
		var distance: float=Medium.offset(query.at,packet.p).length()
		if distance>query.reach: continue
		if query.mode in ["waste","toxin"]:
			if packet.kind==(sim.WASTE if query.mode=="waste" else sim.TOXIN) and (query.mode=="waste" or sim.inherited_lineages.get(packet.owner,packet.owner)!=query.lineage): result.needed=true
			continue
		if packet.owner==query.id: continue
		if query.mode=="graze" and packet.kind==sim.NUTRIENT and packet.amount>0:
			var delta:=Medium.offset(query.center,packet.p)
			var key:=Vector2i((delta/maxf(80,query.reach/4)).floor())
			if not result.food.has(key): result.food[key]={"mass":0.0,"moment":Vector2.ZERO,"nearest":delta,"distance":distance}
			var bin: Dictionary=result.food[key]
			bin.mass+=packet.amount;bin.moment+=delta*packet.amount
			if distance<bin.distance: bin.distance=distance;bin.nearest=delta
		elif query.mode in ["hunt","flee"] and packet.kind==sim.PHEROMONE and packet.expires_at>sim.time:
			var report: Dictionary=packet.report
			if report.lineage==query.lineage: continue
			if not result.reports.has(report.id) or result.reports[report.id].report.emitted_at<report.emitted_at:
				result.reports[report.id]={"report":report,"distance":distance,"expires_at":packet.expires_at}
	return result

func feed(sim,cells: Array,schedule: Dictionary) -> void:
	if sim.particles.is_empty(): return
	var prior: RandomNumberGenerator=sim.rng
	for cell in cells:
		if schedule.coarse.has(cell.id):
			sim.rng=sim.ecology_rng;sim.offscreen_ecology._feed(sim,cell,schedule.times[cell.id])
		else: sim.rng=prior;sim._feed(cell)
	sim.rng=prior

func expose(sim,cells: Array,schedule: Dictionary) -> void:
	if sim.particles.is_empty(): return
	var prior: RandomNumberGenerator=sim.rng
	var activities: Dictionary={}
	for cell in sim.cells:
		activities[cell.id]=cell.activity
		cell.activity=1.0 if cell in cells and not schedule.coarse.has(cell.id) else 0.0
	for cell in cells:
		if schedule.coarse.has(cell.id):
			sim.rng=sim.ecology_rng;sim.offscreen_ecology._exposure(sim,cell,schedule.times[cell.id])
	sim.rng=prior;sim._receptor_contacts();sim._toxin_contacts()
	for cell in sim.cells: cell.activity=activities[cell.id]
