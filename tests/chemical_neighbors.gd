extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Compare = preload("res://tests/packed_particles.gd")
const Pool = preload("res://tests/particle_pool.gd")
const DT := 1.0/60

static func run(check: Callable) -> void:
	var probe = Sim.new(30)
	if probe.kernels == null: return
	var fixture = preload("res://tests/fluid_fixture.gd")
	var before: float = fixture.packet_material(probe)
	check.call(fixture.seed_packets(probe,20000,"clustered","mixed") and absf(fixture.packet_material(probe)-before)<0.00001,"Mixed-radius benchmark keeps finite cell-produced material")
	check.call(not probe.kernels.neighbor_configure("invalid",false,true),"Unknown neighbor backend is rejected")
	for backend in ["legacy","packed","bvh","quadtree"]:
		for cache in [false,true]:
			if backend == "legacy" and not cache: continue
			# Every species, varied radii, seam/bin boundaries, acid gradients,
			# repeated mutations and both chemistry tiers against the old path.
			for hidden in [false,true]:
				for collisions in [false,true]:
					var fast = Sim.new(619)
					var slow = Sim.new(619)
					for sim in [fast,slow]:
						sim.particles.clear()
						sim.grid.clear()
						sim.camera_follows_player = false
						sim.camera_position = Vector2.ZERO
						sim.view_half = Vector2(120,120)
						sim.particle_collisions = collisions
					var random := RandomNumberGenerator.new()
					random.seed = 304817
					var anchors := [Vector2(0,0),Vector2(16,16),Vector2(4095.99,2559.99),Vector2(96,96)]
					for i in 440:
						fast.spawn_particle(i%Sim.SPECIES_COUNT,Sim.Medium.wrap_position(anchors[i%4]+Vector2(random.randf_range(-12,12),random.randf_range(-12,12))),Vector2.ZERO,[0.00001,0.3,1.4,2.0][i%4],91)
						fast.particles[-1].chemical_at = 0.0
					for i in fast.acidity.values.size(): fast.acidity.values[i] = random.randf()
					slow.particles = fast.particles.duplicate(true)
					slow.acidity.values = fast.acidity.values.duplicate()
					for sim in [fast,slow]:
						sim.grid.rebuild(sim.particles)
						sim.rng.seed = 118
					fast.enable_particle_pool()
					fast.kernels.neighbor_configure(backend,cache,true)
					var ids: Array[int] = []
					# Nontrivial insertion order is distinct from identity order.
					for i in range(439,-1,-1): ids.append(i)
					for tick in 12:
						for sim in [fast,slow]:
							sim.time += DT
							sim.revision += 1
							sim._chemistry(DT,ids,hidden)
						check.call(Compare.same_packets(fast.particle_snapshots(),slow.particles) and fast.rng.state == slow.rng.state and fast.acidity.values == slow.acidity.values and fast.chemistry_events == slow.chemistry_events,"%s/cache=%s preserves oriented, wrapped, mixed-radius contacts and insertion order" % [backend,cache])
			full_ecology(check,backend,cache)
			cache_changes(check,backend,cache)

static func full_ecology(check: Callable, backend: String, cache: bool) -> void:
	var fast = Sim.new(25171)
	var slow = Sim.new(25171)
	for sim in [fast,slow]: sim.view_half = Sim.VIEW/0.8/2
	fast.enable_particle_pool()
	slow.enable_particle_pool()
	fast.kernels.neighbor_configure(backend,cache,true)
	for tick in 180:
		if tick in [35,70,110,145]:
			for sim in [fast,slow]:
				sim.camera_follows_player = false
				sim.camera_position = Vector2(4080 if tick == 70 else 600 if tick == 110 else 2048,1280)
		fast.step(DT)
		slow.step(DT)
		if tick%15 == 0 or tick == 179:
			check.call(Compare.same_packets(fast.particle_snapshots(),slow.particle_snapshots()) and Pool.same_cells(fast,slow) and fast.acidity.values == slow.acidity.values and fast.chemistry_events == slow.chemistry_events and [fast.rng.state,fast.background_rng.state,fast.ecology_rng.state] == [slow.rng.state,slow.background_rng.state,slow.ecology_rng.state],"%s/cache=%s retains full ecology, RNG, coarse transport, feeding and membrane exclusion" % [backend,cache])

static func cache_changes(check: Callable, backend: String, cache: bool) -> void:
	var fast = Sim.new(30)
	var slow = Sim.new(30)
	for sim in [fast,slow]:
		sim.particles.clear()
		sim.grid.clear()
		sim.camera_follows_player = false
		sim.camera_position = Vector2.ZERO
		sim.view_half = Vector2(50,50)
		# Toxins do not merge with each other, giving the cache genuine reuse.
		for p in [Vector2(4095.9,0),Vector2(3,0),Vector2(15.9,0),Vector2(25,0)]:
			sim.spawn_particle(Sim.TOXIN,p,Vector2.ZERO,0.3,91)
		sim.grid.rebuild(sim.particles)
	fast.kernels.neighbor_configure(backend,cache,true)
	for tick in 10:
		for sim in [fast,slow]:
			if tick == 2: sim.particles[0].p = Vector2(0.1,0)
			if tick == 3: sim.particles[2].p = Vector2(16.1,0)
			if tick == 4: sim.particles[3].amount = 1.4
			if tick == 5: sim.particles[2].p = Vector2(80,0)
			if tick == 6:
				sim.enable_particle_pool()
				sim.camera_position = Vector2(80,0)
				sim.view_half = Vector2(1,1)
			if tick == 7:
				sim.kernels.pool_patch(0,{"alive":false})
				sim._compact_particles()
			if tick == 8: sim.spawn_particle(Sim.TOXIN,Vector2(20,0),Vector2.ZERO,0.3,91)
			if tick == 9:
				sim.disable_particle_pool()
				sim.enable_particle_pool()
			sim.grid.rebuild(sim.particles)
			sim.time += DT
			sim.revision += 1
			sim._chemistry(DT)
		check.call(Compare.same_packets(fast.particle_snapshots(),slow.particle_snapshots()) and fast.rng.state == slow.rng.state,"%s/cache=%s preserves seam/bin crossing, radius growth, activation, births, compaction and re-import" % [backend,cache])
	if cache:
		var metrics: Dictionary = fast.kernels.neighbor_metrics()
		check.call(metrics.cache_hits > 0 and metrics.cache_misses >= 4,"Cache is reused and conservatively invalidated for structural/geometric changes")
