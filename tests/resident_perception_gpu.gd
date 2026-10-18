extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Perception=preload("res://scripts/resident_perception.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Cell=preload("res://scripts/cell.gd")
const Simulation=preload("res://scripts/simulation.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func packet(kind: int,at: Vector2,amount: float=0.3) -> PackedFloat32Array:
	return PackedFloat32Array([at.x,at.y,0,0,0,0,0,kind,6,amount,0,0])
func meta(slot: int,id: int,lineage: int,mass: float=20,at: Vector2=Vector2(3000,2000),emitted: float=9,expiry: float=30,hostile: bool=true,defended: bool=true) -> Dictionary:
	return {"slot":slot,"owner":id,"expires_at":expiry,"report":{"id":id,"lineage":lineage,"mass":mass,"at":at,"radius":30,"emitted_at":emitted,"hostile":hostile,"defended":defended}}
func query(mode: String="hunt") -> Dictionary:
	return {"at":Vector2(10,100),"reach":120.0,"id":1,"lineage":1,"mass":100.0,"mode":mode,"target_id":-1,"incumbent":false}
func setup(data: PackedFloat32Array,metadata: Array,mode: String="chemistry"):
	var gpu=GPU.new()
	check(gpu.configure_interactions(mode) and gpu.configure_exchange() and gpu.configure_perception(10),"Configure perception")
	gpu.initialize(data,Fixture.flow(),metadata)
	var status: Array=await gpu.ready;check(status[0],str(status[1]))
	return gpu
func sense(gpu,queries: Array,emissions: Array=[]) -> Dictionary:
	check(gpu.exchange([],emissions,[],false,queries),"Query submission")
	return await gpu.exchange_ready
func run() -> void:
	Fixture.load_native()
	validation()
	await full_receptor_pond()
	await resident_navigation()
	await social_and_danger()
	await reports_and_expiry()
	await emission_identity()
	await exact_identities()
	await contacts_unchanged()
	await cpu_behavior()
	await food_patches()
	await maximum_capacity()
	print("PERCEPTION_VALIDATION ",checks," checks")
	print("RESIDENT PERCEPTION: %d checks, 0 failures" % checks)
	quit()
func validation() -> void:
	var p=Perception.new()
	check(p.prepare_initial(packet(3,Vector2.ZERO),[]).has("error"),"No anonymous immortal pheromones")
	var bad:=meta(0,2,2);bad.report.mass=NAN
	check(p.prepare_initial(packet(3,Vector2.ZERO),[bad]).has("error"),"Reject nonfinite metadata")
	check(p.sources.is_empty(),"Invalid import does not consume identities")
	check(p.prepare_initial(packet(3,Vector2.ZERO),[meta(0,2,2),meta(0,3,3)]).has("error"),"Duplicate slot rejected")
	bad=meta(0,2,2);bad.expires_at=bad.report.emitted_at
	check(p.prepare_initial(packet(3,Vector2.ZERO),[bad]).has("error"),"Zero lifetime rejected")
	check(not p.prepare_initial(packet(3,Vector2.ZERO),[meta(0,2147483647,2147483646)]).has("error"),"32-bit identities preserved without float conversion")
	var invalid:=query();invalid.reach=-1
	check(p.prepare_batch([], [invalid]).has("error"),"Invalid query rejected")
	check(p.sources.size()==1,"Rejected batch leaves source map untouched")
	var cell=Cell.new(1,Vector2.ZERO);cell.add_organ("hunting",0,"hunt",false)
	cell.target_organ_id=cell.organs[0].id;cell.target_mode="hunt";cell.target_id=2;cell.target_lineage=2
	cell.target_memory=0.01
	check(not Perception.requests([cell],0.02,10)[0].incumbent,"Dying target memory gives no GPU incumbent bonus")
	cell.target_memory=1;cell.target_expires_at=10
	check(not Perception.requests([cell],0.02,10)[0].incumbent,"Expired signal gives no incumbent bonus")
	cell.target_expires_at=20;cell.target_lineage=1
	check(not Perception.requests([cell],0.02,10)[0].incumbent,"Family memory gives no incumbent bonus")
	cell.target_lineage=2
	check(Perception.requests([cell],0.02,10)[0].incumbent,"Living valid incumbent retained")
	cell.activity=0.25;cell.sense_clock=0.01
	check(Perception.requests([cell],0.02,10).is_empty(),"Sensing cadence follows local activity timestep")
	var gpu=GPU.new();gpu.configure_interactions("chemistry")
	check(not gpu.configure_perception(),"Exchange required")
	gpu.configure_exchange(8,true)
	check(not gpu.configure_perception(),"No stale capacity pipeline with physiology")
func reports_and_expiry() -> void:
	var data:=PackedFloat32Array()
	for i in 7: data.append_array(packet(3,Vector2(4090+i,100)))
	var metadata: Array=[meta(0,2,2,20),meta(1,2,2,200,Vector2(3001,2000),9.5),
		meta(2,3,1,1),meta(3,1,1,1),meta(4,4,4,20,Vector2(777,888),9,10),
		meta(5,5,5,10,Vector2(1234,567),8,11,false),meta(6,6,6,20,Vector2(800,900),9,30,true)]
	var gpu=await setup(data,metadata)
	# Mutating caller data cannot refresh an already emitted report.
	metadata[1].report.at=Vector2.ZERO
	var r:=await sense(gpu,[query(),query("flee")])
	gpu.perception_spread_queries=false
	var packed:=await sense(gpu,[query(),query("flee")])
	check(r.senses==packed.senses,"Packed and spread pheromone results are identical")
	gpu.perception_spread_queries=true
	check(r.senses[0].valid and r.senses[0].report.id==2,"Hunting accepts the latest detected foreign cell regardless of size and defenses")
	check(r.senses[0].report.at==Vector2(3001,2000),"Target is emission-time location, not packet or current source location")
	check(r.senses[1].report.id==2,"Flight sees newest larger hostile source")
	check(r.readback_bytes==160 and gpu.readbacks==0,"Only compact receptor receipts, no state download")
	gpu.advance(1.0,0)
	r=await sense(gpu,[query()])
	gpu.snapshot();var state: PackedFloat32Array=await gpu.snapshot_ready
	check(state[4*12+7]==-1 and state[5*12+7]==-1,"Expiry is global and includes exact deadline")
	check(not gpu.exchange([],[],[],false,[{"at":Vector2.ZERO}]),"Malformed query rejected before submission")
	gpu.close();await gpu.closed
func emission_identity() -> void:
	var gpu=await setup(packet(3,Vector2(10,100)),[meta(0,2,2,20,Vector2(800,900),9,10)])
	var product:=meta(0,7,7,15,Vector2(2000,1000),10,11)
	product["state"]=packet(3,Vector2(10,100))
	var r:=await sense(gpu,[query()],[product])
	check(not r.senses[0].valid,"New emissions enter perception on next query")
	check(r.emissions[0].accepted and r.emissions[0].handle==Vector2i(0,2),"Expired slot reused with new generation")
	r=await sense(gpu,[query()])
	check(r.senses[0].report.id==7 and r.senses[0].report.at==Vector2(2000,1000),"Reused slot contains only new report")
	var rejected:=meta(0,8,8);rejected["state"]=packet(3,Vector2(11,100))
	r=await sense(gpu,[query()],[rejected])
	check(not r.emissions[0].accepted and r.senses[0].report.id==7,"Refused emission never overwrites metadata")
	gpu.advance(1.0,1)
	var chemical: Dictionary={"state":packet(2,Vector2(10,100)),"owner":7}
	r=await sense(gpu,[query()],[chemical])
	check(r.emissions[0].accepted,"Expired signal slot accepts chemical")
	r=await sense(gpu,[query()])
	check(not r.senses[0].valid,"Chemical reuse cannot revive old pheromone report")
	check(gpu.exchange([],[],[Vector2i(0,3)],true,[query()]),"Async combined inspection")
	gpu.close()
	r=await gpu.exchange_ready
	check(r.inspections[0].valid and r.inspections[0].owner==7,"Owner and generation survive receipt layout")
	await gpu.closed
func contacts_unchanged() -> void:
	var data:=packet(0,Vector2(100,100))
	data.append_array(packet(2,Vector2(101,100)))
	data.append_array(packet(3,Vector2(100,100)))
	var outcomes: Array=[]
	for enabled in [false,true]:
		var gpu=GPU.new();gpu.configure_interactions("chemistry");gpu.configure_exchange()
		if enabled: gpu.configure_perception(10)
		gpu.initialize(data,Fixture.flow(),[meta(2,2,2)] if enabled else [])
		var status: Array=await gpu.ready;check(status[0],str(status[1]))
		gpu.interact_only()
		gpu.snapshot();outcomes.append(await gpu.snapshot_ready)
		gpu.contact_snapshot();var contacts: Dictionary=await gpu.contacts_ready
		check(contacts.counts[2]==0 and contacts.stats[0]==1,"Pheromones excluded from both sides of contact screening")
		gpu.close();await gpu.closed
	check(outcomes[0]==outcomes[1],"Adding signals to query grid does not change collision/reaction outcomes")

func cpu_behavior() -> void:
	var sim=Simulation.new(3801)
	sim.disable_particle_pool()
	sim.particles=[];sim.pheromones=[];sim.time=10
	var cell=Cell.new(1,Vector2(4090,100))
	cell.add_organ("hunting",0,"hunt",false);cell.add_organ("sensing",PI,"flee",false)
	var q: Array=Perception.requests([cell])
	var data:=PackedFloat32Array()
	var metadata: Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=380017
	# Large neighborhoods, duplicate sources, family, expired and outside reach.
	for i in 600:
		var at:=Fixture.wrapped(cell.position+Vector2(rng.randf_range(-180,180),rng.randf_range(-180,180)))
		var item:=meta(i,2+i%23,1 if i%7==0 else 2+i%23,float(10+i%220),Vector2(800+i,400-i*.25),5.0+(i%47)*.1,9.9 if i%13==0 else 30,i%3==0,i%5!=0)
		data.append_array(packet(3,at));metadata.append(item)
		sim.particles.append({"p":at,"kind":3,"amount":0.3,"alive":true,"owner":item.owner,"expires_at":item.expires_at,"report":item.report.duplicate()})
	sim.grid.rebuild(sim.particles)
	var gpu=await setup(data,metadata)
	var receipt:=await sense(gpu,q)
	# Compare the actual behavior routine with and without the completed GPU result.
	var native_cell=Cell.new(1,cell.position)
	native_cell.organs=cell.organs.duplicate(true)
	sim._sense(native_cell,0.15)
	sim._sense(cell,0.15,Perception.for_cell(q,receipt.senses,cell))
	check(cell.target_id==native_cell.target_id and cell.target_mode==native_cell.target_mode,"Existing behavior selects same target/priority")
	check(cell.target_position.distance_to(native_cell.target_position)<0.001,"Signal target preserves emitted position")
	check(cell.target.distance_to(native_cell.target)<0.001 and cell.target_lineage==native_cell.target_lineage,"Existing intracellular signal delivery agrees")
	check(cell.target_id!=-1 and cell.target_lineage!=1,"Test actually delivered a non-family signal")
	if sim.kernels!=null:
		var pooled=Cell.new(1,cell.position)
		pooled.organs=cell.organs.duplicate(true)
		check(sim.enable_particle_pool(),"Enable native ownership for perception oracle")
		sim._sense(pooled,0.15)
		check(pooled.target_id==cell.target_id and pooled.target_mode==cell.target_mode and pooled.target_position.distance_to(cell.target_position)<0.001,"Native authoritative perception agrees with resident receipt")
	cell.receive_particle(0,1,1,cell.position+cell.local_point(0))
	var saved: float=cell.energy
	sim._metabolize(cell,0.1)
	check(cell.processed>0 and cell.energy!=saved,"Real CPU physiology runs after GPU handoff")
	gpu.close();await gpu.closed

func maximum_capacity() -> void:
	var data:=PackedFloat32Array();var metadata: Array=[]
	for i in 1024:
		data.append_array(packet(3,Vector2(10,100)))
		metadata.append(meta(i,i+10,i+10,20,Vector2(i,200),9,30))
	var gpu=await setup(data,metadata,"contacts")
	var queries: Array=[]
	for i in Perception.MAX_QUERIES:
		var q:=query()
		q.target_id=1033;q.incumbent=true
		queries.append(q)
	var r:=await sense(gpu,queries)
	for result in r.senses: check(result.valid and result.report.id==1033,"Full source and receptor capacity, incumbent preserved")
	check(r.readback_bytes==Perception.MAX_QUERIES*80,"Bounded maximum receipt")
	var extra:=meta(0,2000,2000);extra["state"]=packet(3,Vector2.ZERO)
	check(not gpu.exchange([], [extra],[],false,queries),"Source overflow explicitly rejected")
	check(gpu._perception.sources.size()==1024,"Overflow does not partially register sources")
	check(not gpu.exchange([],[],[],false,queries+[query()]),"Receptor overflow explicitly rejected")
	gpu.close();await gpu.closed

func food_patches() -> void:
	var sim=Simulation.new(3807)
	sim.disable_particle_pool();sim.particles=[];sim.pheromones=[];sim.time=10
	var data:=PackedFloat32Array();var metadata: Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=38771
	for i in 4097:
		var at:=Fixture.wrapped(Vector2(4090,100)+Vector2(rng.randfn(0,180),rng.randfn(0,180)))
		var kind:=0 if i%5!=0 else 2
		var owner:=1 if i%11==0 else -1
		var amount:=rng.randf_range(0.01,0.4)
		data.append_array(packet(kind,at,amount));metadata.append({"slot":i,"owner":owner})
		sim.particles.append({"p":at,"kind":kind,"amount":amount,"owner":owner,"alive":true})
	sim.grid.rebuild(sim.particles)
	var queries: Array=[]
	var cells: Array=[]
	for i in 12:
		var cell=Cell.new(1,Vector2(4090,100) if i<6 else Vector2(100,2550))
		var q:=query("graze");q.at=Fixture.wrapped(cell.position+Vector2(47,0))
		q.reach=[50.0,120.0,310.0,500.0,1280.0,4096.0][i%6]
		q["center"]=cell.position;q["inner"]=maxf(70,cell.extent()+22)
		queries.append(q);cells.append(cell)
	var gpu=await setup(data,metadata,"contacts")
	var receipt:=await sense(gpu,queries)
	gpu.perception_spread_queries=false
	var packed:=await sense(gpu,queries)
	check(receipt.senses==packed.senses,"Packed and spread grazing results are identical")
	gpu.perception_spread_queries=true
	for i in queries.size():
		var q: Dictionary=queries[i]
		var bins: Dictionary={}
		for index in sim.grid.query_kind(sim.particles,q.at,q.reach,0):
			var p: Dictionary=sim.particles[index]
			if p.kind!=0 or p.owner==1: continue
			var distance: float=Simulation.Medium.offset(q.at,p.p).length()
			if distance>q.reach: continue
			var delta: Vector2=Simulation.Medium.offset(q.center,p.p)
			var key:=Vector2i((delta/maxf(80,q.reach/4)).floor())
			if not bins.has(key): bins[key]={"mass":0.0,"moment":Vector2.ZERO,"nearest":delta,"distance":distance}
			bins[key].mass+=p.amount;bins[key].moment+=delta*p.amount
			if distance<bins[key].distance: bins[key].nearest=delta;bins[key].distance=distance
		var expected: Dictionary=sim._food_patch(bins,q.reach,cells[i])
		var result: Dictionary=receipt.senses[i]
		check(result.valid==not expected.is_empty(),"Food detection agrees across reach and seams")
		if result.valid:
			check(result.patch.at.distance_to(expected.at)<0.03,"Patch center/nearest target agrees")
			check(absf(result.patch.mass-expected.mass)<0.002 and result.patch.inner==expected.inner,"Patch weight and inner threshold agree")
	var cell=Cell.new(1,Vector2(4090,100));cell.add_organ("feeding",0,"graze",false)
	var clone=Cell.new(1,cell.position);clone.organs=cell.organs.duplicate(true)
	var q: Array=Perception.requests([cell])
	receipt=await sense(gpu,q)
	sim._sense(clone,0.15)
	sim._sense(cell,0.15,Perception.for_cell(q,receipt.senses,cell))
	check(cell.target_mode==clone.target_mode and cell.target_position.distance_to(clone.target_position)<0.03,"GPU patch drives existing grazer behavior")
	check(cell.sensed,"Food behavior fixture actually senses food")
	gpu.close();await gpu.closed

func exact_identities() -> void:
	var gpu=await setup(packet(3,Vector2(10,100)),[meta(0,2147483647,2147483646)])
	var r:=await sense(gpu,[query()])
	check(r.senses[0].report.id==2147483647 and r.senses[0].report.lineage==2147483646,"GPU report preserves all identity bits")
	var own:=query();own.id=2147483647
	r=await sense(gpu,[own])
	check(not r.senses[0].valid,"Exact owner prevents sensing self")
	var family:=query();family.lineage=2147483646
	r=await sense(gpu,[family])
	check(not r.senses[0].valid,"Exact lineage prevents sensing relatives")
	gpu.close();await gpu.closed

func social_and_danger() -> void:
	var data:=packet(3,Vector2(25,100))
	data.append_array(packet(3,Vector2(30,100)))
	data.append_array(packet(4,Vector2(40,100)))
	var metadata: Array=[meta(0,2,1,20,Vector2(300,100)),meta(1,3,3,10000,Vector2(400,100),9,30,false,true),{"slot":2,"owner":1,"lineage":1}]
	var gpu=await setup(data,metadata)
	var r:=await sense(gpu,[query("family"),query("hunt"),query("flee"),query("danger")])
	check(r.senses[0].valid and r.senses[0].report.id==2,"Family receptors receive actual same-lineage tracers")
	check(r.senses[1].valid and r.senses[1].report.id==3,"Hunter has no mass or defense exclusion for a non-family signal")
	check(not r.senses[2].valid,"Flight ignores a huge unarmed non-family signal and an armed relative")
	check(r.senses[3].valid and r.senses[3].danger.at==Vector2(40,100),"Flight receives actual local toxin coordinates, including family/source toxin, without a full pool download")
	var cell=Cell.new(1,Vector2(10,100));cell.add_organ("family_toward",0,"graze",false)
	var requests: Array=Perception.requests([cell],.2,10)
	check(requests.size()==1 and requests[0].mode=="family","A dedicated family receptor uses the actual bounded family query instead of a foreign-target query")
	var received: Dictionary=Perception.for_cell(requests,[r.senses[0]],cell)
	check(received[cell.organs[0].id].families.has(2),"The GPU family receipt reaches the organ's ordinary behavior input")
	gpu.close();await gpu.closed

func resident_navigation() -> void:
	for kind in ["sensing","family_toward","family_away"]:
		var sim=preload("res://scripts/simulation.gd").new(690,0,false)
		sim.cells=[sim.player];sim.automatic_reproduction=false
		sim.habitat_geometry=sim.Habitat.new(690,sim.cells);sim.habitat_geometry.enabled=false
		sim.fluid.driven=false;sim.fluid.velocity.fill(Vector2.ZERO)
		var cell=sim.player;cell.energy=100;cell.biomass=40
		cell.add_organ(kind,0,"graze",false);cell.add_organ("propulsion",PI,"graze",false)
		var at: Vector2=cell.organ_position(cell.organs[0])
		if kind=="sensing":sim.spawn_particle(sim.TOXIN,at+Vector2(60,0),Vector2.ZERO,.1,cell.id)
		else:
			var source=Cell.new(999,cell.position+Vector2(300,0));source.lineage=cell.lineage_id()
			var trace: Dictionary=sim._emit_pheromone(source);trace.p=at+Vector2(20,0);trace.previous=trace.p;trace.expires_at=10
		var bridge=preload("res://scripts/resident_ecology.gd").new();bridge.start(sim,8192)
		var ready: Array=await bridge.initialized;check(ready[0],str(ready[1]))
		check(bridge.streaming!=null,"Navigation fixture uses actual resident/cold ownership")
		var seen:=false
		for i in 60:
			sim.step(1.0/60)
			if cell.target_mode==("toxin" if kind=="sensing" else "kin_toward" if kind=="family_toward" else "kin_away") and cell.drive_active:
				var expected:=Vector2.RIGHT if kind=="family_toward" else Vector2.LEFT
				if cell.target.dot(expected)>.8:seen=true
		check(seen,"Actual resident/cold "+kind+" steers from compact local sensory receipts")
		check(sim.resident==bridge and sim.particles.is_empty() and bridge.gpu.readbacks==0,"Navigation keeps real GPU authority without full exports or live source bodies")
		bridge.close();await bridge.gpu.closed

func full_receptor_pond() -> void:
	var cells: Array=[]
	for i in 64:
		var cell=Cell.new(i+1,Vector2(400+(i%8)*350,400+(i/8)*250))
		for kind in ["feeding","sensing","hunting","family_toward","family_away","counterattack","neutralizing"]:check(cell.add_organ(kind,cell.organs.size()*.8,"graze",false),"Capacity fixture fits its ordinary receptor/support anatomy")
		cells.append(cell)
	var clock=preload("res://scripts/simulation.gd").new(691,0,false);clock.time=10
	var queries: Array=preload("res://scripts/resident_ecology.gd").new()._queries(clock,cells,.2)
	check(queries.size()==576,"All64 cells can sense through every free receptor and both secretion-demand channels")
	var gpu=GPU.new();gpu.configure_interactions("chemistry");gpu.configure_exchange();gpu.configure_perception(10);gpu.configure_exposure()
	gpu.initialize(packet(0,Vector2(50,50)),Fixture.flow())
	var ready: Array=await gpu.ready;check(ready[0],str(ready[1]))
	var receipt: Dictionary=gpu.exchange_sync(cells,[],[],queries,{"feeding":false,"projection":false,"exposure":true})
	check(not receipt.has("error") and receipt.senses.size()==576,"A whole pond of free receptors stays on hardware with complete compact query receipts")
	check(receipt.exposure.decoys.size()==320 and gpu.readbacks==0,"All ordinary and family receptor contact sites fit without a full pool export")
	gpu.close();await gpu.closed
