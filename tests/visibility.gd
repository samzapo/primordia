extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Medium = Sim.Medium

static func run(check: Callable) -> void:
	var half := Vector2(500,300)
	for camera in [Vector2(2048,1280),Vector2(4,6),Vector2(4090,2554)]:
		for direction in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1),Vector2(1,0),Vector2(0,1)]:
			var edge: Vector2 = Medium.wrap_position(camera+direction*half)
			check.call(Medium.visibility(edge,camera,half) == 1,"All viewport edges/corners remain fully active across wrapping seams")
			var fluid := Medium.new()
			fluid.set_camera(camera,half)
			check.call(absf(fluid._weights(edge)-1.0) < 0.00001,"Every fluid interpolation neighbor at the visible edge runs at full speed")
		check.call(Medium.visibility(camera+Vector2(560,0),camera,half) == 1,"Simulation continues at full speed just beyond the visible rectangle")
		check.call(is_equal_approx(Medium.visibility(camera+Vector2(596,0),camera,half),0.5),"Only the offscreen outer band slows simulation")
		check.call(Medium.visibility(camera+Vector2(629,0),camera,half) == 0,"Distant offscreen state remains dormant")
	_transport_and_chemistry(check)
	var world = Sim.new(713)
	world.evolution.enabled = false
	world.habitat_geometry.enabled = false
	world.cells = [world.player]
	world.particles.clear()
	world.pheromones.clear()
	world.grid.rebuild(world.particles)
	world.camera_follows_player = false
	world.camera_position = Vector2(1000,1000)
	world.view_half = Vector2(250,150)
	world.player.biomass = 18000
	world.player.update_geometry()
	world.player.membrane = Sim.Cell.Membrane.new(world.player.radius)
	world.player.position = world.camera_position+Vector2(world.view_half.x+world.player.extent()*0.75,0)
	world.player.previous_position = world.player.position
	check.call(world.activity_at(world.player.position) == 0 and world.activity_for_cell(world.player) == 1,"A large visible membrane stays active even when its center is beyond the point-particle halo")
	world.step(1.0/60)
	check.call(is_equal_approx(world.player.age,1.0/60),"A partially visible large cell advances real biology at the full timestep")
	world.camera_position = Medium.wrap_position(world.camera_position-Vector2(1600,800))
	var age: float = world.player.age
	world.step(1.0/60)
	check.call(world.player.age == age,"Moving the free camera away makes the entirely hidden cell dormant")

static func _transport_and_chemistry(check: Callable) -> void:
	var fast = Sim.new(981)
	var slow = Sim.new(981)
	slow.native_particles = false
	var half := Vector2(500,300)
	var camera := Vector2(4070,2510)
	for world in [fast,slow]:
		world.camera_follows_player = false
		world.camera_position = camera
		world.view_half = half
		world.particles.clear()
		world.pheromones.clear()
		world.grid.rebuild(world.particles)
		for offset in [Vector2(490,290),Vector2(-490,-290),Vector2(560,0),Vector2(596,0),Vector2(700,0)]:
			world.spawn_particle(Sim.NUTRIENT,camera+offset,Vector2(20,8),0.3)
		world.rng.seed = 83
		world._move_particles(0.02)
	check.call(fast.active_particles == 4 and slow.active_particles == 4,"Native/reference broad phases include the offscreen simulation halo")
	for i in 5:
		var a: Dictionary = fast.particles[i]
		var b: Dictionary = slow.particles[i]
		check.call(a.p.distance_to(b.p) < 0.001 and absf(a.age-b.age) < 0.000001,"Native/reference edge transport agrees, including corner, fringe and dormancy")
		check.call(absf(a.age-([0.02,0.02,0.02,0.01,0.0][i])) < 0.000001,"Particle age follows full visible speed, offscreen fade and far dormancy")
	for world in [fast,slow]:
		world.particles.clear()
		world.grid.rebuild(world.particles)
		var at := camera+Vector2(590,0)
		world.spawn_particle(Sim.ANTITOXIN,at,Vector2.ZERO,0.3,0)
		world.spawn_particle(Sim.TOXIN,at+Vector2(3,0),Vector2.ZERO,0.3,1)
		world.particles[0].direction = Vector2.RIGHT
		world.particles[1].direction = Vector2.LEFT
		world.rng.seed = 45
		world._chemistry(0.0000001)
		check.call(world.chemistry_events.neutralize == 1,"Oriented chemistry also runs in the offscreen halo")
