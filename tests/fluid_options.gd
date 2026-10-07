extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Fluid = preload("res://scripts/fluid_compare.gd")
const Fixture = preload("res://tests/fluid_fixture.gd")
static func totals(sim) -> Dictionary:
	var out := {}
	for packet in sim.particles:
		if not packet.alive or packet.kind == sim.PHEROMONE: continue
		for key in ["amount","capacity","product"]:
			var name: String = str(packet.kind)+":"+str(key)
			out[name] = out.get(name,0.0)+float(packet.get(key,0))
	return out
static func run(check: Callable) -> void:
	check.call(Fluid.valid_options("grid",16,80) and Fluid.valid_options("pbf",32,8),"Both fluid comparison configurations are explicit")
	for args in [["wrong",16,8],["grid",0,8],["grid",16,3],["pbf",16,0],["pbf",16,258]]:
		check.call(not Fluid.valid_options(args[0],args[1],args[2]),"Reject invalid fluid parameters")
	var sim = Sim.new(25171)
	check.call(sim.experimental_fluid == null,"Normal gameplay retains its established fluid backend")
	sim._emit_pheromone(sim.cells[1])
	check.call(sim.pheromones.size() == 1,"Fixture checks a real immutable pheromone")
	var inventory: Dictionary = totals(sim)
	var before: float = Fixture.packet_material(sim)
	var rng_state: int = sim.rng.state
	var pheromones: Array = sim.pheromones.duplicate()
	check.call(not Fixture.seed_packets(sim,1,"uniform"),"Resolution fixture cannot silently drop original chemical inventory")
	var size: int = sim.particles.size()
	var count := maxi(6000,size*2)
	check.call(Fixture.seed_packets(sim,count,"uniform"),"Finite chemical resolution sweep succeeds")
	var after: Dictionary = totals(sim)
	for key in inventory:
		check.call(absf(inventory[key]-after.get(key,0))<0.000001,"Species material/capacity conserved when packets split: "+key)
	check.call(absf(before-Fixture.packet_material(sim))<0.000001,"Organic fixture material is unchanged")
	check.call(sim.particles.size() == count+pheromones.size(),"Requested chemical count is separate from pheromone tracers")
	check.call(sim.rng.state == rng_state,"Fixture placement uses its own random stream")
	for packet in pheromones:
		check.call(sim.particles.has(packet),"Pheromone snapshots retain identity/expiry")
	var values := PackedVector2Array()
	values.resize(2560)
	values.fill(Vector2(20,-7))
	for point in [Vector2.ZERO,Sim.WORLD,Vector2(-1,-1),Vector2(4095,2559)]:
		check.call(Fluid.sample_array(values,point).is_equal_approx(Vector2(20,-7)),"Common fluid exchange samples wrap at torus seams")
