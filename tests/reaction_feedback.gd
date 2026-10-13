extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Sparks = preload("res://scripts/reaction_sparks.gd")
static func fixture():
	var sim = Sim.new(903)
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.grid.clear()
	sim.acidity.values.fill(0.4)
	return sim
static func pair(sim, a: int, b: int, facing: bool = true) -> void:
	for item in [{"kind":a,"d":Vector2.RIGHT,"x":0},{"kind":b,"d":Vector2.LEFT if facing else Vector2.RIGHT,"x":3}]:
		sim.spawn_particle(item.kind,sim.player.position+Vector2(110+item.x,0),Vector2.ZERO,0.2,98)
		sim.particles[-1].direction = item.d
	sim.grid.rebuild(sim.particles)
static func run(check: Callable) -> void:
	for native in [false,true]:
		var sim = fixture()
		if native and sim.kernels == null: continue
		sim.native_particles = native
		for species in [[Sim.NUTRIENT,Sim.NUTRIENT],[Sim.ENZYME,Sim.WASTE],[Sim.ANTITOXIN,Sim.TOXIN],[Sim.ACID,Sim.BUFFER],[Sim.WASTE,Sim.OXYGEN],[Sim.NUTRIENT,Sim.TOXIN]]:
			sim.particles.clear()
			sim.grid.clear()
			sim.reaction_sparks.clear()
			sim.reaction_serial = 0
			pair(sim,species[0],species[1])
			sim._chemistry(0.000000001)
			check.call(sim.reaction_sparks.size() == 1,"Every supported successful pair reaction emits one presentation spark")
			check.call(sim.reaction_sparks[0].at.distance_to(sim.player.position+Vector2(111.5,0)) < 0.001,"Reaction spark marks the two particles' contact midpoint")
		sim = fixture()
		sim.native_particles = native
		pair(sim,Sim.NUTRIENT,Sim.NUTRIENT,false)
		sim._chemistry(0.000000001)
		check.call(sim.reaction_sparks.is_empty(),"Misaligned contacts produce no successful-reaction spark")
		sim = fixture()
		sim.native_particles = native
		pair(sim,Sim.NUTRIENT,Sim.OXYGEN)
		sim._chemistry(0.000000001)
		check.call(sim.reaction_sparks.is_empty(),"An incompatible particle collision is not shown as a reaction")
	var sim = fixture()
	var state: Array = [sim.rng.state,sim.background_rng.state,hash(sim.particles),sim.time]
	for i in 300: sim._record_reaction(sim.player.position+Vector2(110+i*0.01,0))
	check.call(sim.reaction_sparks.size() == Sim.REACTION_SPARK_LIMIT and sim.reaction_serial == 300,"Reaction presentation retains bounded storage without limiting biology")
	var view = Sparks.new()
	view._ready()
	view.sync(sim,sim.player.position,sim.view_half,0.8)
	check.call(view.displayed == 128 and view.multimesh.visible_instance_count == 128,"Dense reaction sparks use a bounded instanced draw batch")
	view.sync(sim,sim.player.position,sim.view_half,0.8,false)
	check.call(view.displayed == 0 and state == [sim.rng.state,sim.background_rng.state,hash(sim.particles),sim.time],"Hiding sparks leaves particles, clocks and random streams unchanged")
	sim.time = Sparks.LIFETIME
	view.sync(sim,sim.player.position,sim.view_half,0.8)
	check.call(view.displayed == 0,"Reaction sparks expire after a short simulation-time flash")
	view.free()
