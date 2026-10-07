extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Compare = preload("res://tests/packed_particles.gd")
const DT := 1.0/60

static func run(check: Callable) -> void:
	var initial = Sim.new(27)
	if initial.kernels == null:
		check.call(not initial.enable_particle_pool(),"Script backend explicitly rejects native ownership")
		return
	# Full ecology covers secretion, expiry, chemistry, feeding, coarse catch-up,
	# deformation, succession, compaction and all three independent RNG streams.
	for seed_value in [25171,846,619]:
		var pooled = Sim.new(seed_value)
		var mirrored = Sim.new(seed_value)
		pooled.view_half = Sim.VIEW/0.8/2
		mirrored.view_half = pooled.view_half
		check.call(pooled.enable_particle_pool() and pooled.particles.is_empty() and pooled.pheromones.is_empty(),"Pool imports once and leaves no public pose mirrors")
		var imported: int = pooled.kernels.pool_metrics().imports
		var initial_emissions: int = pooled.emitted_particles
		var exported: int = pooled.kernels.pool_metrics().exports
		for tick in 240:
			if tick in [40,80,130,190]:
				for sim in [pooled,mirrored]:
					sim.camera_follows_player = false
					sim.camera_position = Vector2(4080 if tick==80 else 600 if tick==130 else 2048,1280)
			pooled.step(DT)
			mirrored.step(DT)
			if tick%20!=0: continue
			var metrics: Dictionary = pooled.kernels.pool_metrics()
			check.call(metrics.exports==exported and metrics.mirror_writes==0 and pooled.particles.is_empty(),"Ordinary ticks never publish/import a per-particle pose mirror")
			var packets := pooled.particle_snapshots()
			exported = pooled.kernels.pool_metrics().exports
			check.call(Compare.same_packets(packets,mirrored.particles),"Pool retains exact packet fields/order through camera and biology transitions %d/%d" % [seed_value,tick])
			check.call([pooled.rng.state,pooled.background_rng.state,pooled.ecology_rng.state]==[mirrored.rng.state,mirrored.background_rng.state,mirrored.ecology_rng.state] and pooled.chemistry_events==mirrored.chemistry_events and pooled.acidity.values==mirrored.acidity.values,"Pool preserves chemical outcomes and all random streams")
			check.call(same_cells(pooled,mirrored) and pooled.respiration_loss==mirrored.respiration_loss and pooled.recycled==mirrored.recycled,"Batched sensing/feeding/contact preserves shared physiology")
			var ids: Array[int] = []
			for i in packets.size(): ids.append(i)
			var caps := PackedInt32Array()
			caps.resize(Sim.SPECIES_COUNT)
			caps.fill(1)
			for alpha in [0.0,0.47,1.0]:
				var actual: Array = pooled.kernels.render_particles([],ids,pooled.cells,pooled.player.position,pooled.view_half,alpha,pooled.revision,caps,true)
				var expected: Array = mirrored.kernels.render_particles(mirrored.particles,ids,mirrored.cells,mirrored.player.position,mirrored.view_half,alpha,mirrored.revision,caps,false)
				check.call(actual==expected,"Pool rendering reads native poses directly at every interpolation fraction")
		check.call(pooled.kernels.pool_metrics().imports==imported+pooled.emitted_particles-initial_emissions,"Pool imports are limited to initialization and newly emitted particles")
		pooled.disable_particle_pool()
		check.call(not pooled.particle_pool and Compare.same_packets(pooled.particles,mirrored.particles),"Explicit fallback exports once with current material/clocks")
		pooled.step(DT)
		mirrored.step(DT)
		check.call(Compare.same_packets(pooled.particles,mirrored.particles) and same_cells(pooled,mirrored),"Dictionary execution resumes without a discontinuity")
	chemistry_pairs(check)
	mutations(check)
	handles(check)
	optional_clocks(check)

static func same_cells(a,b) -> bool:
	if a.cells.size()!=b.cells.size(): return false
	for i in a.cells.size():
		for key in ["position","velocity","angle","angular_velocity","biomass","energy","health","substrate","oxygen","carbon","waste","eaten","foreign_intake","target_mode","target_position","target_id","target_lineage","target_organ_id","target_memory","target_score","signals","dead"]:
			if a.cells[i].get(key)!=b.cells[i].get(key): return false
		for j in a.cells[i].organs.size():
			if a.cells[i].organs[j]!=b.cells[i].organs[j]: return false
	return true

static func chemistry_pairs(check: Callable) -> void:
	var pooled = Sim.new(27)
	var mirrored = Sim.new(27)
	for acid in [0.0,0.4,0.95]:
		for aligned in [true,false]:
			for a in Sim.SPECIES_COUNT:
				for b in Sim.SPECIES_COUNT:
					if pooled.particle_pool: pooled.disable_particle_pool()
					pooled.particles.clear()
					pooled.grid.rebuild(pooled.particles)
					pooled.spawn_particle(a,Vector2(4094,900),Vector2(2,0),0.3,0)
					pooled.spawn_particle(b,Vector2(2,900),Vector2(-3,0),0.4,1)
					pooled.particles[0].direction = Vector2.RIGHT if aligned else Vector2.LEFT
					pooled.particles[1].direction = Vector2.LEFT
					mirrored.particles = pooled.particles.duplicate(true)
					for sim in [pooled,mirrored]:
						sim.camera_follows_player = false
						sim.camera_position = Vector2(0,900)
						sim.acidity.values.fill(acid)
						sim.rng.seed = 781
						sim.revision += 1
						sim.grid.rebuild(sim.particles)
					pooled.enable_particle_pool()
					pooled._chemistry(0.0000001)
					mirrored._chemistry(0.0000001)
					check.call(Compare.same_packets(pooled.particle_snapshots(),mirrored.particles) and pooled.rng.state==mirrored.rng.state and pooled.chemistry_events==mirrored.chemistry_events and pooled.acidity.values==mirrored.acidity.values,"Resident pool oriented species/order/acid parity %d/%d" % [a,b])

