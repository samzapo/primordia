extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:
	for backend in ["script","native","pool"]:
		for kind in [Sim.ACID,Sim.BUFFER]:
			var sim=Sim.new(20261016)
			if backend!="script" and sim.kernels==null:continue
			sim.native_particles=backend!="script";sim.cells=[sim.player]
			sim.particles.clear();sim.grid.clear()
			sim.camera_follows_player=false;sim.camera_position=Vector2(96,96);sim.view_half=Vector2(100,100)
			sim.acidity.values.fill(.4)
			sim.spawn_particle(kind,Vector2(96,96),Vector2.ZERO,.3,7)
			sim.particles[0].capacity=.00000002;sim.grid.rebuild(sim.particles)
			if backend=="pool":sim.enable_particle_pool()
			sim._chemistry(.000001)
			var packet: Dictionary=sim.particle_snapshot(0)
			check(packet.kind==Sim.WASTE and packet.capacity>=0,"Exhausted sub-ULP charge remains nonnegative: "+backend)
			check(absf(packet.amount-.3)<.000001 and packet.alive,"Charge rounding preserves material and packet life")
	var old: Dictionary={"kind":Sim.WASTE,"capacity":-.00000002421439,"amount":.18}
	check(Sim.repair_spent_charge(old) and old.capacity==0 and old.amount==.18,"Known old spent-charge remainder is repaired")
	check(not Sim.repair_spent_charge({"kind":Sim.NUTRIENT,"capacity":-.00000002}),"Negative fuel remains invalid")
	check(not Sim.repair_spent_charge({"kind":Sim.WASTE,"capacity":-.1}),"Substantive corruption remains invalid")
	print("PARTICLE CHARGE: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
