extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const DT := 1.0/60
static func fixture(seed_value: int = 931):
	var sim = Sim.new(seed_value)
	sim.evolution.enabled = false
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.pheromones.clear()
	sim.grid.rebuild(sim.particles)
	sim.habitat_geometry.enabled = false
	sim.camera_follows_player = false
	sim.camera_position = Vector2.ZERO
	sim.view_half = Vector2(100,100)
	sim.fluid.velocity.fill(Vector2(24,-9))
	return sim

static func run(check: Callable) -> void:
	_schedule(check)
	_diffusion(check)
	_integrator(check)
	_stems(check)
	_field(check)
	_fast_promotion(check)

static func _schedule(check: Callable) -> void:
	var fast = fixture()
	var slow = fixture()
	slow.native_particles = false
	slow.grid.native_enabled = false
	for world in [fast,slow]:
		for i in 90:
			world.spawn_particle(Sim.WASTE,Vector2(2000+i,1200),Vector2(20,7),0.4,77)
		world.spawn_particle(Sim.PHEROMONE,Vector2(2000,1200))
	for frame in 90:
		for world in [fast,slow]:
			world.revision += 1
			if frame == 19:
				for i in range(0,world.particles.size(),3): world.particles[i].alive = false
				world._compact_particles()
				world.grid.rebuild(world.particles)
				for i in 17: world.spawn_particle(Sim.CARBON,Vector2(2100+i,1200),Vector2.ZERO,0.3,88)
			world._move_particles(DT)
	for i in fast.particles.size():
		var a: Dictionary = fast.particles[i]
		var b: Dictionary = slow.particles[i]
		check.call(Sim.Medium.offset(a.p,b.p).length() < 0.004 and absf(a.age-b.age) < 0.000001,"Coarse transport matches native/reference through births, deletion and compaction")
		check.call(fast.transport_clock-a.transport_at < 0.54,"Every surviving packet receives bounded-latency offscreen service")
		check.call(a.owner in [77,88,-1] and a.amount in [0.4,0.3,1.0],"Transport preserves material and source metadata")
	var packet: Dictionary = fast.particles[0]
	var prior_age: float = packet.age
	fast.camera_position = packet.p
	fast.revision += 1
	fast._move_particles(DT)
	check.call(absf(packet.age-fast.transport_clock) < 0.000001 and packet.age > prior_age,"Camera promotion catches up elapsed time exactly once")
	fast.cells.clear()
	fast.transport_clock += 0.4
	fast.step(DT)
	check.call(packet.previous == packet.p and not packet.get("transport_jump",false),"A camera-promoted packet leaves no long interpolation segment")
	var prior: float = packet.age
	fast._move_particles(DT)
	check.call(absf(packet.age-prior-DT) < 0.000001,"A promoted particle returns to one foreground step per tick")
	fast.spawn_particle(Sim.WASTE,Vector2(2300,1300))
	check.call(fast.particles[-1].transport_at == fast.transport_clock,"New packets start with no pre-birth transport debt")
	check.call(fast.grid.query(packet.p,8).has(0),"Background moves and compaction preserve query membership")
	# Signals still expire in global real time even while transport is coarse.
	fast.spawn_particle(Sim.PHEROMONE,Vector2(2300,1300))
	var tracer: Dictionary = fast.particles[-1]
	fast.time = tracer.expires_at+0.01
	fast._expire_pheromones()
	check.call(not tracer.alive,"Offscreen pheromone expiry is not prolonged by coarse transport")

static func _diffusion(check: Callable) -> void:
	var world = fixture(417)
	for i in 2400: world.spawn_particle(Sim.WASTE,Vector2(2000,1200),Vector2.ZERO,0.3)
	for i in 120:
		world.revision += 1
		world._move_particles(DT)
	var sum := Vector2.ZERO
	var square := Vector2.ZERO
	var expected := 0.0
	for p in world.particles:
		var residual: Vector2 = Sim.Medium.offset(Vector2(2000,1200),p.p)-Vector2(24,-9)*p.age
		sum += residual
		square += residual*residual
		expected += 12.0*p.age
	var ratio := square/expected
	check.call(sum.length()/world.particles.size() < 0.35,"Offscreen plume follows the current without biased diffusion")
	check.call(ratio.x > 0.90 and ratio.x < 1.10 and ratio.y > 0.90 and ratio.y < 1.10,"Large steps preserve Brownian variance 2 D elapsed, not dt-squared")
	check.call(world.particles.size() == 2400,"Background transport cannot fabricate or destroy material")
	print("OFFSCREEN_DIFFUSION ",JSON.stringify({"variance_ratio":str(ratio),"mean_error":sum.length()/2400.0}))

