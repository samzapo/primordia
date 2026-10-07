extends RefCounted
## Desktop resident-particle gameplay bridge. Cells retain all resource authority.
const GPU=preload("res://scripts/resident_particles.gd")
const Perception=preload("res://scripts/resident_perception.gd")
var gpu=GPU.new()
var world: WeakRef
var pending: Array=[]
var trace_emissions: Dictionary={}
var alive:=0
var signals:=0
var needed: Dictionary={}
var last_chemistry: Dictionary={}
var last_tick:=-1
var ready:=false
var closing:=false
var reason:=""
var capacity:=65536
var elapsed_usec:=0
var fallback_reason:=""
signal returned_to_cpu(message: String)
signal initialized(ok: bool, message: String)

func start(sim, slots: int=65536) -> void:
	world=weakref(sim);capacity=slots
	sim.disable_particle_pool()
	var packets: Array=sim.particles
	if packets.size()>capacity:
		initialized.emit(false,"Starting particle count exceeds resident capacity");return
	var values:=PackedFloat32Array();values.resize(capacity*12)
	for i in capacity: values[i*12+7]=-1
	var metadata: Array=[]
	for i in packets.size():
		var packet: Dictionary=packets[i]
		var encoded:=encode(packet,sim)
		for j in 12: values[i*12+j]=encoded.state[j]
		encoded.erase("state");encoded["slot"]=i;metadata.append(encoded)
		if packet.alive: alive+=1
		if packet.alive and packet.kind==3: signals+=1
	gpu.configure_interactions("chemistry");gpu.configure_exchange()
	gpu.configure_perception(sim.time);gpu.configure_chemistry(sim.acidity.values,sim.seed_value);gpu.configure_exposure()
	gpu.ready.connect(func(ok: bool,message: String):
		reason=message
		if closing: initialized.emit(false,"Initialization cancelled");return
		if ok:
			sim.particles=[];sim.pheromones=[];sim.grid.rebuild([])
			sim.resident=self;sim.particle_engine="resident";sim.fluid.global_coupling=true
			ready=true
		else:
			gpu.close();sim.enable_particle_pool()
		initialized.emit(ok,message),CONNECT_ONE_SHOT)
	gpu.initialize(values,sim.fluid.velocity,metadata)

static func encode(p: Dictionary,sim) -> Dictionary:
	var diameter: float=2*sim.particle_radius(p.kind)*sim.particle_scale(p.amount)
	var data: Dictionary={"state":PackedFloat32Array([p.p.x,p.p.y,p.angle,p.spin,p.v.x,p.v.y,p.get("age",0),p.kind if p.alive else -1,
		diameter,p.amount if p.alive else 0,p.get("capacity",p.amount),0]),"owner":p.owner,"lineage":sim.inherited_lineages.get(p.owner,p.owner)}
	if p.kind==3: data["report"]=p.get("report",{});data["expires_at"]=p.get("expires_at",0)
	return data

func enqueue(packet: Dictionary) -> void:
	# Photosynthesis can release a double-precision remainder smaller than one
	# float32 packet. Retain that paid material until another release makes a
	# representable packet; never create a minimum dose or silently discard it.
	var key:=Vector2i(packet.owner,packet.kind)
	if packet.amount>=1e-20 and not trace_emissions.has(key):
		pending.append(packet);return
	if trace_emissions.has(key):
		var held: Dictionary=trace_emissions[key]
		held.amount+=packet.amount;held.capacity+=packet.capacity
		held.p=packet.p;held.previous=packet.previous
	else: trace_emissions[key]=packet
	if trace_emissions[key].amount>=1e-20:
		pending.append(trace_emissions[key]);trace_emissions.erase(key)

func _living(sim) -> Array:
	return sim.cells.filter(func(c): return not c.dead)

