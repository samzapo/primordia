extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Budget=preload("res://scripts/particle_budget.gd")
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:
	var packets: Array=[]
	for kind in 13:
		for i in 1000:packets.append({"alive":true,"kind":kind,"amount":.3,"capacity":.3})
	var random:=RandomNumberGenerator.new();random.seed=82301
	var result: Dictionary=Budget.thin(packets,.4,random)
	check(result.removed>4900 and result.removed<5500,"Uniform thinning removes the requested fraction")
	for kind in 13:
		var count: int=packets.filter(func(packet):return packet.alive and packet.kind==kind).size()
		check(count>550 and count<650,"Every exterior species uses the same unbiased survival probability")
	var loss:=0.0
	for packet in packets:
		if not packet.alive:loss+=packet.amount*Sim.Catalog.material(packet.kind)
	check(absf(result.loss-loss)<.000001,"Removed material has an explicit sink")
	var before: int=random.state
	Budget.thin(packets,0,random)
	check(random.state==before,"Zero thinning does not draw random values")
	for pool in [false,true]:
		var sim=Sim.new(9307);sim.cells=[sim.player];sim.particles.clear();sim.grid.clear()
		for i in 100:sim.spawn_particle(i%13,Vector2(300+i,100),Vector2.ZERO,.3,7)
		if pool and sim.kernels!=null:sim.enable_particle_pool()
		var body_before: float=sim.player.organic_mass();var energy_before: float=sim.player.energy
		var total:=0.0
		for packet in sim.particle_snapshots():total+=packet.amount*Sim.Catalog.material(packet.kind)
		sim.particle_limit=50;sim.time=2;sim.thin_external_if_due()
		var kept:=0.0
		for packet in sim.particle_snapshots():
			if packet.alive:kept+=packet.amount*Sim.Catalog.material(packet.kind)
		check(absf(kept+sim.particle_thinning_loss-total)<.00001,"Reference/native destruction conserves material against outflow ledger")
		check(sim.player.organic_mass()==body_before and sim.player.energy==energy_before,"Exterior thinning cannot change internal stock or cell anatomy")
		check(sim.habitat_census().external<75 and sim.particle_thinning_removed>0,"Shared global limit actually lowers live external count")
	var saved=Sim.new(391);saved.particle_limit=5000;saved.particle_thinning_serial=7;saved.particle_thinning_due=81.0;saved.particle_thinning_random.seed=13
	saved.particle_thinning_random.randf()
	var restored=preload("res://scripts/network/state_codec.gd").new().restore(preload("res://scripts/network/state_codec.gd").new().capture(saved))
	check(restored.particle_limit==5000 and restored.particle_thinning_serial==7 and restored.particle_thinning_due==81.0 and restored.particle_thinning_random.state==saved.particle_thinning_random.state,"Restart retains the exterior limit, independent RNG, serial and deadline")
	print("PARTICLE BUDGET: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