static func isolated():
	var sim = Sim.new(619)
	sim.cells = [sim.player]
	sim.pending_replacements.clear()
	sim.particles.clear()
	sim.pheromones.clear()
	sim.grid.rebuild(sim.particles)
	return sim

static func mutations(check: Callable) -> void:
	for kind in [Sim.NUTRIENT,Sim.OXYGEN,Sim.CARBON,Sim.TOXIN,Sim.DECOY,Sim.WASTE]:
		for hidden in [false,true]:
			var pooled = isolated()
			var mirrored = isolated()
			for sim in [pooled,mirrored]:
				var cell = sim.player
				cell.substrate = 0
				cell.oxygen = 0
				cell.carbon = 0
				cell.waste = 20.1
				cell.add_organ("photosynthesis",PI/2,"light",false)
				var organ: Dictionary = cell.organs[0]
				var normal: Vector2 = cell.organ_normal(organ).rotated(cell.angle)
				var at: Vector2 = cell.organ_position(organ)+normal*3 if kind==Sim.DECOY else cell.pore_center(organ) if kind==Sim.NUTRIENT else cell.position
				sim.spawn_particle(kind,at,Vector2.ZERO,0.3,900)
				sim.particles[0].direction = -normal
				if kind==Sim.TOXIN:
					sim.spawn_particle(kind,at,Vector2.ZERO,0.13,sim.player.id if hidden else 900)
					sim.spawn_particle(kind,at,Vector2.ZERO,0.17,900)
				if hidden:
					sim.camera_follows_player = false
					sim.camera_position = Vector2.ZERO
					sim.view_half = Vector2(10,10)
					cell.activity = 0
			pooled.enable_particle_pool()
			for sim in [pooled,mirrored]:
				if kind in [Sim.NUTRIENT,Sim.OXYGEN,Sim.CARBON]:
					if hidden: sim.offscreen_ecology._feed(sim,sim.player,100)
					else: sim._feed(sim.player)
				elif kind in [Sim.DECOY,Sim.TOXIN]:
					if hidden: sim.offscreen_ecology._exposure(sim,sim.player,100)
					elif kind==Sim.DECOY: sim._receptor_contacts()
					else: sim._toxin_contacts()
				elif not hidden: sim._exclude_particles()
			check.call(Compare.same_packets(pooled.particle_snapshots(),mirrored.particles) and same_cells(pooled,mirrored) and pooled.rng.state==mirrored.rng.state and pooled.evolution.exposures==mirrored.evolution.exposures,"Pool finite intake, toxin, decoy and exclusion parity %d hidden=%s" % [kind,hidden])

static func handles(check: Callable) -> void:
	var sim = isolated()
	for i in 3: sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(150+i*30,0),Vector2.ZERO,0.3,900)
	sim.particles[0].alive = false
	sim.enable_particle_pool()
	sim.grid.kind_queries = false
	check.call(sim.grid.query_kind(sim.particles,sim.player.position,500,Sim.OXYGEN)==sim.grid.query(sim.player.position,500),"Disabled species-query ablation retains raw ordered candidates including dead slots")
	sim.grid.kind_queries = true
	var held: Dictionary = sim.particle_snapshot(2)
	var retired: Dictionary = sim.particle_snapshot(0)
	sim._compact_particles()
	sim.grid.rebuild(sim.particles)
	check.call(sim.kernels.pool_resolve(retired._handle).is_empty(),"Compaction retires dead handles")
	check.call(sim.kernels.pool_resolve(held._handle).p==held.p,"Live handles survive slot compaction")
	sim.spawn_particle(Sim.OXYGEN,sim.player.position+Vector2(240,0),Vector2.ZERO,0.3,900)
	check.call(sim.particle_snapshot(2)._handle!=retired._handle,"New slots never reuse an old particle identity")
	held.p = Vector2.ZERO
	held.amount = 500
	check.call(sim.kernels.pool_resolve(held._handle).p!=held.p and sim.kernels.pool_resolve(held._handle).amount==0.3,"Inspection snapshots cannot mutate native state")
	var old_handle: int = held._handle
	sim.disable_particle_pool()
	sim.enable_particle_pool()
	check.call(sim.kernels.pool_resolve(old_handle).is_empty(),"Re-import invalidates old handles rather than attaching a lens to another packet")

static func optional_clocks(check: Callable) -> void:
	for clock in [-1.0,0.0,3.0]:
		for background in [false,true]:
			var pooled = isolated()
			var mirrored = isolated()
			for sim in [pooled,mirrored]:
				sim.spawn_particle(Sim.WASTE,Vector2(500,500),Vector2(1,2),0.2,900)
				sim.particles[0].erase("transport_at")
				sim.particles[0].erase("chemical_at")
				sim.rng.seed = 118
			pooled.enable_particle_pool()
			var camera := Vector2.ZERO if background else Vector2(500,500)
			var ids: Array[int] = [0]
			for sim in [pooled,mirrored]:
				sim.kernels.transport(sim.particles,ids,sim.fluid.velocity,camera,Vector2(10,10),0.01,1,sim.rng,clock,background)
				sim.kernels.chemistry(sim.particles,ids,sim.acidity.values,camera,Vector2(10,10),0.01,1,sim.rng,clock,background)
			check.call(Compare.same_packets(pooled.particle_snapshots(),mirrored.particles) and pooled.rng.state==mirrored.rng.state,"Resident pool preserves absent-clock defaults in both transport tiers")
