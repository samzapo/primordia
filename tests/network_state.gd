extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Store=preload("res://scripts/network/world_store.gd")
var assertions:=0
var failures:=0
func check(value: bool,message: String) -> void:
	assertions+=1
	if not value: failures+=1;push_error("FAIL: "+message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var sim=Sim.new(13,0,false)
	sim.habitat_geometry=Sim.Habitat.new(13,[sim.player])
	sim.cells=[sim.player];sim.evolution.sandbox=true;sim.server_mode=true
	sim.spawn_particle(0,Vector2(100,100),Vector2.ZERO,.5)
	sim.spawn_particle(1,Vector2(130,100),Vector2.ZERO,.4)
	sim.spawn_particle(5,Vector2(1800,1200),Vector2.ZERO,.2)
	sim.grid.rebuild(sim.particles)
	sim.camera_views=[Vector4(100,100,80,80),Vector4(130,100,80,80)]
	check(sim.visible_particle_ids().size()==2,"overlapping camera union deduplicates particles")
	check(sim.activity_at(Vector2(130,100))==1,"observed water is fully detailed")
	check(sim.activity_at(Vector2(1800,1200))==0,"unobserved water stays coarse")
	sim.camera_views=[]
	check(sim.activity_at(sim.player.position)==0,"no observer does not keep a privileged camera")
	if sim.kernels!=null:
		sim.kernels.set_activity_views([],true)
		check(sim.enable_particle_pool(),"native particle owner starts")
	var packets=sim.particle_snapshots()
	var graph=Codec.new().capture({"world":sim,"same_player":sim.player},{sim.get_instance_id():{"particles":packets,"pheromones":[],"particle_pool":false}})
	var restored=Codec.new().restore(bytes_to_var(var_to_bytes(graph)))
	check(restored.world.player==restored.same_player,"checkpoint retains shared object identities")
	check(restored.world.cells[0]==restored.world.player,"player refers to the actual restored world cell")
	check(restored.world.rng.state==sim.rng.state and restored.world.background_rng.state==sim.background_rng.state,"random streams survive restoration")
	check(var_to_bytes(restored.world.player.chemistry.particles)==var_to_bytes(sim.player.chemistry.particles),"cytoplasmic particles retain species, fuel, positions and amounts")
	check(restored.world.player.chemistry.owner.get_ref()==restored.world.player,"chemistry owner rebound without a retained old world")
	check(restored.world.particles.size()==3,"native/CPU state is captured without inventing a second owner")
	var before: float=sim.time
	sim.player.dead=true
	sim.step(1.0/60)
	check(sim.time>before,"world clock continues when selected player dies")
	var store=Store.new()
	store.directory=ProjectSettings.globalize_path("res://build/network-store-"+str(OS.get_process_id()))
	check(store.save({"tick":17,"graph":graph}),"first atomic checkpoint")
	check(store.save({"tick":18,"graph":graph}),"second checkpoint")
	check(store.load_latest().tick==18,"latest complete generation selected")
	check(store.retain_latest(),"pre-conversion checkpoint is independently retained")
	var retained_bytes:=FileAccess.get_file_as_bytes(store.directory.path_join("before-particle-resolution-v1.pworld"))
	check(retained_bytes==FileAccess.get_file_as_bytes(store.directory.path_join("world-0.pworld")),"retained generation is byte-identical to the validated input")
	var damaged:=FileAccess.open(store.directory.path_join("world-0.pworld"),FileAccess.WRITE)
	damaged.store_string("interrupted");damaged.close()
	check(store.load_latest().tick==17,"corrupt newer generation falls back to valid previous checkpoint")
	check(store.retain_latest() and FileAccess.get_file_as_bytes(store.directory.path_join("before-particle-resolution-v1.pworld"))==retained_bytes,"repeated retention cannot overwrite the original generation")
	restored.world.grid.rebuild(restored.world.particles)
	check(restored.world.time==before,"host downtime is not charged during restore")
	for path in ["world-0.pworld","world-1.pworld","before-particle-resolution-v1.pworld"]:
		DirAccess.remove_absolute(store.directory.path_join(path))
	DirAccess.remove_absolute(store.directory)

	var host=preload("res://scripts/network/world_host.gd").new();host.world=sim
	var peer={"view":null,"view_tick":-1,"detail":Sim.VIEW*.5/.8}
	var report={"rect":[100,100,80,80],"detail":[800,500]}
	host._view(peer,report)
	check(peer.view_tick==sim.revision,"new camera waits for a simulation tick")
	peer.view_tick=sim.revision-1
	host._view(peer,report)
	check(peer.view_tick==sim.revision-1,"unchanged camera heartbeat cannot starve GPU publication")
	report.rect[0]=140
	host._view(peer,report)
	check(peer.view_tick==sim.revision,"changed camera requires a fresh detailed tick")
	peer.view_tick=sim.revision-1;report.detail[0]=900
	host._view(peer,report)
	check(peer.view_tick==sim.revision,"expanded detail footprint requires a fresh tick")
	var retained: Vector4=peer.view;var retained_tick: int=peer.view_tick
	report.rect[2]=10000
	host._view(peer,report)
	check(peer.view==retained and peer.view_tick==retained_tick,"invalid camera does not mutate activity or readiness")
	host.world=null;host.free()

	var resolution=preload("res://scripts/network/particle_resolution.gd")
	var coarse=Sim.new(91,0,false)
	coarse.cells=[coarse.player]
	for i in 20: coarse.spawn_particle(Sim.NUTRIENT,Vector2(100+i,100),Vector2(i,0),0.3,7)
	coarse.spawn_particle(Sim.NUTRIENT,Vector2(100,100),Vector2.ZERO,0.3,8)
	coarse.spawn_particle(Sim.NUTRIENT,Vector2(400,100),Vector2.ZERO,0.3,7)
	coarse.spawn_particle(Sim.NUTRIENT,Vector2(100,100),Vector2.ZERO,0.3,7)
	coarse.particles[-1].chemical_at=3
	coarse.spawn_particle(Sim.PHEROMONE,Vector2(100,100),Vector2.ZERO,0.2,7)
	var signal_packet: Dictionary=coarse.particles[-1].duplicate(true)
	var original=coarse.particles.duplicate(true)
	var chemistry=coarse.player.chemistry
	chemistry.particles.clear();chemistry.totals.clear();chemistry.bins.clear()
	for i in 20: chemistry.emit("glucose",0.2,Vector2(1+i*0.25,1),-1,-1,0.8)
	chemistry.emit("glucose",0.2,Vector2(80,1),-1,-1,0.8)
	chemistry.emit("glucose",0.2,Vector2(1,1),3,4,0.8)
	var glucose: float=chemistry.amount("glucose")
	var fuel: float=chemistry.potential()
	var state: int=coarse.rng.state
	var resolution_report: Dictionary=resolution.apply(coarse)
	check(resolution_report.external_after==6,"density migration groups at most ten compatible packets and preserves distinct owners, chunks and clocks")
	var amount:=0.0;var capacity:=0.0;var momentum:=Vector2.ZERO
	for packet in coarse.particles:
		if packet.kind==Sim.NUTRIENT:
			amount+=packet.amount;capacity+=packet.capacity;momentum+=packet.v*packet.amount
	var before_momentum:=Vector2.ZERO
	for packet in original:
		if packet.kind==Sim.NUTRIENT: before_momentum+=packet.v*packet.amount
	check(absf(amount-6.9)<0.000001 and absf(capacity-6.9)<0.000001,"coarser external parcels retain finite material and fuel capacity")
	check(momentum.distance_to(before_momentum)<0.00001,"coarser parcel velocity preserves aggregate linear momentum")
	check(coarse.particles[-1]==signal_packet,"informational pheromone metadata and expiry stay unchanged")
	var retained_amount:=0.0
	for packet in chemistry.particles: retained_amount+=packet.amount
	check(is_equal_approx(retained_amount,glucose) and is_equal_approx(chemistry.potential(),fuel),"local cytoplasm coalescence retains species quantities and exact fuel")
	check(chemistry.particles.any(func(packet):return packet.source==3 and packet.compartment==4 and packet.amount==0.2),"migration preserves pathway source and compartment isolation")
	check(chemistry._local_amount("glucose",Vector2(80,1),2)==0.2,"distant intracellular material remains a distant physical particle")
	check(coarse.rng.state==state,"resolution conversion draws no simulation randomness")
	var seeded=Sim.new(81)
	check(seeded.particle_count()==3760 and seeded.Catalog.data().ecology.visible_target==700,"new worlds use one tenth of the former external packet population")
	check(is_equal_approx(seeded.particles[0].amount,3),"initial parcel coarsening retains the previously funded starting quantity")
	var prior_ecology:=OS.get_environment("PRIMORDIA_ECOLOGY")
	OS.set_environment("PRIMORDIA_ECOLOGY","reference")
	var reference_world=Sim.new(81)
	check(reference_world.particle_count()==3760 and is_equal_approx(reference_world.particles[0].amount,0.3),"explicit reference ecology retains its historical finite fixture inventory")
	if prior_ecology!="": OS.set_environment("PRIMORDIA_ECOLOGY",prior_ecology)
	else: OS.unset_environment("PRIMORDIA_ECOLOGY")
	print("NETWORK CORRECTNESS: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
