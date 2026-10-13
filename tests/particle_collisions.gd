extends RefCounted
const Sim = preload("res://scripts/simulation.gd")

static func fixture(backend: String, collisions: bool, hidden: bool, second_kind: int, aligned: bool):
	var sim = Sim.new(928)
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.grid.clear()
	sim.native_particles = backend != "script" and sim.kernels != null
	sim.particle_collisions = collisions
	sim.camera_follows_player = false
	sim.camera_position = Vector2(2048,1600) if hidden else Vector2(0,800)
	sim.view_half = Vector2(100,100)
	sim.acidity.values.fill(0.4)
	sim.time = 0.00000001
	sim.revision = 1
	sim.rng.seed = 118
	sim.spawn_particle(Sim.NUTRIENT,Vector2(4094,800),Vector2.ZERO,0.2,91)
	sim.spawn_particle(second_kind,Vector2(2,800),Vector2.ZERO,0.2,92)
	sim.particles[0].direction = Vector2.RIGHT if aligned else Vector2.LEFT
	sim.particles[1].direction = Vector2.LEFT
	sim.particles[0].chemical_at = 0.0
	sim.particles[1].chemical_at = 0.0
	sim.grid.rebuild(sim.particles)
	if backend == "pool": sim.enable_particle_pool()
	return sim

static func run(check: Callable) -> void:
	check.call(Sim.new(928).particle_collisions,"Ordinary particles collide by default; overlap remains an explicit diagnostic")
	for backend in ["script","native","pool"]:
		if backend != "script" and Sim.new(928).kernels == null: continue
		for hidden in [false,true]:
			for collisions in [false,true]:
				for scenario in ["incompatible","misaligned","reaction"]:
					var kind: int = Sim.OXYGEN if scenario == "incompatible" else Sim.NUTRIENT
					var sim = fixture(backend,collisions,hidden,kind,scenario != "misaligned")
					var patch: Array[int] = []
					if hidden: patch.assign([0,1])
					var before: Array = sim.particle_snapshots()
					sim._chemistry(0.00000001,patch,hidden)
					var after: Array = sim.particle_snapshots()
					var tag := "%s / collisions %s / hidden %s / %s" % [backend,collisions,hidden,scenario]
					check.call(after[0].p == before[0].p and after[1].p == before[1].p,"Pair chemistry never projects positions: "+tag)
					if scenario == "reaction":
						check.call(after[0].alive and not after[1].alive and is_equal_approx(after[0].amount,0.4) and sim.chemistry_events.combine == 1 and sim.reaction_sparks.size() == (0 if hidden else 1),"Aligned reactions and finite mass still work: "+tag)
					else:
						check.call(after[0].alive and after[1].alive and sim.reaction_sparks.is_empty(),"Wrong species/facing cannot bind: "+tag)
						check.call((after[0].v.x < 0 and after[1].v.x > 0) if collisions else (after[0].v == Vector2.ZERO and after[1].v == Vector2.ZERO),"Only the collision comparison mode adds separation impulses: "+tag)
					if scenario == "misaligned" and not collisions:
						sim.particle_collisions = true
						sim.revision += 1
						sim.time += 0.00000001
						sim._chemistry(0.00000001,patch,hidden)
						var switched: Array = sim.particle_snapshots()
						check.call(switched[0].v.x < 0 and switched[1].v.x > 0,"Live toggle works without re-importing particles: "+tag)

	# A zero-current cloud spreads through independent thermal displacement.
	for backend in ["script","native","pool"]:
		var sim = Sim.new(928)
		if backend != "script" and sim.kernels == null: continue
		sim.native_particles = backend != "script"
		sim.cells = [sim.player]
		sim.particles.clear()
		sim.grid.clear()
		sim.fluid.velocity.fill(Vector2.ZERO)
		sim.camera_follows_player = false
		var origin := Vector2(500,800)
		sim.camera_position = origin
		sim.view_half = Vector2(100,100)
		for i in 256: sim.spawn_particle(Sim.ENZYME,origin,Vector2.ZERO,0.1,91)
		sim.grid.rebuild(sim.particles)
		if backend == "pool": sim.enable_particle_pool()
		for i in 32: sim._move_particles(1.0/60)
		var mean := Vector2.ZERO
		var mean_square := 0.0
		for packet in sim.particle_snapshots():
			var offset: Vector2 = sim.Medium.offset(origin,packet.p)
			mean += offset/256
			mean_square += offset.length_squared()/256
		var expected := 2.0*12.0*32.0/60.0
		check.call(mean_square > expected*0.7 and mean_square < expected*1.3 and mean.length_squared() < 1.0,"A coincident collision-free cloud spreads by independent random walk at the existing diffusion rate: "+backend)
