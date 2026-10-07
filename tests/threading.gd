extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Fixture = preload("res://tests/fluid_fixture.gd")
const Compare = preload("res://tests/packed_particles.gd")
const Pool = preload("res://tests/particle_pool.gd")
static func equal(a,b,check: Callable,label: String) -> void:
	check.call(Compare.same_packets(a.particle_snapshots(),b.particle_snapshots()),label+" exact packets")
	check.call(Pool.same_cells(a,b) and a.acidity.values==b.acidity.values and a.respiration_loss==b.respiration_loss and a.recycled==b.recycled,label+" exact cells and material")
	check.call([a.rng.state,a.background_rng.state,a.ecology_rng.state,a.chemistry_events]==[b.rng.state,b.background_rng.state,b.ecology_rng.state,b.chemistry_events],label+" exact random streams and reactions")
static func run(check: Callable) -> void:
	var probe = Sim.new(33)
	if probe.kernels == null: return
	check.call(not probe.kernels.thread_configure(0) and not probe.kernels.thread_configure(9),"Thread budget rejects out-of-range values")
	for distribution in ["uniform","clustered"]:
		for setting in [[2,true,false,true],[4,false,true,true],[8,true,true,true],[8,true,true,false]]:
			var fast = Sim.new(3301)
			var serial = Sim.new(3301)
			for sim in [fast,serial]:
				sim.view_half = Sim.VIEW/0.8/2
				check.call(Fixture.seed_packets(sim,8000,distribution),"Finite dense threading fixture")
				sim.enable_particle_pool()
			fast.kernels.thread_configure(setting[0],setting[1],setting[2],setting[3])
			serial.kernels.thread_configure(1)
			for tick in 64:
				if tick in [24,40]:
					for sim in [fast,serial]:
						sim.camera_follows_player = false
						sim.camera_position = Vector2(4080 if tick==24 else 400,1280)
				fast.step(1.0/60)
				serial.step(1.0/60)
				if tick%16==0 or tick==63: equal(fast,serial,check,"Thread width "+str(setting[0])+" "+distribution)
			var metrics: Dictionary = fast.kernels.thread_metrics()
			check.call((metrics.transport_jobs>0 if setting[1] else metrics.transport_jobs==0) and (metrics.contact_jobs>0 if setting[2] else metrics.contact_jobs==0),"Independent parallel stages actually execute")
	# More than 128 simultaneous contacts per particle must fall back completely.
	var fast = Sim.new(3302)
	var serial = Sim.new(3302)
	for sim in [fast,serial]:
		Fixture.seed_packets(sim,4200,"uniform")
		for p in sim.particles:
			p.p = sim.player.position+Vector2(200,0)
			p.previous = p.p
			p.direction = Vector2.RIGHT
		sim.grid.rebuild(sim.particles)
		sim.enable_particle_pool()
	serial.kernels.thread_configure(1)
	for sim in [fast,serial]: sim._chemistry(0.0000001)
	equal(fast,serial,check,"Overfull contact list")
	check.call(fast.kernels.thread_metrics().contact_fallbacks>0,"Overfull lists use ordered serial fallback")
	# Public diagnostic IDs may repeat; never dispatch two writes to one slot.
	var ids: Array[int] = []
	for i in fast.particle_count(): ids.append(i)
	ids.append(0)
	for sim in [fast,serial]:
		sim.kernels.transport([],ids,sim.fluid.velocity,sim.player.position,Vector2(3000,2000),0.01,99,sim.rng,-1.0,false)
	equal(fast,serial,check,"Repeated-ID transport fallback")
	# Coarse midpoint integration, missing clocks and COW position snapshots.
	for clock in [-1.0,0.0,3.0]:
		fast = Sim.new(3303)
		serial = Sim.new(3303)
		for sim in [fast,serial]:
			Fixture.seed_packets(sim,4200,"habitat")
			for i in range(0,sim.particles.size(),2): sim.particles[i].erase("transport_at")
			sim.enable_particle_pool()
		serial.kernels.thread_configure(1)
		ids.clear()
		for i in fast.particle_count(): ids.append(i)
		var held: PackedVector2Array = fast.kernels.packet_positions()
		var saved := held.duplicate()
		for sim in [fast,serial]:
			sim.kernels.transport([],ids,sim.fluid.velocity,Vector2.ZERO,Vector2.ZERO,0.5,103,sim.rng,clock,true)
		equal(fast,serial,check,"Coarse/missing-clock transport")
		check.call(held==saved,"Parallel transport detaches published position snapshots")
	# Dense seam contacts must retain periodic bin order without overflow fallback.
	fast = Sim.new(3304)
	serial = Sim.new(3304)
	for sim in [fast,serial]:
		Fixture.seed_packets(sim,4200,"uniform")
		sim.camera_follows_player=false
		sim.camera_position=Vector2(0,1280)
		sim.view_half=Vector2(3000,2000)
		for i in sim.particles.size():
			sim.particles[i].p=Vector2(4095 if i%2==0 else 1,fposmod(i*11,2560))
			sim.particles[i].direction=Vector2.RIGHT if i%2==0 else Vector2.LEFT
		sim.grid.rebuild(sim.particles)
		sim.enable_particle_pool()
	serial.kernels.thread_configure(1)
	for sim in [fast,serial]: sim._chemistry(0.0000001)
	equal(fast,serial,check,"Dense periodic contact screening")
	check.call(fast.kernels.thread_metrics().contact_jobs==1 and fast.kernels.thread_metrics().contact_fallbacks==0,"Dense seam uses the actual screened contact path")
