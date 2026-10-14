extends RefCounted
## Desktop resident-particle gameplay bridge. Cells retain all resource authority.
const GPU=preload("res://scripts/resident_particles.gd")
const Perception=preload("res://scripts/resident_perception.gd")
const Streaming=preload("res://scripts/particle_streaming.gd")
var streaming_enabled:=true # Whole-habitat reference is a diagnostic only.
var streaming
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
# Display zoom never changes ecology resolution. The view sets this to its
# widest playable footprint (including aspect ratio); activity adds a halo.
var display_scope:=Vector4(0,0,-1,-1)
var detail_half:=Vector2(800,500)
var full_detail:=false # Benchmark ablation.
var coarse_period:=0.1
var coarse_cells:=0
var scheduled: Dictionary={}

signal returned_to_cpu(message: String)
signal initialized(ok: bool, message: String)

func start(sim, slots: int=65536) -> void:
	world=weakref(sim);capacity=slots;detail_half=sim.VIEW*.5/.8
	sim.disable_particle_pool()
	var packets: Array=sim.particles
	if streaming_enabled:
		streaming=Streaming.new();streaming.initialize(self,sim)
		packets=[]
		for packet in sim.particles:
			if streaming.contains(packet.p): packets.append(packet)
			else: streaming.cold.put(packet,sim.time)
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
	if streaming_enabled:
		gpu.configure_transfer()
	gpu.ready.connect(func(ok: bool,message: String):
		reason=message
		if closing: initialized.emit(false,"Initialization cancelled");return
		if ok:
			sim.particles=[];sim.pheromones=[];sim.grid.rebuild([])
			sim.resident=self;sim.particle_engine="resident";sim.fluid.global_coupling=true
			sim.fluid.set_camera(sim.WORLD*.5,sim.WORLD*.5)
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
		_queue(packet);return
	if trace_emissions.has(key):
		var held: Dictionary=trace_emissions[key]
		held.amount+=packet.amount;held.capacity+=packet.capacity
		held.p=packet.p;held.previous=packet.previous
	else: trace_emissions[key]=packet
	if trace_emissions[key].amount>=1e-20:
		_queue(trace_emissions[key]);trace_emissions.erase(key)

func _queue(packet: Dictionary) -> void:
	if streaming!=null and not streaming.contains(packet.p): streaming.cold.put(packet,world.get_ref().time)
	else: pending.append(packet)

func stored_count() -> int:
	return streaming.cold.count if streaming!=null else 0

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
	# A backdated coarse pheromone can already have expired. It carries no
	# material; count it once and never submit a dead emission to the GPU.
	for i in range(pending.size()-1,-1,-1):
		if pending[i].kind==sim.PHEROMONE and (not pending[i].alive or pending[i].expires_at<=sim.time):
			pending.remove_at(i);sim.chemistry_events.decay+=1
	# Paid output remains escrowed until the device accepts it. Do not discard a
	# death burst just because one emission batch has fewer slots.
	while pending.size()>256:
		var extra:=_receipt_batch([],[],{"feeding":false,"projection":false,"chemistry":options.get("chemistry",true)},256)
		if extra.has("error"): return extra
		if extra.get("_capacity",false): return {"error":"Particle capacity reached; preserved paid emissions"}
	return _receipt_batch(cells,queries,options,pending.size())

func _receipt_batch(cells: Array,queries: Array,options: Dictionary,n: int) -> Dictionary:
	var sim=world.get_ref()
	var products: Array=[]
	for i in n: products.append(encode(pending[i],sim))
	options["count_scope"]=display_scope
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

func _schedule(sim, dt: float) -> Dictionary:
	var selected: Array=[]
	var times: Dictionary={}
	var coarse: Dictionary={}
	var delayed: Dictionary={}
	sim.active_cells=0;coarse_cells=0;sim.offscreen_ecology.visits=0
	for cell in _living(sim):
		if not scheduled.has(cell.id):
			scheduled[cell.id]=true
			cell.coarse_due=coarse_period*(0.25+fposmod(cell.id*0.61803398875,0.75))
		cell.previous_position=cell.position;cell.previous_angle=cell.angle
		cell.activity=1.0 if sim.activity_for_cell(cell)>0 else 0.0
		if cell.activity>0:
			sim.active_cells+=1
			selected.append(cell);times[cell.id]=dt+cell.coarse_elapsed
			# Drain the short unresolved interval once on promotion. Use exact
			# feeding/exposure here, never widened hidden uptake in visible water.
			if cell.coarse_elapsed>0: delayed[cell.id]=true
			cell.coarse_due=coarse_period*(0.25+fposmod(cell.id*0.61803398875,0.75))
		else:
			coarse_cells+=1
			cell.coarse_elapsed+=dt;cell.coarse_due-=dt
			if cell.coarse_due>0: continue
			selected.append(cell);times[cell.id]=cell.coarse_elapsed;delayed[cell.id]=true
			coarse[cell.id]=sim.offscreen_ecology.feeding_request(sim,cell,cell.coarse_elapsed,sim.offscreen_ecology.period)
			cell.coarse_due+=coarse_period
	return {"cells":selected,"times":times,"coarse":coarse,"delayed":delayed}

func _credit(cell, receipt: Dictionary, index: int, pore: int) -> int:
	var sim=world.get_ref()
	var intake=receipt.intake[index]
	cell.eaten+=intake[0];cell.foreign_intake+=intake[3]
	if intake[0]>0: sim._record_sound("feeding",cell.position,cell.id,intake[0])
	for organ in cell.organs:
		if organ.kind!="feeding": continue
		var quantity: float=receipt.pores[pore]
		var at: Vector2=cell.organ_position(organ)
		if quantity>0 and receipt.has("pore_contacts"): at=cell.position+receipt.pore_contacts[pore]/quantity
		cell.receive_particle(0,quantity,receipt.pore_fuel[pore] if receipt.has("pore_fuel") else quantity,at)
		cell.consumed(organ,quantity);pore+=1
	for kind in [1,5]:
		if kind==5 and cell.count("photosynthesis")==0: continue
		var quantity: float=receipt.pores[pore]
		var at: Vector2=cell.position+Vector2.RIGHT*cell.radius
		if quantity>0 and receipt.has("pore_contacts") and receipt.pore_contacts[pore].length()>0.001: at=cell.position+receipt.pore_contacts[pore]/quantity
		cell.receive_particle(kind,quantity,quantity,at)
		pore+=1
	return pore

func step(dt: float) -> void:
	var sim=world.get_ref()
	if not ready or (not sim.server_mode and (sim.evolution.terminal() or sim.build_original!=null or (sim.player.dead and not sim.evolution.enabled))): return
	var start:=Time.get_ticks_usec()
	gpu.exchange_prepare_usec=0;gpu.exchange_wait_usec=0
	if streaming!=null:
		if not streaming.service(sim): fallback("Particle ownership transfer failed");return
		# Admit already caught-up packets before this tick, so they receive its
		# motion/chemistry exactly once and are available to every receptor.
		if not pending.is_empty():
			var admission:=_receipt([],[],{"feeding":false,"projection":false,"chemistry":false})
			if admission.has("error") or admission.get("_capacity",false): fallback("Nearby particle capacity reached");return
	sim.time+=dt;sim.transport_clock+=dt;sim.revision+=1
	sim.profile_counts.clear();sim.profile_usec.clear()
	sim.profile_usec["streaming"]=Time.get_ticks_usec()-start
	var internal_started:=Time.get_ticks_usec()
	sim._step_internal_chemistry(dt)
	sim.profile_usec["internal_chemistry"]=Time.get_ticks_usec()-internal_started
	for name in ["sensing","feeding","organ_geometry","traction","membrane","contacts","coarse_chemistry","coarse_feeding","coarse_motion","offscreen_biology"]:
		sim.profile_usec[name]=0
	var schedule:=_schedule(sim,dt)
	var cells: Array=schedule.cells
	var center: Vector2=sim.player.position if sim.camera_follows_player else sim.camera_position
	var scope:=Vector4(center.x,center.y,sim.view_half.x,sim.view_half.y)
	var mark:=Time.get_ticks_usec()
	# Cheap habitat field and GPU transport remain continuous. Only cell
	# detail is tiered; no full particle download or frozen offscreen clouds.
	if sim.external_offscreen:sim.fluid.set_views([])
	elif sim.server_mode: sim.fluid.set_views(sim.camera_views)
	if sim.native_fluid:
		sim.fluid.velocity=sim.kernels.fluid_step(sim.fluid.velocity,sim.fluid.activity,sim.fluid.tide,dt,sim.fluid.driven)
		if sim.revision%6==0: sim.acidity.values=sim.kernels.acid_step(sim.acidity.values,sim.fluid.velocity,sim.fluid.activity,dt*6)
	else:
		sim.fluid.step(dt)
		if sim.revision%6==0: sim.acidity.step(dt*6,sim.fluid)
	if sim.server_mode or sim.external_offscreen: sim._step_background_fluid(dt)
	# Coarse bodies pay their own elapsed suction inside advance_body.
	for cell in cells:
		if not schedule.delayed.has(cell.id): sim._suction_cell(cell,dt)
	sim.profile_usec["fluid"]=Time.get_ticks_usec()-mark
	mark=Time.get_ticks_usec()
	var queries: Array=[]
	for cell in cells:
		var h: float=schedule.times[cell.id]
		cell.activity=1
		cell.animate_resources(h);sim._clear_receptors(cell,h)
		queries.append_array(_queries(sim,[cell],h))
	var local_senses: Array=[]
	if streaming!=null:
		var cold_started:=Time.get_ticks_usec()
		streaming.begin(sim,cells,queries,true)
		sim.profile_usec["cold_prepare"]=Time.get_ticks_usec()-cold_started
		cold_started=Time.get_ticks_usec()
		for query in queries: local_senses.append(streaming.sense(sim,query))
		sim.profile_usec["cold_sense"]=Time.get_ticks_usec()-cold_started
		# The private cold workset remains borrowed until intake is credited.
		sim.resident=self
	gpu.environment(sim.fluid.velocity,sim.acidity.values);gpu.advance(dt,sim.revision)
	var receipt:=_receipt(cells,queries,{"projection":false,"coarse":schedule.coarse,"scope":scope,"summaries":streaming!=null})
	sim.profile_usec["particles"]=Time.get_ticks_usec()-mark
	if receipt.has("error"):
		if streaming!=null: streaming.finish(sim)
		fallback(receipt.error);return
	var combined: Array=[]
	if streaming!=null:
		for i in queries.size():
			if receipt.summaries[i].has("error"):
				# Feeding has already committed on-device; credit before recovery.
				var cursor:=0
				for j in cells.size(): cursor=_credit(cells[j],receipt,j,cursor)
				streaming.finish(sim);fallback(receipt.summaries[i].error);return
			combined.append(Perception.merge(local_senses[i],receipt.summaries[i]))
	mark=Time.get_ticks_usec()
	needed.clear()
	for i in queries.size():
		if queries[i].mode in ["waste","toxin"]: needed[Vector2i(queries[i].id,queries[i].organ_id)]=receipt.senses[i].valid or (streaming!=null and local_senses[i].needed)
	var pore:=0
	var foreground_rng: RandomNumberGenerator=sim.rng
	# Credit every paid receipt before an offscreen hunt can kill a batch peer.
	for i in cells.size(): pore=_credit(cells[i],receipt,i,pore)
	if streaming!=null:
		sim.resident=null;streaming.feed(sim,cells,schedule);streaming.finish(sim)
	for cell in cells:
		var h: float=schedule.times[cell.id]
		var delayed: bool=schedule.delayed.has(cell.id)
		var body_start:=Time.get_ticks_usec()
		sim.rng=sim.ecology_rng if delayed else foreground_rng
		sim.coarse_mode=delayed
		sim.coarse_event_at=sim.time
		cell.age+=h;cell.coarse_handling=maxf(0,cell.coarse_handling-h)
		cell.hurt_flash=maxf(0,cell.hurt_flash-h*2);cell.reaction_flash=maxf(0,cell.reaction_flash-h*2)
		var sense_start:=Time.get_ticks_usec()
		var received: Dictionary=Perception.for_cell(queries,receipt.senses,cell)
		if streaming!=null:
			for i in queries.size():
				if queries[i].id!=cell.id or queries[i].mode not in ["graze","hunt","flee"]: continue
				combined[i]["patch"]=sim._food_patch(combined[i].food,queries[i].reach,cell)
				received[queries[i].organ_id]=combined[i]
		sim._sense(cell,h,received)
		sim.profile_usec["sensing"]+=Time.get_ticks_usec()-sense_start
		if delayed:
			sim.offscreen_ecology.advance_body(sim,cell,h)
			cell.coarse_elapsed=0;cell.activity=0
			cell.previous_position=cell.position;cell.previous_angle=cell.angle;cell.render_revision+=1
			sim.offscreen_ecology.visits+=1
			sim.profile_usec["offscreen_biology"]+=Time.get_ticks_usec()-body_start
		else: sim._biology_after_feed(cell,h)
	sim.rng=foreground_rng;sim.coarse_mode=false
	sim.profile_usec["biology"]=Time.get_ticks_usec()-mark
	mark=Time.get_ticks_usec()
	sim._step_cell_motion(dt)
	sim.profile_usec["motion"]=Time.get_ticks_usec()-mark
	mark=Time.get_ticks_usec()
	# Same two handoffs per tick as detailed-only gameplay: due coarse cells
	# share the intake and exposure batches instead of adding per-cell fences.
	for cell in cells: cell.activity=1
	var options: Dictionary={"feeding":false,"exposure":true,"projection":false,"coarse":schedule.coarse,"scope":scope}
	receipt=_receipt(cells,[],options)
	if receipt.has("error"): fallback(receipt.error)
	else:
		while true:
			_apply_exposure(cells,receipt.exposure)
			if receipt.get("_capacity",false):
				fallback("Particle capacity reached; preserved paid emissions");break
			if receipt.exposure.deferred==0:
				gpu.project_cached(cells.size());break
			# Identical hazard seed on overflow retries: one exposure lottery,
			# not additional chances for every receipt-capacity drain.
			receipt=_receipt(cells,[],options)
			if receipt.has("error"): fallback(receipt.error);break
	if streaming!=null and sim.resident!=null:
		streaming.begin(sim,cells)
		streaming.expose(sim,cells,schedule)
		streaming.finish(sim)
	for cell in cells: cell.activity=0.0 if schedule.coarse.has(cell.id) else 1.0
	sim.rng=sim.ecology_rng;sim.coarse_mode=true;sim.coarse_event_at=sim.time
	for cell in cells:
		if cell.health<=0 and not cell.dead: sim._die(cell)
	for cell in cells:
		if schedule.coarse.has(cell.id): sim.offscreen_ecology._hunt(sim,cell,schedule.times[cell.id])
	sim.rng=foreground_rng;sim.coarse_mode=false
	sim.spawn_clock+=dt
	if sim.spawn_clock>=.5:
		sim.spawn_clock-=.5;sim._replace_population()
	sim._step_reproduction()
	if not sim.server_mode and sim.evolution.enabled and (sim.player.dead or sim.player.health<=0):
		if not sim.player.dead: sim._die(sim.player)
		sim.lineage.recover(sim,dt)
	sim.evolution.advance(dt,sim);sim.won=sim.evolution.status=="won"
	sim.profile_usec["ecology"]=Time.get_ticks_usec()-mark
	sim.profile_counts["cold_particles"]=stored_count()
	if streaming!=null:
		sim.profile_counts["particle_promotions"]=streaming.entered
		sim.profile_counts["cold_transport_updates"]=streaming.transported
		sim.profile_counts["stream_queue"]=streaming.queue_depth
	sim.profile_counts["resident_internal_cells"]=sim.cells.filter(func(cell):return cell.chemistry.accelerator!=null).size()
	sim.profile_counts["internal_packets"]=sim.cells.reduce(func(total,cell):return total+cell.chemistry.particle_count(),0)
	sim.profile_counts["coarse_cells"]=coarse_cells
	sim.profile_counts["coarse_updates"]=sim.offscreen_ecology.visits
	sim.profile_usec["gpu_receipt_prepare"]=gpu.exchange_prepare_usec
	sim.profile_usec["gpu_receipt_wait"]=gpu.exchange_wait_usec
	elapsed_usec=Time.get_ticks_usec()-start

func _apply_exposure(cells: Array,exposure: Dictionary) -> void:
	var sim=world.get_ref()
	for i in cells.size():
		var cell=cells[i]
		for event in exposure.hits[i]:
			if event.get("kind",4)!=4:
				if not cell.accept_surface(event.kind,event.amount,event.angle,event.owner): cell.waste+=event.amount
				continue
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
	return result+pending.duplicate(true)+trace_emissions.values().duplicate(true)+(streaming.snapshots(sim) if streaming!=null else [])

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
		result=gpu.exchange_sync([],[],[handle],[],{"feeding":false,"projection":false,"chemistry":false})
		if result.has("error") or not result.inspections[0].valid: return {}
		packet=decode(result.inspections[0].state,result.inspections[0].owner,sim)
	else:
		var query={"at":at,"reach":reach,"id":0,"lineage":0,"mass":0,"mode":"inspect","target_id":-1,"incumbent":false,"inner":zoom}
		result=gpu.exchange_sync([],[],[],[query],{"feeding":false,"projection":false,"chemistry":false})
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