static func _integrator(check: Callable) -> void:
	var fluid = Sim.Medium.new()
	fluid.velocity.fill(Vector2(24,-9))
	var origin := Vector2(4090,3)
	var launch := Vector2(80,12)
	var expected := Sim.Medium.wrap_position(origin+Vector2(24,-9)*0.5+launch*((1.0-exp(-0.4))/0.8))
	var actual: Vector2 = Sim.Transport.advect(origin,launch,fluid,0.5)
	check.call(Sim.Medium.offset(expected,actual).length() < 0.001,"Coarse transport integrates launch drag and wraps the torus correctly")
	fluid = Sim.Medium.new()
	var coarse := Vector2(1800,1200)
	var fine := coarse
	for i in 20: coarse = Sim.Transport.advect(coarse,Vector2.ZERO,fluid,0.5)
	for i in 2500: fine = Sim.Transport.advect(fine,Vector2.ZERO,fluid,0.004)
	check.call(Sim.Medium.offset(fine,coarse).length() < 0.15,"Midpoint advection follows a curved eddy close to fine transport")
	print("OFFSCREEN_EDDY_ERROR ",Sim.Medium.offset(fine,coarse).length())

static func _stems(check: Callable) -> void:
	for native in [false,true]:
		var world = fixture()
		world.native_particles = native and world.kernels != null
		world.fluid.velocity.fill(Vector2(0,400))
		var habitat = world.habitat_geometry
		habitat.enabled = true
		habitat.forms = [{"branches":[{"a":Vector2(-80,0),"b":Vector2(80,0),"r":5.0,"depth":2}]}]
		habitat.plants = [{"p":Vector2(2048,1280),"radius":100.0,"form":0,"angle":0.0}]
		habitat.rebuild()
		world.spawn_particle(Sim.WASTE,Vector2(2048,1180),Vector2.ZERO,0.3)
		world.spawn_particle(Sim.PHEROMONE,Vector2(2048,1180))
		world.revision += 1
		world._move_particles(0.5)
		check.call(world.particles[0].p.y > 1360 and world.particles[0].amount == 0.3,"Coarse material permeates offscreen stems while preserving its amount")
		check.call(world.particles[1].p.y > 1320 and world.particles[1].v == Vector2.ZERO,"Coarse pheromone flow still passes through solids without launch momentum")
		check.call(world.particles[0].previous == world.particles[0].p,"Coarse background movement cannot produce interpolation streaks")

static func _field(check: Callable) -> void:
	var fast = fixture()
	var slow = fixture()
	slow.native_fluid = false
	for world in [fast,slow]:
		world.fluid.set_camera(Vector2.ZERO,world.view_half)
		world.fluid.velocity.fill(Vector2(100,0))
		world.fluid.tide.fill(Vector2.ZERO)
		world._step_background_fluid(0.5)
	var far := Sim.Medium.index(30,20)
	check.call(absf(fast.fluid.velocity[far].x-100*exp(-0.12*0.5)) < 0.001,"Offscreen fluid relaxes old wakes in elapsed real time")
	var error := 0.0
	for i in fast.fluid.velocity.size():
		error = maxf(error,fast.fluid.velocity[i].distance_to(slow.fluid.velocity[i]))
	check.call(error < 0.001,"Native/reference background fluid refresh agrees")
	check.call(fast.fluid.activity[far] == 0 and slow.fluid.activity[far] == 0,"Coarse fluid work restores the foreground interaction mask")


static func _fast_promotion(check: Callable) -> void:
	for native in [false,true]:
		var world = fixture()
		world.cells.clear()
		world.native_particles = native and world.kernels != null
		world.fluid.velocity.fill(Vector2(600,0))
		world.fluid.tide.fill(Vector2(600,0))
		var habitat = world.habitat_geometry
		habitat.enabled = true
		habitat.forms = [{"branches":[{"a":Vector2(0,-80),"b":Vector2(0,80),"r":5.0,"depth":2}]}]
		habitat.plants = [{"p":Vector2(350,100),"radius":100.0,"form":0,"angle":0.0}]
		habitat.rebuild()
		world.spawn_particle(Sim.WASTE,Vector2(200,100),Vector2.ZERO,0.3)
		world.transport_clock += 0.5
		world.step(DT)
		check.call(world.particles[0].p.x > 490,"Fast camera catch-up carries dissolved material through plant stems")
		check.call(world.particles[0].p == world.particles[0].previous,"Catch-up beyond the halo suppresses its interpolation trail")
