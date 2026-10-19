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
	var uncached=Codec.new();uncached.cache_property_schema=false
	var schema_fixture: Array=[]
	for kind in Codec.TYPES:
		schema_fixture.append(Codec.TYPES[kind].new(0,0,false) if kind=="simulation" else Codec.TYPES[kind].new())
	for compact in [false,true]:
		for version in [1,2]:
			check(var_to_bytes(Codec.new().capture(schema_fixture,{},compact,version))==var_to_bytes(uncached.capture(schema_fixture,{},compact,version)),"Schema reuse preserves every allowlisted field and exact graph bytes for saved and compact client formats")
	var override_fields: Dictionary={sim.get_instance_id():{"particles":packets,"pheromones":[],"particle_pool":false}}
	var old_energy: float=sim.player.energy;sim.player.energy+=1
	var changed=Codec.new().capture({"world":sim,"same_player":sim.player},override_fields)
	check(var_to_bytes(changed)==var_to_bytes(uncached.capture({"world":sim,"same_player":sim.player},override_fields)) and var_to_bytes(changed)!=var_to_bytes(graph),"Reusing field names captures current biology and overrides without retaining an older cell state")
	sim.player.energy=old_energy
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
	check(store.retain_latest(2),"version-two backup uses the durable publisher before conversion")
	var retained_v2:=FileAccess.get_file_as_bytes(store.directory.path_join("before-particle-resolution-v2.pworld"))
	check(retained_v2==FileAccess.get_file_as_bytes(store.directory.path_join("world-1.pworld")) and retained_v2!=retained_bytes,"version-two backup is independent of the older resolution backup")
	check(store.save({"tick":19,"graph":graph}) and store.retain_latest(2) and FileAccess.get_file_as_bytes(store.directory.path_join("before-particle-resolution-v2.pworld"))==retained_v2,"later checkpoints cannot overwrite the pre-v2 generation")
	check(store.retain_latest(3),"v3 retained backup uses the exact durable destination")
	check(FileAccess.get_file_as_bytes(store.directory.path_join("before-particle-resolution-v1.pworld"))==retained_bytes and FileAccess.get_file_as_bytes(store.directory.path_join("before-particle-resolution-v2.pworld"))==retained_v2,"v3 backup preserves both preceding resolution generations")
	restored.world.grid.rebuild(restored.world.particles)
	check(restored.world.time==before,"host downtime is not charged during restore")
	for path in ["world-0.pworld","world-1.pworld","before-particle-resolution-v1.pworld","before-particle-resolution-v2.pworld","before-particle-resolution-v3.pworld"]:
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
	for i in 20: chemistry.emit("food",0.2,Vector2(1+i*0.25,1),-1,-1,0.8)
	chemistry.emit("food",0.2,Vector2(80,1),-1,-1,0.8)
	chemistry.emit("food",0.2,Vector2(1,1),3,4,0.8)
	var glucose: float=chemistry.amount("food")
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
	check(chemistry.particle_count()<=24,"The current model retains its bounded food/waste carriers")
	check(chemistry.particles.all(func(packet):return packet.species=="food"),"Density conversion cannot restore retired intracellular pathways")
	check(coarse.rng.state==state,"resolution conversion draws no simulation randomness")
	var seeded=Sim.new(81)
	check(seeded.particle_count()==3760 and seeded.Catalog.data().ecology.visible_target==700,"new worlds use one tenth of the former external packet population")
	check(is_equal_approx(seeded.particles[0].amount,9),"initial stock carries three times the food at unchanged external packet count")
	var prior_ecology:=OS.get_environment("PRIMORDIA_ECOLOGY")
	OS.set_environment("PRIMORDIA_ECOLOGY","reference")
	var reference_world=Sim.new(81)
	check(reference_world.particle_count()==3760 and is_equal_approx(reference_world.particles[0].amount,0.3),"explicit reference ecology retains its historical finite fixture inventory")
	if prior_ecology!="": OS.set_environment("PRIMORDIA_ECOLOGY",prior_ecology)
	else: OS.unset_environment("PRIMORDIA_ECOLOGY")

	var exterior: Array=coarse.particles.duplicate(true)
	var internal_before: float=chemistry.material();var fuel_before: float=chemistry.potential()
	var v2: Dictionary=resolution.apply(coarse,1)
	check(coarse.particles==exterior and v2.external_before==v2.external_after,"v2 changes intracellular resolution only")
	check(absf(chemistry.material()-internal_before)<.000001 and absf(chemistry.potential()-fuel_before)<.000001,"v2 retains finite species and fuel")
	var density_packets: Array=[]
	for i in 1000:density_packets.append({"id":i,"species":"nad","source":-1,"compartment":-1,"amount":.05,"fuel":0.0,"p":Vector2(i%20,i/20)*.1,"previous":Vector2.ZERO,"v":Vector2.ZERO,"angle":0.0,"alive":true})
	var tenth: Dictionary=resolution._internal_tenth(density_packets,47)
	check(tenth.particles.size()==100,"dense compatible cytoplasm uses one tenth of the previous particles")
	var quantity:=0.0
	for packet in tenth.particles:quantity+=packet.amount
	check(absf(quantity-50)<.000001,"tenfold resolution retains the full cofactor inventory")
	var current: Array=chemistry.particles.duplicate(true)
	var v3: Dictionary=resolution.apply(coarse,2)
	check(chemistry.particles==current,"A historical density marker cannot repeat migration on the current food model")
	var converted: Array=chemistry.particles.duplicate(true)
	check(resolution.apply(coarse,resolution.VERSION).get("already_applied",false) and chemistry.particles==converted,"recorded migration cannot coalesce the saved world twice")
	var authority=preload("res://scripts/network/world_host.gd").new()
	authority.world=Sim.new(701,0,false)
	var second=Sim.Cell.new(1,Vector2(1000,1000));second.lineage=1
	authority.world.cells=[authority.world.player,second]
	var originals: Dictionary={"retained-session-a":{"root":0,"selected":0},"retained-session-b":{"root":1,"selected":1}}
	authority.accounts=originals.duplicate(true)
	var retained_map: Dictionary=authority.accounts.duplicate(true)
	var observer_fixture=preload("res://tests/realtime_checkpoint_gpu.gd")
	var messages: Array=observer_fixture.observer_credentials(authority,"fixture-invite")
	check(messages.size()==2 and messages.all(func(message):return message.get("token","").length()==64 and not message.has("invite")),"A fully player-owned saved pond resumes fixture observers without claiming more cells")
	check(retained_map.keys().all(func(key):return authority.accounts.get(key)==retained_map[key]) and authority.world.cells.size()==2,"Observer aliases preserve every original saved account and cell")
	check(messages.map(func(message):return authority.accounts[message.token.sha256_text()].selected)==[0,1],"Isolated observer bearers select the retained player bodies")
	authority.accounts.clear()
	messages=observer_fixture.observer_credentials(authority,"fixture-invite")
	check(messages.all(func(message):return message.get("invite","")=="fixture-invite" and not message.has("token")),"An unclaimed fixture still uses its explicit invitation without reading production credentials")
	authority.world=null;authority.free()
	print("NETWORK CORRECTNESS: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
