extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const FIELDS := ["kind","p","previous","v","amount","age","alive","owner","angle","previous_angle","spin","direction","capacity","chemical_at","transport_at","transport_jump","updated","reacted","report","expires_at","product"]
static func same_packets(a: Array, b: Array) -> bool:
	if a.size()!=b.size(): return false
	for i in a.size():
		for key in FIELDS:
			if a[i].has(key)!=b[i].has(key): return false
			if a[i].get(key)!=b[i].get(key): return false
	return true
static func run(check: Callable) -> void:
	var fast = Sim.new(846)
	if fast.kernels == null:
		check.call(not fast.native_particle_pipeline and not fast.native_particle_render_cache,"Script fallback has no packed/native render cache")
		return
	var slow = Sim.new(846)
	slow.native_particle_pipeline = false
	mutation_checks(check)
	# Every oriented pair/order and acid regime reaches the packed chemistry path.
	for acid in [0.0,0.4,0.95]:
		for aligned in [true,false]:
			for a in Sim.SPECIES_COUNT:
				for b in Sim.SPECIES_COUNT:
					fast.particles.clear()
					fast.grid.rebuild(fast.particles)
					fast.spawn_particle(a,Vector2(4094,900),Vector2(2,0),0.3,0)
					fast.spawn_particle(b,Vector2(2,900),Vector2(-3,0),0.4,1)
					fast.particles[0].direction = Vector2.RIGHT if aligned else Vector2.LEFT
					fast.particles[1].direction = Vector2.LEFT
					slow.particles = fast.particles.duplicate(true)
					for sim in [fast,slow]:
						sim.grid.rebuild(sim.particles)
						sim.acidity.values.fill(acid)
						sim.rng.seed = 781
						sim.revision += 1
					var held: Dictionary = fast.particles[0]
					fast.kernels.packet_begin(fast.particles)
					fast._chemistry(0.0000001)
					fast.kernels.packet_end()
					slow._chemistry(0.0000001)
					check.call(same_packets(fast.particles,slow.particles) and fast.rng.state==slow.rng.state and fast.chemistry_events==slow.chemistry_events and fast.acidity.values==slow.acidity.values and is_same(held,fast.particles[0]),"Packed chemistry preserves pair order, fields, identity, clocks and RNG %d/%d" % [a,b])
	# Exercise real food/feeding, emissions, exclusion, compaction and camera tiers.
	fast = Sim.new(25171)
	slow = Sim.new(25171)
	slow.native_particle_pipeline = false
	for tick in 180:
		if tick in [40,80,130]:
			for sim in [fast,slow]:
				sim.camera_follows_player = false
				sim.camera_position = Vector2(4080 if tick==80 else 600,1280)
		fast.step(1.0/60)
		slow.step(1.0/60)
		if tick%20==0:
			check.call(render_matches(fast),"Hot whole-tick render handoff agrees after biology/contacts/compaction")
			check.call(same_packets(fast.particles,slow.particles) and fast.rng.state==slow.rng.state and fast.background_rng.state==slow.background_rng.state and fast.ecology_rng.state==slow.ecology_rng.state and fast.player.biomass==slow.player.biomass and fast.player.energy==slow.player.energy,"Packed whole tick preserves finite ecology and transition draws")
	# Cached drawing changes interpolation without changing current packet state.
	var ids := fast.visible_particle_ids(30)
	var caps := PackedInt32Array()
	caps.resize(Sim.SPECIES_COUNT)
	caps.fill(1)
	for alpha in [0.0,0.35,1.0,0.1]:
		var cached: Array = fast.kernels.render_particles(fast.particles,ids,fast.cells,fast.player.position,fast.view_half,alpha,fast.revision,caps,true)
		var direct: Array = fast.kernels.render_particles(fast.particles,ids,fast.cells,fast.player.position,fast.view_half,alpha,fast.revision,caps,false)
		check.call(cached==direct,"Packed render cache preserves interpolation, glyphs and membrane exclusion")
	var replaced: Array = fast.particles.duplicate(true)
	if not replaced.is_empty(): replaced[0].amount *= 0.5
	fast.particles = replaced
	var cached: Array = fast.kernels.render_particles(fast.particles,ids,fast.cells,fast.player.position,fast.view_half,1.0,fast.revision,caps,true)
	var direct: Array = fast.kernels.render_particles(fast.particles,ids,fast.cells,fast.player.position,fast.view_half,1.0,fast.revision,caps,false)
	check.call(cached==direct,"Render cache rejects replacement arrays even at the same count/revision")
	if not fast.particles.is_empty(): fast.particles[0].p += Vector2(50,0)
	fast.kernels.invalidate_particle_render()
	cached = fast.kernels.render_particles(fast.particles,ids,fast.cells,fast.player.position,fast.view_half,1.0,fast.revision,caps,true)
	direct = fast.kernels.render_particles(fast.particles,ids,fast.cells,fast.player.position,fast.view_half,1.0,fast.revision,caps,false)
	check.call(cached==direct,"Explicit external packet edits invalidate render snapshots")

static func render_matches(sim) -> bool:
	var ids: Array[int] = []
	for i in sim.particles.size(): ids.append(i)
	var caps := PackedInt32Array()
	caps.resize(Sim.SPECIES_COUNT)
	caps.fill(1)
	for alpha in [0.0,0.47,1.0]:
		var cached: Array = sim.kernels.render_particles(sim.particles,ids,sim.cells,sim.player.position,Vector2(3000,2000),alpha,sim.revision,caps,true)
		var direct: Array = sim.kernels.render_particles(sim.particles,ids,sim.cells,sim.player.position,Vector2(3000,2000),alpha,sim.revision,caps,false)
		if cached != direct: return false
	return true

