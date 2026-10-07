extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Compare = preload("res://tests/packed_particles.gd")
const Pool = preload("res://tests/particle_pool.gd")
const DT := 1.0/60

static func run(check: Callable) -> void:
	var probe = Sim.new(31)
	check.call(probe.particle_engine == "current" and probe.integration_half == Vector2.ZERO,"Gameplay particle engine remains unchanged until comparison gates pass")
	if probe.kernels == null:
		check.call(not probe.configure_particle_engine("liquidfun"),"Script fallback rejects native-only LiquidFun explicitly")
		return
	check.call(probe.kernels.neighbor_configure("legacy",true,false),"Existing current-engine cache remains supported")
	check.call(not probe.configure_particle_engine("uniform") and not probe.configure_particle_engine("liquidfun"),"Reject cached lists that lack uniform physical-radius coverage")
	check.call(probe.kernels.neighbor_configure("legacy",false,false),"Restore ordinary uncached grid after configuration probe")
	for args in [["wrong",4,1],["liquidfun",0,1],["liquidfun",9,1],["liquidfun",4,0],["liquidfun",4,5]]:
		check.call(not probe.configure_particle_engine(args[0],args[1],args[2]),"Reject unsupported engine/radius/iteration settings")
	for engine in ["uniform","liquidfun"]:
		var fixed = Sim.new(619)
		var zoomed = Sim.new(619)
		for sim in [fixed,zoomed]:
			sim.view_half = Sim.VIEW/0.8/2
			check.call(sim.configure_particle_engine(engine),"Configure explicit native "+engine+" experiment")
			check.call(sim.install("cilia",PI/2),"Zoom test uses paid feeding-current organ")
		check.call(not fixed.kernels.neighbor_configure("legacy",true,false),"Active physical-radius trial rejects incompatible cache explicitly")
		var material: float = fixed.kernels.pool_material()
		for tick in 240:
			# Editing magnification and free-camera display must not choose
			# ecology work, RNG, intake or pressure resolution.
			zoomed.view_half = Sim.VIEW/(12.0 if tick%30<15 else 0.8)/2
			zoomed.camera_follows_player = tick%45<20
			zoomed.camera_position = Vector2(20,20) if tick%45>=20 else fixed.player.position
			var display_half: Vector2 = zoomed.view_half
			fixed.step(DT)
			zoomed.step(DT)
			check.call(zoomed.view_half == display_half,"Simulation restores presentation zoom after every step")
			if tick%30 != 29: continue
			check.call(Compare.same_packets(fixed.particle_snapshots(),zoomed.particle_snapshots()),"Zoom/pan cannot change detailed packet states "+engine)
			check.call(Pool.same_cells(fixed,zoomed),"Zoom/pan cannot improve ATP, tissue, feeding or survival "+engine)
			check.call([fixed.rng.state,fixed.background_rng.state,fixed.ecology_rng.state,fixed.chemistry_events,fixed.acidity.values]==[zoomed.rng.state,zoomed.background_rng.state,zoomed.ecology_rng.state,zoomed.chemistry_events,zoomed.acidity.values],"Zoom cannot change random streams or reaction outcomes "+engine)
			check.call(fixed.kernels.pool_material() == zoomed.kernels.pool_material(),"Zoom conserves exactly the same remaining material")
			for packet in fixed.particle_snapshots():
				check.call(packet.p.is_finite() and packet.v.is_finite() and is_finite(packet.amount) and packet.amount>=0,"Native particle engine remains finite with chemistry and pumping")
		check.call(fixed.emitted_particles > 0 and fixed.kernels.pool_metrics().mirror_writes == 0,"Engine supports births with authoritative native ownership")
		if engine == "liquidfun":
			check.call(fixed.kernels.particle_engine_metrics().calls == 240,"LiquidFun executes during real ecology ticks")
		check.call(fixed.kernels.pool_material() <= material+100,"Solver supplies no particle food or capacity grants")
		check.call(fixed.configure_particle_engine("current") and fixed.integration_half == Vector2.ZERO,"Experimental engine can return to current kernel without rebuilding habitat")
	# Pure pair/contact fixture, including torus seams and contact-free signals.
	for wrapped in [false,true]:
		var sim = Sim.new(31)
		sim.cells = [sim.player]
		sim.particles.clear()
		sim.pheromones.clear()
		sim.player.position = Vector2(4095,1000) if wrapped else Vector2(100,1000)
		sim.fluid.velocity.fill(Vector2.ZERO)
		for x in ([4095.0,1.0] if wrapped else [99.0,101.0]):
			sim.spawn_particle(sim.WASTE,Vector2(x,1000),Vector2.ZERO,0.3,7)
		sim.spawn_particle(sim.PHEROMONE,sim.player.position,Vector2.ZERO,1,9)
		check.call(sim.configure_particle_engine("liquidfun"),"Initialize periodic contact fixture")
		var ids: Array[int] = [0,1,2]
		sim.kernels.packet_begin([])
		sim.kernels.transport([],ids,sim.fluid.velocity,sim.player.position,Sim.WORLD/2,DT,1,sim.rng,DT,false)
		var packets := sim.particle_snapshots()
		check.call(sim.kernels.particle_engine_metrics().contacts > 0,"LiquidFun detects round point contacts across ordinary and wrapped seams")
		check.call(sim.kernels.pool_material() == 0.6,"Physics contacts and periodic images conserve chemical material")
		check.call(sim.kernels.particle_engine_metrics().solver_points == 2,"Pheromone tracers never join collision solver")
		check.call(packets[2].v == Vector2.ZERO and packets[2].owner == 9,"Pheromone metadata and contact-free flow survive native engine")
		var handle: int = packets[0]._handle
		sim.kernels.pool_patch(1,{"alive":false})
		sim.kernels.pool_compact(0)
		check.call(sim.kernels.pool_resolve(handle)._index==0,"Chemistry compaction retains game handles independently of solver slots")

	# Large hidden/catch-up steps keep circular separation; LiquidFun is only
	# stepped for fine foreground transport and must not remove other contacts.
	var hidden_velocities: Array = []
	for engine in ["uniform","liquidfun"]:
		var sim = Sim.new(31)
		sim.particles.clear()
		sim.pheromones.clear()
		for x in [2000.0,2002.0]:
			sim.spawn_particle(Sim.WASTE,Vector2(x,1200),Vector2.ZERO,0.3,7)
			sim.particles[-1].angle = 0.0
			sim.particles[-1].direction = Vector2.RIGHT
		check.call(sim.configure_particle_engine(engine),"Initialize coarse round-contact fixture")
		sim.kernels.packet_begin([])
		var ids: Array[int] = [0,1]
		sim.kernels.chemistry([],ids,sim.acidity.values,Vector2.ZERO,Vector2(100,100),0.5,1,sim.background_rng,0.5,true,true,true,true,true)
		var packets := sim.particle_snapshots()
		hidden_velocities.append([packets[0].v,packets[1].v])
		check.call(packets[0].v.x<0 and packets[1].v.x>0,"Hidden chemistry retains uniform circular separation in "+engine)
	check.call(hidden_velocities[0]==hidden_velocities[1],"LiquidFun coarse fallback matches the uniform-radius contact baseline")

	# Dense pressure acts on round proxies, independent of display art or chemical
	# amount. Translation through a seam should preserve the same local solution.
	var ordinary := pressure(probe,Vector2(100,1000))
	var wrapped := pressure(probe,Vector2(4095,1000))
	check.call(ordinary.metrics.contacts>=6 and wrapped.metrics.contacts>=6,"Dense cloud supplies fluid pressure contacts")
	var momentum := Vector2.ZERO
	for velocity in ordinary.velocities: momentum += velocity
	check.call(momentum.length()<0.01,"Closed pressure fixture conserves linear momentum")
	check.call(ordinary.velocities[0].x<0 and ordinary.velocities[3].x>0,"Compressed water expands instead of clumping")
	for i in ordinary.velocities.size():
		check.call(ordinary.velocities[i].distance_to(wrapped.velocities[i])<0.05,"Periodic images preserve pressure under seam translation")

static func pressure(sim,center: Vector2) -> Dictionary:
	sim.kernels.particle_engine_configure("liquidfun",4,1)
	var p := PackedVector2Array()
	for at in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]: p.append(sim.Medium.wrap_position(center+at))
	return sim.kernels.particle_solver_probe(p,PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]),DT)
