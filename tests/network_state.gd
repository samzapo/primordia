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
	var damaged:=FileAccess.open(store.directory.path_join("world-0.pworld"),FileAccess.WRITE)
	damaged.store_string("interrupted");damaged.close()
	check(store.load_latest().tick==17,"corrupt newer generation falls back to valid previous checkpoint")
	restored.world.grid.rebuild(restored.world.particles)
	check(restored.world.time==before,"host downtime is not charged during restore")
	for path in ["world-0.pworld","world-1.pworld"]:
		DirAccess.remove_absolute(store.directory.path_join(path))
	DirAccess.remove_absolute(store.directory)
	print("NETWORK CORRECTNESS: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
