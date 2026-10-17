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
	var pore: Dictionary=cell.organs[0]
	cell.exploration=4;cell.response_cycle=2;pore["steering"]=0
	cell.sense_clock=10;cell.age=3;cell.target_memory=1
	sim._sense(cell,DT)
	check.call(cell.drive_active and cell.target_mode=="graze","Legacy exploration/steering settings never interrupt a useful food cue")
	var heading: Vector2=cell.target
	cell.angle+=2;sim._sense(cell,DT)
	check.call(cell.target==heading,"World food intentions stay independent of body rotation")
	check.call(not cell.set_response_cycle(3) and not cell.set_exploration(1) and not cell.set_steering_strength(pore.id,2),"Retired behavior settings reject all edits")
	var child=sim.make_offspring(cell,sim.offspring_quote())
	check.call(cell.exploration==4 and cell.response_cycle==2 and pore.steering==0 and child.exploration==.25 and child.response_cycle==4 and child.organs[0].steering==1,"Parent legacy fields stay intact while a basic daughter starts fresh, with all retired controls inactive")
