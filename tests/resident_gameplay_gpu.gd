extends SceneTree
const Ecology=preload("res://scripts/resident_ecology.gd")
const Simulation=preload("res://scripts/simulation.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func organic(sim,packets: Array) -> float:
	var total: float=sim.lineage.stored_material()
	for cell in sim.cells:
		if not cell.dead: total+=cell.organic_mass()
	for p in packets:
		if p.alive and p.kind not in [1,3]: total+=p.amount
	return total
func start(sim,capacity: int=8192):
	var bridge=Ecology.new()
	bridge.start(sim,capacity)
	var status: Array=await bridge.initialized
	check(status[0],str(status[1]))
	return bridge
func run() -> void:
	Fixture.load_native()
	var first:=await play(false)
	var second:=await play(true)
	for key in first:
		if first[key] is float: check(absf(first[key]-second[key])<.00001,"Zoom/pan must not alter "+key)
		else: check(first[key]==second[key],"Zoom/pan must not alter "+key)
	await lifecycle()
	await escrow()
	print("RESIDENT_GAMEPLAY_VALIDATION ",checks," checks")
	quit()
func play(change_camera: bool) -> Dictionary:
	var sim=Simulation.new(39001)
	var before:=organic(sim,sim.particles)
	var bridge=await start(sim)
	var start_time:=Time.get_ticks_usec()
	for i in 240:
		if change_camera:
			sim.view_half=Vector2(40,30) if i%2==0 else Vector2(1000,800)
			sim.camera_follows_player=false;sim.camera_position=Vector2(i*17,i*7)
		sim.step(1.0/60)
		check(sim.resident!=null,"No fallback in normal gameplay")
		check(sim.particles.is_empty() and sim.pheromones.is_empty(),"No retained particle pose mirror")
		check(sim.active_cells==sim.cells.size(),"All living habitat cells advance")
	check(bridge.gpu.readbacks==0,"No full readback during gameplay")
	var elapsed: float=(Time.get_ticks_usec()-start_time)/240000.0
	var packets: Array=bridge.snapshots()
	var total: float=organic(sim,packets)+sim.respiration_loss-sim.external_input
	check(absf(total-before)<.002,"Finite cell+packet+reserve material including respiration: "+str(total-before))
	var result: Dictionary={"organic":total,"ATP":sim.player.energy,"body":sim.player.organic_mass(),"at":sim.player.position,
		"rng":str(sim.rng.state),"clock":sim.evolution.clock,"count":sim.particle_count(),"chemistry":sim.chemistry_events.duplicate()}
	print("GAMEPLAY_COUPLING ",JSON.stringify({"camera_changes":change_camera,"mean_tick_ms":elapsed,"live":sim.particle_count(),"material_error":total-before}))
	bridge.close();await bridge.gpu.closed
	return result
func lifecycle() -> void:
	var sim=Simulation.new(390012)
	var bridge=await start(sim)
	sim.begin_build()
	var clock: float=sim.time
	var revision: int=sim.revision
	check(sim.install("cilia",PI),"Paid organ installation during resident editing")
	sim.step(1.0/60)
	check(sim.time==clock and sim.revision==revision,"Editing pauses resident physics and chemistry")
	var id: int=sim.player.organs[-1].id
	check(sim.remove(sim.player.organs.size()-1),"Recycle during editing")
	check(sim.player.organ_by_id(id).is_empty(),"Build anatomy updates immediately")
	sim.commit_build()
	sim.step(1.0/60)
	var before:=organic(sim,bridge.snapshots())
	var old_id: int=sim.player.id
	var points: int=sim.evolution.points
	sim._die(sim.player)
	sim.lineage.recover(sim,1.0/60)
	check(sim.player.id!=old_id and not sim.player.dead,"Paid successor inherits the same habitat")
	check(sim.death_bursts.size()>0 and sim.death_bursts[-1].player,"Player lysis remains visible")
	check(sim.evolution.points==points,"Death does not reset adaptation points")
	var after:=organic(sim,bridge.snapshots())
	check(absf(before-after)<.002,"Lysis and reserve recovery conserve organic inventory")
	sim.step(1.0/60)
	check(sim.resident!=null and bridge.pending.is_empty(),"Large death release reaches resident pool")
	# A stable generation handle follows the same packet; no full pool picking.
	var packet: Dictionary=bridge.inspect(Vector2(2048,1280),4096)
	check(not packet.is_empty(),"Sparse GPU particle picking")
	var inspection_time: float=sim.time
	var inspection_rng: int=sim.rng.state
	var detached: Dictionary=sim.particle_snapshot(packet._index)
	check(detached._resident_handle==packet._resident_handle,"Detached snapshot preserves resident slot generation")
	var followed: Dictionary=bridge.inspect(Vector2.ZERO,1,packet._resident_handle)
	check(not followed.is_empty() and followed._resident_handle==packet._resident_handle,"Sparse tracking keeps generation identity")
	check(sim.time==inspection_time and sim.rng.state==inspection_rng,"Inspection does not advance ecology")
	bridge.close();await bridge.gpu.closed
func escrow() -> void:
	var sim=Simulation.new(390013)
	sim.cells=[sim.player];sim.particles=[];sim.pheromones=[];sim.grid.rebuild([])
	for i in 4: sim.spawn_particle(sim.NUTRIENT,Vector2(100+i*20,100),Vector2.ZERO,.3,7)
	var bridge=await start(sim,4)
	for i in 10: sim.spawn_particle(sim.WASTE,Vector2(100,100),Vector2.ZERO,.1,7)
	sim.spawn_particle(sim.NUTRIENT,Vector2(100,100),Vector2.ZERO,1e-100,7)
	check(bridge.trace_emissions.size()==1,"Sub-float material retained as emission escrow")
	var receipt: Dictionary=bridge._receipt([],[],{"feeding":false,"projection":false})
	check(receipt.get("_capacity",false),"Capacity refusal is explicit")
	var before:=organic(sim,bridge.snapshots())
	bridge.fallback("Intentional capacity regression")
	check(sim.resident==null and sim.particle_pool,"Recover authoritative CPU ownership")
	var after:=organic(sim,sim.particle_snapshots())
	check(absf(before-after)<.000001,"Fallback retains device material and every refused paid emission")
	check(sim.particle_count()==15,"Fallback retains tiny emission as well as regular packets")
	await bridge.gpu.closed