func _queries(sim, cells: Array,dt: float) -> Array:
	var queries:=Perception.requests(cells,dt,sim.time)
	for cell in cells:
		for organ in cell.organs:
			if organ.kind not in ["feeding","neutralizing"]: continue
			queries.append({"at":cell.organ_position(organ),"reach":140*sqrt(organ.scale),"id":cell.id,
				"lineage":cell.lineage_id(),"mass":cell.organic_mass(),"mode":"waste" if organ.kind=="feeding" else "toxin",
				"target_id":-1,"incumbent":false,"organ_id":organ.id})
	return queries

func _receipt(cells: Array=[],queries: Array=[],options: Dictionary={}) -> Dictionary:
	var sim=world.get_ref()
	# Paid output remains escrowed until the device accepts it. Do not discard a
	# death burst just because one emission batch has fewer slots.
	while pending.size()>256:
		var extra:=_receipt_batch([],[],{"feeding":false,"projection":false},256)
		if extra.has("error"): return extra
		if extra.get("_capacity",false): return {"error":"Particle capacity reached; preserved paid emissions"}
	return _receipt_batch(cells,queries,options,pending.size())

func _receipt_batch(cells: Array,queries: Array,options: Dictionary,n: int) -> Dictionary:
	var sim=world.get_ref()
	var products: Array=[]
	for i in n: products.append(encode(pending[i],sim))
	var result: Dictionary=gpu.exchange_sync(cells,products,[],queries,options)
	if result.has("error"): return result
	var refused: Array=[]
	for i in n:
		if not result.emissions[i].accepted: refused.append(pending[i])
	pending=refused+pending.slice(n)
	if result.has("chemistry"): _account_chemistry(result.chemistry)
	if not refused.is_empty(): result["_capacity"]=true
	return result

func _account_chemistry(chemistry: Dictionary) -> void:
	var sim=world.get_ref()
	last_chemistry=chemistry
	alive=chemistry.alive;signals=chemistry.pheromones
	sim.active_particles=alive
	sim.acidity.values=chemistry.acid
	if chemistry.tick!=last_tick:
		last_tick=chemistry.tick
		sim.respiration_loss+=chemistry.loss
		sim.recycled+=chemistry.recycled
		for cue in chemistry.cues:
			sim._record_reaction(cue.at)
			if cue.detox: sim._record_sound("neutralize",cue.at,-1)
		sim.chemistry_events.decay+=chemistry.decay
		for pair in [["enzyme",5],["neutralize",6],["recycle",8],["spoil",9],["combine",10]]:
			sim.chemistry_events[pair[0]]+=chemistry.pairs[pair[1]]