static func prime_render(sim) -> void:
	var ids: Array[int] = []
	for i in sim.particles.size(): ids.append(i)
	sim.kernels.packet_begin(sim.particles)
	sim.kernels.transport(sim.particles,ids,sim.fluid.velocity,sim.player.position,Vector2(3000,2000),0.0000001,sim.revision,sim.rng)
	sim.kernels.packet_end()
	sim.kernels.particle_render_ready(sim.particles,sim.revision)

static func mutation_checks(check: Callable) -> void:
	# Change live numeric snapshots through the same post-chemistry callers as play.
	for native in [false,true]:
		for kind in [Sim.NUTRIENT,Sim.OXYGEN,Sim.TOXIN,Sim.DECOY,Sim.WASTE]:
			var sim = Sim.new(619)
			sim.cells = [sim.player]
			sim.particles.clear()
			sim.grid.rebuild(sim.particles)
			sim.native_feeding = native
			sim.native_exclusion = native
			var cell = sim.player
			var organ: Dictionary = cell.organs[0]
			var normal: Vector2 = cell.organ_normal(organ).rotated(cell.angle)
			var at: Vector2 = cell.organ_position(organ)+normal*3 if kind==Sim.DECOY else cell.pore_center(organ) if kind==Sim.NUTRIENT else cell.position
			sim.spawn_particle(kind,at,Vector2.ZERO,0.3,900)
			prime_render(sim)
			var packet: Dictionary = sim.particles[0]
			packet.direction = -normal
			if kind in [Sim.NUTRIENT,Sim.OXYGEN]:
				cell.substrate = 0
				cell.oxygen = 0
				sim._feed(cell)
			elif kind==Sim.DECOY: sim._receptor_contacts()
			elif kind==Sim.TOXIN: sim._toxin_contacts()
			else:
				for i in cell.membrane.COUNT:
					var angle: float = TAU*i/cell.membrane.COUNT
					cell.membrane.points[i] = Vector2.from_angle(angle)*cell.radius*(1+0.16*sin(angle*3))
				cell.membrane.maximum_radius = cell.radius*1.16
				cell.membrane.invalidate()
				sim._exclude_particles()
			check.call((not packet.alive if kind!=Sim.WASTE else packet.p!=at) and render_matches(sim),"Render snapshots refresh after real feeding, toxin, decoy and deformed exclusion %d" % kind)
			sim.spawn_particle(Sim.OXYGEN,cell.position+Vector2(160,0),Vector2.ZERO,0.2,900)
			sim.kernels.particle_render_ready(sim.particles,sim.revision)
			check.call(render_matches(sim),"Render snapshots include appended packets without a new tick")
			var held: Dictionary = sim.particles[-1]
			sim._compact_particles()
			sim.kernels.particle_render_ready(sim.particles,sim.revision)
			check.call(is_same(held,sim.particles[-1]) and render_matches(sim),"Compaction refreshes render indices while preserving packet identity")
	# Hidden intake and contact must also retire cached visible poses.
	for native in [false,true]:
		for exposure in [false,true]:
			var sim = Sim.new(819)
			sim.native_feeding = native
			sim.cells = [sim.player]
			sim.particles.clear()
			sim.grid.rebuild(sim.particles)
			sim.spawn_particle(Sim.TOXIN if exposure else Sim.NUTRIENT,sim.player.position+Vector2(10,0),Vector2.ZERO,0.3,900)
			prime_render(sim)
			sim.camera_follows_player = false
			sim.camera_position = Vector2.ZERO
			sim.view_half = Vector2(10,10)
			sim.player.activity = 0
			sim.player.substrate = 0
			if exposure: sim.offscreen_ecology._exposure(sim,sim.player,100)
			else: sim.offscreen_ecology._feed(sim,sim.player,100)
			check.call(not sim.particles[0].alive and render_matches(sim),"Hidden feeding/exposure invalidates the same render snapshot")
	# Sparse diagnostic packets keep legacy missing-clock defaults.
	for clock in [-1.0,0.0,3.0]:
		for background in [false,true]:
			var fast = Sim.new(902)
			var slow = Sim.new(902)
			for sim in [fast,slow]:
				sim.particles.clear()
				sim.grid.rebuild(sim.particles)
				sim.spawn_particle(Sim.WASTE,Vector2(500,500),Vector2(1,2),0.2,900)
				sim.particles[0].erase("transport_at")
				sim.particles[0].erase("chemical_at")
				sim.rng.seed = 118
			var camera := Vector2.ZERO if background else Vector2(500,500)
			var ids: Array[int] = [0]
			fast.kernels.packet_begin(fast.particles)
			for sim in [fast,slow]:
				sim.kernels.transport(sim.particles,ids,sim.fluid.velocity,camera,Vector2(10,10),0.01,1,sim.rng,clock,background)
				sim.kernels.chemistry(sim.particles,ids,sim.acidity.values,camera,Vector2(10,10),0.01,1,sim.rng,clock,background)
			fast.kernels.packet_end()
			check.call(same_packets(fast.particles,slow.particles) and fast.rng.state==slow.rng.state,"Sparse packet timestamp defaults agree in both scoped tiers")
