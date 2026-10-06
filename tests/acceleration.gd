extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
static func run(check: Callable) -> void:
	var fast = Sim.new(531)
	var slow = Sim.new(531)
	if fast.kernels == null:
		print("ACCELERATION: native comparison skipped (reference backend)")
		return
	slow.native_particles = false
	slow.native_exclusion = false
	slow.native_fluid = false
	slow.native_feeding = false
	slow.native_contacts = false
	slow.spatial_queries = false
	slow.grid.native_enabled = false
	slow.reaction_grid.native_enabled = false
	# Exercise all species pair orders, three acid regimes, facing and misfacing.
	for acid in [0.0,0.4,0.95]:
		for aligned in [true,false]:
			for a in Sim.SPECIES_COUNT:
				for b in Sim.SPECIES_COUNT:
					fast.particles.clear()
					fast.grid.rebuild(fast.particles)
					fast.spawn_particle(a,fast.player.position,Vector2(2,0),0.3,0)
					fast.spawn_particle(b,fast.player.position+Vector2(4,0),Vector2(-3,0),0.4,1)
					fast.particles[0].direction = Vector2.RIGHT if aligned else Vector2.LEFT
					fast.particles[1].direction = Vector2.LEFT
					slow.particles = fast.particles.duplicate(true)
					for sim in [slow,fast]:
						sim.grid.rebuild(sim.particles)
						sim.acidity.values.fill(acid)
						sim.rng.seed = 781
						sim.revision += 1
						sim._chemistry(0.0000001)
					var agrees := true
					for i in 2:
						var x: Dictionary = slow.particles[i]
						var y: Dictionary = fast.particles[i]
						agrees = agrees and x.kind==y.kind and x.alive==y.alive and absf(x.amount-y.amount)<0.00001 and absf(x.capacity-y.capacity)<0.00001 and x.v.distance_to(y.v)<0.0001
					check.call(agrees,"Native chemistry matches reference species %d/%d, acid %.2f, aligned %s" % [a,b,acid,aligned])
	fast = Sim.new(123)
	slow = Sim.new(123)
	slow.native_particles = false
	fast.view_half = Vector2(3000,2000)
	slow.view_half = fast.view_half
	fast._move_particles(1.0/60)
	slow._move_particles(1.0/60)
	var error := 0.0
	for i in fast.particles.size():
		error = maxf(error,Sim.Medium.offset(fast.particles[i].p,slow.particles[i].p).length())
	check.call(error<0.001,"Native transport preserves reference thermal draw order and wrapped positions")
	# Fluid symmetry, dormant nodes and acid transport remain numerically equivalent.
	var medium = Sim.Medium.new()
	medium.set_camera(Vector2(4080,1280),Vector2(1300,950))
	var expected: PackedVector2Array = fast.kernels.fluid_step(medium.velocity,medium.activity,medium.tide,1.0/60,true)
	medium.step(1.0/60)
	error = 0
	for i in expected.size(): error=maxf(error,expected[i].distance_to(medium.velocity[i]))
	check.call(error<0.0001,"Native fluid flux agrees with conservative reference across periodic seams")
	fast.acidity.values.fill(0.4)
	fast.acidity.exchange(Vector2(4090,1100),0.5)
	var acid_expected: PackedFloat32Array = fast.kernels.acid_step(fast.acidity.values,medium.velocity,medium.activity,0.1)
	fast.acidity.step(0.1,medium)
	error = 0
	for i in acid_expected.size(): error=maxf(error,absf(acid_expected[i]-fast.acidity.values[i]))
	check.call(error<0.00001,"Native acidity transport agrees with reference")
	# Native/query acceleration must not let particles enter a cell at the seam.
	for sim in [slow,fast]:
		sim.cells = [sim.player]
		sim.player.position = Vector2(4094,1280)
		sim.player.previous_position = sim.player.position
		sim.player.activity = 1
		sim.particles.clear()
		sim.grid.rebuild(sim.particles)
		for i in 50: sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2.from_angle(i*2.4)*i)
	slow.native_exclusion=false
	slow.spatial_queries=false
	fast._exclude_particles()
	slow._exclude_particles()
	error=0
	for i in 50: error=maxf(error,Sim.Medium.offset(slow.particles[i].p,fast.particles[i].p).length())
	check.call(error<0.01,"Native membrane exclusion agrees with reference across the wrapping seam")
	# Compare the coarse cell index against brute-force bounding circles.
	fast.cell_index.rebuild(fast.cells)
	check.call(0 in fast.cell_index.at(Vector2(2,1280)),"Cell index includes periodic membrane overhang")

	# Sub-float32 organic packets are possible when a carbon stock is exhausted.
	# Weighted vector sums must normalize weights before float32 arithmetic.
	for sim in [slow,fast]:
		sim.particles.clear()
		sim.grid.rebuild(sim.particles)
		sim.spawn_particle(Sim.NUTRIENT,sim.player.position,Vector2(3,1),1e-60,0)
		sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(4,0),Vector2(1,3),2e-60,1)
		sim.particles[0].direction=Vector2.RIGHT
		sim.particles[1].direction=Vector2.LEFT
		sim._chemistry(0.0000001)
		check.call(sim.particles[0].v.is_finite() and sim.particles[0].v.distance_to(Vector2(5.0/3,7.0/3))<0.00001,"Microscopic packet aggregation has finite, mass-weighted velocity")

	var native_membrane = Sim.Cell.Membrane.new(60)
	var reference_membrane = Sim.Cell.Membrane.new(60)
	reference_membrane.native_constraints = false
	for i in 30:
		native_membrane.step(1.0/60,60,Vector2(2,3),i/60.0)
		reference_membrane.step(1.0/60,60,Vector2(2,3),i/60.0)
	error=0
	for i in native_membrane.COUNT: error=maxf(error,native_membrane.points[i].distance_to(reference_membrane.points[i]))
	check.call(error<0.01,"Native edge/pressure solves agree with the reference tension network")
