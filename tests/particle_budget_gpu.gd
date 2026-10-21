extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var data:=PackedFloat32Array();var metadata: Array=[]
	for kind in 13:
		for i in 500:
			var slot: int=data.size()/12
			data.append_array(PackedFloat32Array([100+i,100,0,0,0,0,0,kind,6,.3,.3,0]))
			if kind==3:metadata.append({"slot":slot,"owner":7,"lineage":7,"expires_at":30.,"report":{"id":7,"lineage":7,"at":Vector2(100+i,100),"mass":20.,"radius":30.,"emitted_at":0.,"hostile":false,"defended":false}})
	var field:=PackedFloat32Array();field.resize(2560)
	var gpu=GPU.new();gpu.configure_interactions("chemistry");gpu.configure_exchange();gpu.configure_perception();gpu.configure_chemistry(field,90211);gpu.configure_transfer()
	gpu.initialize(data,Fixture.flow(),metadata)
	var ready: Array=await gpu.ready;check(ready[0],str(ready[1]))
	if not ready[0]:quit(1);return
	var before: Dictionary=gpu.exchange_sync([],[],[],[],{"feeding":false,"projection":false})
	var result: Dictionary=gpu.thin_sync(.4,1)
	check(not result.has("error"),"Valid GPU thinning request")
	if result.has("error"):quit(1);return
	check(result.removed>2450 and result.removed<2750 and result.alive+result.removed==6500,"GPU thinning counts every live slot exactly once")
	var after: Dictionary=gpu.exchange_sync([],[],[],[],{"feeding":false,"projection":false})
	check(absf(before.chemistry.material-after.chemistry.material-result.loss)<.001,"GPU removal is charged to the exact material sink")
	gpu.snapshot();var state: PackedFloat32Array=await gpu.snapshot_ready
	for kind in 13:
		var count:=0
		for i in 6500:
			if state[i*12+7]==kind:count+=1
		check(count>250 and count<350,"GPU survival probability is shared across every species including signals")
	var all: Dictionary=gpu.thin_sync(1,2)
	check(absf(result.fuel_loss+all.fuel_loss-150*preload("res://scripts/cell_chemistry.gd").FOOD_FUEL)<.1,"Resident thinning accounts for the current finite food energy")
	check(all.alive==0 and all.signals==0 and gpu.work_count==1,"Empty pool releases stale dispatch work without resetting generations")
	var products: Array=[{"owner":7,"state":PackedFloat32Array([100,100,0,0,0,0,0,0,8,.3,.3,0])}]
	var admitted: Dictionary=gpu.exchange_sync([],products,[],[],{"feeding":false,"projection":false})
	check(admitted.emissions[0].accepted and admitted.emissions[0].handle.y>1,"Refill increments retained slot generation after an empty-pool trim")
	check(gpu.readbacks==1 and gpu.thinning_readback_bytes==64,"Thinning reads exactly32 bytes per pass, not particle snapshots")
	gpu.close();await gpu.closed
	await coupled_owners()
	print("PARTICLE BUDGET GPU: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func coupled_owners() -> void:
	var sim=preload("res://scripts/simulation.gd").new(93011)
	sim.cells=[sim.player];sim.particles.clear();sim.grid.clear()
	for i in 600:
		sim.spawn_particle([0,1,2,5,8,9][i%6],sim.player.position+Vector2(i%20,0) if i%2==0 else Vector2(40,40),Vector2.ZERO,.3,7)
	var bridge=preload("res://scripts/resident_ecology.gd").new();bridge.start(sim,8192)
	var ready: Array=await bridge.initialized;check(ready[0],str(ready[1]))
	if not ready[0]:quit(1);return
	sim.spawn_particle(4,sim.player.position+Vector2(40,0),Vector2.ZERO,.15,7)
	sim.spawn_particle(0,sim.player.position+Vector2(40,0),Vector2.ZERO,1e-100,7)
	var packets: Array=bridge.snapshots()
	var material:=0.0
	for packet in packets:material+=packet.amount*sim.Catalog.material(packet.kind)
	var body: float=sim.player.organic_mass();var energy: float=sim.player.energy
	var random:=RandomNumberGenerator.new();random.seed=8712
	var removed: Dictionary=bridge.thin(1,4,random)
	check(not removed.has("error") and absf(removed.loss-material)<.0001,"GPU, cold chunks, paid emissions and sub-float escrow share the explicit outflow ledger")
	check(sim.habitat_census().external==0 and bridge.snapshots().is_empty(),"No disjoint exterior owner escapes the global limit")
	check(sim.player.organic_mass()==body and sim.player.energy==energy,"Exterior GPU limit cannot spend body/internal resources")
	check(sim.particles.is_empty() and sim.pheromones.is_empty(),"Thinning never creates a CPU pose mirror for resident particles")
	sim.pending_replacements.clear();sim.automatic_reproduction=false
	for i in 600:sim.spawn_particle(0,sim.player.position+Vector2(80+i%20,0),Vector2.ZERO,.3,7)
	var before:=organic(sim)
	sim.particle_limit=100
	for i in 60:
		sim.step(1./30)
		check(sim.resident==bridge and sim.particles.is_empty(),"Periodic budget stays resident with no CPU pose mirror")
	check(sim.particle_thinning_removed>0 and sim.habitat_census().external<160,"Global periodic controller regulates the live coupled pond")
	check(absf(organic(sim)-before)<.01,"Coupled feeding, transport and thinning preserve total organic bookkeeping")
	bridge.close();await bridge.gpu.closed

func organic(sim) -> float:
	var total: float=sim.lineage.stored_material()+sim.respiration_loss-sim.external_input
	for cell in sim.cells:
		if not cell.dead:total+=cell.organic_mass()
	for packet in sim.particle_snapshots():
		if packet.alive:total+=packet.amount*sim.Catalog.material(packet.kind)
	return total
