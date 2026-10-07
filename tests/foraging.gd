extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Cues = preload("res://tests/pheromones.gd")
const DT := 1.0/60

static func fixture():
	var sim = Cues.isolated()
	sim.player.organs.clear()
	sim.player.add_organ("feeding",0,"graze",false)
	sim.player.add_organ("propulsion",PI,"graze",false)
	return sim

static func aim(sim) -> void:
	sim.grid.rebuild(sim.particles)
	sim.player.sense_clock = 0
	for i in 40: sim._sense(sim.player,DT)

static func run(check: Callable) -> void:
	var sim = fixture()
	var cell = sim.player
	sim.spawn_particle(Sim.NUTRIENT,cell.position+Vector2(85,0),Vector2.ZERO,0.3,77)
	for i in 12:
		sim.spawn_particle(Sim.NUTRIENT,cell.position+Vector2(-240+i%3*7,25+i/3*6),Vector2.ZERO,0.3,77)
	var states: Array = [sim.rng.state,sim.background_rng.state,sim.ecology_rng.state]
	var material: int = hash(sim.particles)
	aim(sim)
	var direction: Vector2 = Sim.Medium.offset(cell.position,cell.target_position)
	check.call(direction.x < -200 and direction.y > 20,"A distant food patch outweighs a nearby lone particle")
	check.call(states == [sim.rng.state,sim.background_rng.state,sim.ecology_rng.state] and material == hash(sim.particles),"Patch sensing changes no food or biological random draws")
	# Translation across the toroidal seam retains patch geometry.
	var old_target: Vector2 = direction
	var shift := Vector2(2020,0)
	cell.position = Sim.Medium.wrap_position(cell.position+shift)
	for p in sim.particles: p.p = Sim.Medium.wrap_position(p.p+shift)
	cell.target_memory = 0
	cell.signals.clear()
	aim(sim)
	check.call(Sim.Medium.offset(cell.position,cell.target_position).distance_to(old_target) < 0.01,"Local patch moments stay correct across the periodic seam")
	# Inside the patch, aim at an actual packet, not an empty centroid.
	sim = fixture()
	cell = sim.player
	for at in [Vector2(55,-12),Vector2(61,18),Vector2(64,25)]:
		sim.spawn_particle(Sim.NUTRIENT,cell.position+at,Vector2.ZERO,1,77)
	aim(sim)
	check.call(sim.particles.any(func(p): return Sim.Medium.offset(cell.target_position,p.p).length() < 0.01),"An inner-threshold grazer steers to a real food particle")
	# Distant equally large opposing clouds select one instead of cancelling.
	sim = fixture()
	cell = sim.player
	for side in [-1,1]:
		for i in 8: sim.spawn_particle(Sim.NUTRIENT,cell.position+Vector2(side*(240+i),0),Vector2.ZERO,1,77)
	aim(sim)
	check.call(Sim.Medium.offset(cell.position,cell.target_position).length() > 230,"Separated opposing clouds do not produce an empty midpoint goal")
	var pore: Dictionary = cell.organs[0]
	cell.set_exploration(1)
	check.call(is_equal_approx(cell.response_share(pore),0.5),"Equal signal and exploration weights split following time equally")
	cell.set_steering_strength(pore.id,0.25)
	check.call(is_equal_approx(cell.response_share(pore),0.2),"A weaker signal grants proportionately more exploration time")
	cell.set_steering_strength(pore.id,1)
	cell.sense_clock = 10
	cell.target_memory = 1
	cell.age = 3
	sim._sense(cell,DT)
	check.call(not cell.drive_active and cell.target_memory > 0 and cell.state == "EXPLORING · RESPONSE CYCLE","Exploration happens despite a valid refreshing signal and preserves its bounded memory")
	var heading: Vector2 = cell.target
	cell.angle += 2
	sim._sense(cell,DT)
	check.call(cell.target == heading,"Exploration heading is independent of cell rotation, avoiding perpetual spirals")
	cell.age = 0.5
	sim._sense(cell,DT)
	check.call(cell.drive_active and cell.target_mode == "graze","The response cycle returns to its remembered signal")
	cell.set_exploration(0)
	cell.age = 3.8
	sim._sense(cell,DT)
	check.call(cell.drive_active,"Exploration Off follows a valid signal for the entire cycle")
	cell.add_organ("sensing",1,"flee",false)
	var flight: Dictionary = cell.organs[-1]
	cell.target_organ_id = flight.id
	cell.target_mode = "flee"
	cell.target_lineage = 77
	cell.target_memory = 1
	cell.set_exploration(4)
	sim._sense(cell,DT)
	check.call(cell.drive_active and cell.state == "FLEEING","Explicit flight bypasses exploration duty")
	check.call(not cell.set_response_cycle(3) and not cell.set_exploration(NAN),"Invalid behavior settings are rejected")
	cell.set_exploration(0.5)
	cell.set_response_cycle(8)
	var child = sim.make_offspring(cell,sim.offspring_quote())
	check.call(child.exploration == 0.5 and child.response_cycle == 8,"Paid successors inherit exploration weight and response cycle")
	child.set_exploration(2)
	check.call(cell.exploration == 0.5,"A child's behavior settings are independent of its parent")