func step(dt: float) -> void:
	var sim=world.get_ref()
	if not ready or sim.evolution.terminal() or sim.build_original!=null or (sim.player.dead and not sim.evolution.enabled): return
	var start:=Time.get_ticks_usec()
	sim.time+=dt;sim.transport_clock+=dt;sim.revision+=1
	sim.profile_counts.clear();sim.profile_usec.clear()
	for name in ["sensing","feeding","organ_geometry","traction","membrane","contacts","coarse_chemistry","coarse_feeding","coarse_motion"]:
		sim.profile_usec[name]=0
	var mark:=Time.get_ticks_usec()
	sim.fluid.set_camera(sim.WORLD*.5,sim.WORLD*.5)
	if sim.native_fluid:
		sim.fluid.velocity=sim.kernels.fluid_step(sim.fluid.velocity,sim.fluid.activity,sim.fluid.tide,dt,sim.fluid.driven)
		if sim.revision%6==0: sim.acidity.values=sim.kernels.acid_step(sim.acidity.values,sim.fluid.velocity,sim.fluid.activity,dt*6)
	else:
		sim.fluid.step(dt)
		if sim.revision%6==0: sim.acidity.step(dt*6,sim.fluid)
	var cells:=_living(sim)
	sim.active_cells=cells.size()
	for cell in cells:
		cell.previous_position=cell.position;cell.previous_angle=cell.angle;cell.activity=1
		cell.age+=dt;cell.hurt_flash=maxf(0,cell.hurt_flash-dt*2);cell.reaction_flash=maxf(0,cell.reaction_flash-dt*2)
	sim._suction(dt)
	sim.profile_usec["fluid"]=Time.get_ticks_usec()-mark
	mark=Time.get_ticks_usec()
	gpu.environment(sim.fluid.velocity,sim.acidity.values);gpu.advance(dt,sim.revision)
	for cell in cells: cell.animate_resources(dt);sim._clear_receptors(cell,dt)
	var queries:=_queries(sim,cells,dt)
	var receipt:=_receipt(cells,queries,{"projection":false})
	sim.profile_usec["particles"]=Time.get_ticks_usec()-mark
	if receipt.has("error"): fallback(receipt.error)
	mark=Time.get_ticks_usec()
	needed.clear()
	if not receipt.has("error"):
		for i in queries.size():
			if queries[i].mode in ["waste","toxin"]: needed[Vector2i(queries[i].id,queries[i].organ_id)]=receipt.senses[i].valid
	var pore:=0
	for i in cells.size():
		var cell=cells[i]
		var sense_start:=Time.get_ticks_usec()
		sim._sense(cell,dt,Perception.for_cell(queries,receipt.senses,cell) if not receipt.has("error") else {})
		sim.profile_usec["sensing"]+=Time.get_ticks_usec()-sense_start
		if receipt.has("error"): sim._feed(cell)
		else:
			var intake=receipt.intake[i]
			cell.substrate+=intake[0];cell.oxygen+=intake[1];cell.carbon+=intake[2]
			cell.eaten+=intake[0];cell.foreign_intake+=intake[3]
			if intake[0]>0: sim._record_sound("feeding",cell.position,cell.id,intake[0])
			for organ in cell.organs:
				if organ.kind=="feeding": cell.consumed(organ,receipt.pores[pore]);pore+=1
			pore+=1
			if cell.count("photosynthesis")>0: pore+=1
		sim._biology_after_feed(cell,dt)
	if receipt.get("_capacity",false): fallback("Particle capacity reached; preserved paid emissions")
	sim.profile_usec["biology"]=Time.get_ticks_usec()-mark
	mark=Time.get_ticks_usec()
	sim._step_cell_motion(dt)
	sim.profile_usec["motion"]=Time.get_ticks_usec()-mark
	mark=Time.get_ticks_usec()
	if sim.resident!=null:
		receipt=_receipt(cells,[],{"feeding":false,"exposure":true,"projection":false})
		if receipt.has("error"): fallback(receipt.error)
		else:
			while true:
				_apply_exposure(cells,receipt.exposure)
				if receipt.get("_capacity",false):
					fallback("Particle capacity reached; preserved paid emissions");break
				if receipt.exposure.deferred==0:
					gpu.project_cached(cells.size());break
				receipt=_receipt(cells,[],{"feeding":false,"exposure":true,"projection":false})
				if receipt.has("error"): fallback(receipt.error);break

	if sim.resident==null: sim._toxin_contacts();sim._receptor_contacts();sim._exclude_particles()
	for cell in sim.cells.duplicate():
		if cell.health<=0 and not cell.dead: sim._die(cell)
	sim.spawn_clock+=dt
	if sim.spawn_clock>=.5:
		sim.spawn_clock-=.5;sim._replace_population()
	if sim.evolution.enabled and (sim.player.dead or sim.player.health<=0):
		if not sim.player.dead: sim._die(sim.player)
		sim.lineage.recover(sim,dt)
	sim.evolution.advance(dt,sim);sim.won=sim.evolution.status=="won"
	sim.profile_usec["ecology"]=Time.get_ticks_usec()-mark
	elapsed_usec=Time.get_ticks_usec()-start

func _apply_exposure(cells: Array,exposure: Dictionary) -> void:
	var sim=world.get_ref()
	for i in cells.size():
		var cell=cells[i]
		for event in exposure.hits[i]:
			cell.waste+=cell.damage(event.amount*75,event.angle)+event.amount
			cell.death_hint="Membrane failed after toxin exposure"
			if event.owner==sim.player.id: sim.evolution.record("toxin",event.amount*75)
	for event in exposure.decoys:
		var cell=cells[event.body]
		var organ: Dictionary=cell.organ_by_id(event.organ_id)
		organ.blocked=minf(1,organ.blocked+.65*event.count)
		cell.waste+=event.amount
		if event.count>0: cell.render_revision+=1

