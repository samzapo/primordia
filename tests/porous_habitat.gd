extends RefCounted
const Sim = preload("res://scripts/simulation.gd")

static func fixture(hidden: bool, native: bool):
	var sim = Sim.new(917)
	sim.native_particles = native and sim.kernels != null
	sim.native_feeding = native and sim.kernels != null
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.pheromones.clear()
	sim.grid.clear()
	sim.evolution.enabled = false
	sim.camera_follows_player = false
	sim.camera_position = Vector2.ZERO if hidden else Vector2(2048,1280)
	sim.view_half = Vector2.ONE*(100 if hidden else 1000)
	sim.fluid.velocity.fill(Vector2(400,0))
	var h = sim.habitat_geometry
	h.forms = [{"branches":[{"a":Vector2(0,-500),"b":Vector2(0,500),"r":8.0,"depth":2}]}]
	h.plants = [{"p":Vector2(2048,1280),"radius":100.0,"form":0,"angle":0.0}]
	h.rebuild()
	return sim

static func run(check: Callable) -> void:
	for native in [false,true]:
		for hidden in [false,true]:
			var with_plants = fixture(hidden,native)
			var open_water = fixture(hidden,native)
			open_water.habitat_geometry.enabled = false
			for world in [with_plants,open_water]:
				for kind in 11:
					world.spawn_particle(kind,Vector2(1938,1280+(kind-5)*55),Vector2.ZERO,0.3,77)
				world.revision += 1
				world._move_particles(0.5)
				world.habitat_geometry.move_particles(world.particles,world.foreground_particle_ids,world.revision,world.grid,world.native_particles)
				world._settle_transport(world.foreground_particle_ids,false)
			for i in 11:
				var p: Dictionary = with_plants.particles[i]
				check.call(p.p.x > 2110 and p.amount == 0.3 and p.owner == 77,"Every chemical species flows through a plant without losing material or source metadata")
			check.call(with_plants.particles == open_water.particles and with_plants.rng.state == open_water.rng.state and with_plants.background_rng.state == open_water.background_rng.state,"Porous plant transport matches open water, including foreground/background clocks and RNG")
			check.call(with_plants.grid.query(with_plants.particles[0].p,10).has(0),"Permeating particles remain indexed for feeding and chemistry")
			var hit: Array = with_plants.habitat_geometry.move(Vector2(1938,1280),Vector2(2150,1280),Vector2(400,0),30)
			check.call(hit[2] and hit[0].x < 2011,"The same stem remains a swept physical obstacle to cells")

		# Hidden absorption must not invent an impermeable chemical wall.
		var sim = fixture(true,native)
		sim.player.position = Vector2(1988,1280)
		sim.player.previous_position = sim.player.position
		sim.player.organs.clear()
		sim.player.add_organ("feeding",0,"graze",false)
		sim.player.substrate = 0
		sim.player.energy = 100
		sim.spawn_particle(Sim.NUTRIENT,Vector2(2056,1280),Vector2.ZERO,0.3,77)
		sim.grid.rebuild(sim.particles)
		check.call(not Sim.Offscreen._clear_path(sim,sim.player.position,sim.particles[0].p),"Fixture separates grazer and food with a cell-solid stem")
		var before: float = sim.player.substrate+sim.particles[0].amount
		sim.offscreen_ecology._feed(sim,sim.player,100)
		check.call(sim.player.substrate > 0 and is_equal_approx(sim.player.substrate+sim.particles[0].amount,before),"Coarse grazers collect real permeating food across a stem without creating nutrients")