static func decode(values: PackedFloat32Array,owner: int,sim) -> Dictionary:
	return {"p":Vector2(values[0],values[1]),"previous":Vector2(values[0],values[1]),"angle":values[2],"previous_angle":values[2],
		"spin":values[3],"v":Vector2(values[4],values[5]),"age":values[6],"kind":int(values[7]),"amount":values[9],"capacity":values[10],
		"direction":Vector2.from_angle(values[2]),"owner":owner,"alive":values[7]>=0,"chemical_at":sim.time,"transport_at":sim.transport_clock}

static func metadata(packet: Dictionary,data: PackedByteArray,at: int) -> void:
	packet.owner=data.decode_s32(at+48)
	if packet.kind!=3: return
	packet["expires_at"]=data.decode_float(at+36)
	packet["report"]={"at":Vector2(data.decode_float(at),data.decode_float(at+4)),"mass":data.decode_float(at+8),
		"radius":data.decode_float(at+12),"id":data.decode_s32(at+16),"lineage":data.decode_s32(at+20),
		"hostile":data.decode_u32(at+24)!=0,"defended":data.decode_u32(at+28)!=0,"emitted_at":data.decode_float(at+32)}

func snapshots() -> Array:
	var result: Array=[]
	var sim=world.get_ref()
	var data: Dictionary=gpu.export_sync()
	for i in capacity:
		if data.state[i*12+7]<0: continue
		var packet:=decode(data.state.slice(i*12,i*12+12),-1,sim)
		metadata(packet,data.metadata,i*64)
		result.append(packet)
	return result+pending.duplicate(true)+trace_emissions.values().duplicate(true)

func fallback(message: String) -> void:
	var sim=world.get_ref()
	var completion: Dictionary=gpu.exchange_sync([],[],[],[],{"feeding":false,"projection":false})
	if completion.has("chemistry"): _account_chemistry(completion.chemistry)
	var packets:=snapshots()
	sim.resident=null;sim.particle_engine="current";sim.fluid.global_coupling=false
	sim.particles=packets;sim.pheromones=packets.filter(func(p): return p.alive and p.kind==3)
	sim.grid.rebuild(packets);pending.clear();trace_emissions.clear()
	ready=false;fallback_reason=message
	gpu.close();sim.enable_particle_pool()
	returned_to_cpu.emit(message)
	push_warning("Resident particles returned to CPU without resetting the habitat: "+message)

func inspect(at: Vector2,reach: float,handle: Vector2i=Vector2i(-1,-1),zoom: float=0) -> Dictionary:
	var sim=world.get_ref()
	var result: Dictionary
	var packet: Dictionary
	if handle.x>=0:
		result=gpu.exchange_sync([],[],[handle],[],{"feeding":false,"projection":false})
		if result.has("error") or not result.inspections[0].valid: return {}
		packet=decode(result.inspections[0].state,result.inspections[0].owner,sim)
	else:
		var query={"at":at,"reach":reach,"id":0,"lineage":0,"mass":0,"mode":"inspect","target_id":-1,"incumbent":false,"inner":zoom}
		result=gpu.exchange_sync([],[],[],[query],{"feeding":false,"projection":false})
		if result.has("error") or not result.senses[0].valid: return {}
		var found=result.senses[0]
		packet=decode(found.state,found.owner,sim);handle=found.handle
	packet["_resident_handle"]=handle;packet["_index"]=handle.x
	if packet.kind==3: metadata(packet,gpu.report_sync(handle.x),0)
	return packet

func inspect_slot(index: int) -> Dictionary:
	# Detached diagnostic at an absolute resident slot. Tracking keeps the
	# returned generation; it never resolves a reused slot as the old particle.
	var handle: Vector2i=gpu.slot_handle_sync(index)
	return inspect(Vector2.ZERO,1,handle) if handle.x>=0 else {}

func close() -> void:
	closing=true;ready=false;gpu.close()
