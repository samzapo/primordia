extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Grid = preload("res://scripts/spatial_grid.gd")
static func run(check: Callable) -> void:
	var fast = Sim.new(425)
	if fast.kernels == null: return
	_grid(check,fast)
	_feeding(check)
	_hidden_chemistry(check)
	_hidden_feeding(check)
	_contacts(check)
	_compression(check)
	_halo_timestamp(check)
	_bounds(check)
	_bookkeeping(check)
	_cell_bounds(check)
	_dirty_chemistry(check)
	_mesh(check)
	_compaction(check)

static func _grid(check: Callable, sim) -> void:
	var full = Grid.new()
	full.rebuild(sim.particles)
	var ids: Array[int] = []
	for i in range(0,sim.particles.size(),7):
		ids.append(i)
		sim.particles[i].p = Sim.Medium.wrap_position(sim.particles[i].p+Vector2(127,-193))
		# Solid projection overwrites previous; updates must use stored buckets.
		sim.particles[i].previous = sim.particles[i].p
	sim.grid.update(sim.particles,ids)
	full.rebuild(sim.particles)
	for at in [Vector2.ZERO,Vector2(4095,2559),sim.player.position,sim.cells[2].position]:
		for radius in [32,150,800]:
			check.call(sim.grid.query(at,radius) == full.query(at,radius),"Incremental grid matches rebuild identity order across seams and projected history")
	for kind in Sim.SPECIES_COUNT:
		var expected: Array[int] = []
		for id in sim.grid.query(sim.player.position,1200):
			if sim.particles[id].alive and sim.particles[id].kind == kind: expected.append(id)
		check.call(sim.grid.query_kind(sim.particles,sim.player.position,1200,kind) == expected,"Typed particle queries preserve current live species and bucket order")
	sim.particles[0].kind = Sim.TOXIN
	sim.particles[0].alive = false
	check.call(not 0 in sim.grid.query_kind(sim.particles,sim.particles[0].p,64,Sim.TOXIN),"Typed queries never retain a stale species or dead packet")
	# Hybrid reference movement may have already updated bucket locations.
	for i in ids:
		var old: Vector2 = sim.particles[i].p
		sim.particles[i].p = Sim.Medium.wrap_position(old+Vector2(89,37))
		sim.grid.move(i,old,sim.particles[i].p)
	sim.grid.update(sim.particles,ids)
	full.rebuild(sim.particles)
	check.call(sim.grid.query(sim.player.position,1200) == full.query(sim.player.position,1200),"Incremental updates restore rebuild order after hybrid reference moves")
	# Appends and compaction are separate index lifetimes.
	sim.spawn_particle(Sim.NUTRIENT,Vector2.ZERO)
	sim.grid.update(sim.particles,[sim.particles.size()-1])
	full.rebuild(sim.particles)
	check.call(sim.grid.query(Vector2.ZERO,100) == full.query(Vector2.ZERO,100),"Incremental grid includes newly emitted packets")
	sim.particles[0].alive = false
	sim._compact_particles()
	sim.grid.rebuild(sim.particles)
	full.rebuild(sim.particles)
	check.call(sim.grid.query(sim.player.position,900) == full.query(sim.player.position,900),"Compaction rebuilds stored particle bucket identities")

static func _feeding(check: Callable) -> void:
	for seam in [false,true]:
		for full in [false,true]:
			var fast = Sim.new(315)
			var slow = Sim.new(315)
			slow.native_feeding = false
			for sim in [fast,slow]:
				var c = sim.player
				c.position = Vector2(4090,1280) if seam else Vector2(2048,1280)
				c.angle = 0.74
				c.add_organ("photosynthesis",1.6,"graze",false)
				for i in c.membrane.COUNT:
					var a: float = TAU*i/c.membrane.COUNT
					c.membrane.points[i] = Vector2.from_angle(a)*c.radius*(1+0.18*sin(a*3))
				c.membrane.maximum_radius = c.radius*1.18
				c.membrane.invalidate()
				c.substrate = c.gut_capacity()-(0 if full else 0.17)
				c.oxygen = c.oxygen_capacity()-(0 if full else 0.27)
				c.carbon = 30*c.growth_scale()-(0 if full else 0.37)
				sim.particles.clear()
				sim.grid.rebuild(sim.particles)
				sim.view_half = Vector2(3000,2000)
				for i in 120:
					var kind: int = [Sim.NUTRIENT,Sim.CARBON,Sim.OXYGEN,Sim.WASTE][i%4]
					var at: Vector2 = c.pore_center(c.organs[0])+Vector2.from_angle(i*2.4)*(i%35) if kind == Sim.NUTRIENT else c.position+Vector2.from_angle(i*2.4)*(30+i%60)
					sim.spawn_particle(kind,at,Vector2.ZERO,0.04,i%3)
				sim._feed(c)
			var a = fast.player
			var b = slow.player
			check.call(absf(a.substrate-b.substrate)+absf(a.eaten-b.eaten)+absf(a.oxygen-b.oxygen)+absf(a.carbon-b.carbon)+absf(a.foreign_intake-b.foreign_intake)<0.000001,"Native feeding preserves capped storage, foreign intake and grazing across a deformed seam")
			var same := true
			for i in fast.particles.size():
				same = same and fast.particles[i].alive == slow.particles[i].alive and absf(fast.particles[i].amount-slow.particles[i].amount)<0.000001
			check.call(same and a.organs[0].consumed_total == b.organs[0].consumed_total,"Native feeding consumes identical finite packets and pulses the same pore")

static func _hidden_chemistry(check: Callable) -> void:
	var fast = Sim.new(116)
	var slow = Sim.new(116)
	slow.native_particles = false
	slow.reaction_grid.native_enabled = false
	for sim in [fast,slow]:
		sim.particles.clear()
		sim.grid.rebuild(sim.particles)
		sim.time = 1.25
		sim.revision = 20
		for i in 330:
			sim.spawn_particle(i%Sim.SPECIES_COUNT,Vector2(4092+i%11*5,2400+i/11*4),Vector2(1,-2),0.3,i%2)
			sim.particles[-1].chemical_at = [0.0,0.5,1.25][i%3]
		sim.acidity.values.fill(0.4)
		sim.rng.seed = 334
		var ids: Array[int] = []
		ids.assign(range(sim.particles.size()))
		sim._chemistry(0,ids,true)
	var same := true
	for i in fast.particles.size():
		var a: Dictionary = fast.particles[i]
		var b: Dictionary = slow.particles[i]
		same = same and a.kind == b.kind and a.alive == b.alive and absf(a.amount-b.amount)<0.00001 and absf(a.capacity-b.capacity)<0.00001 and a.v.distance_to(b.v)<0.0001 and a.chemical_at == b.chemical_at
	check.call(same,"Native hidden chemistry preserves oriented reactions and per-packet elapsed timestamps")
	check.call(fast.rng.state == slow.rng.state and fast.chemistry_events == slow.chemistry_events,"Native hidden chemistry preserves random draw order and event accounting")
	check.call(absf(fast.respiration_loss-slow.respiration_loss)+absf(fast.recycled-slow.recycled)<0.00001,"Native hidden chemistry preserves organic material accounting")

static func _contacts(check: Callable) -> void:
	var fast = Sim.new(515)
	var slow = Sim.new(515)
	slow.native_contacts = false
	for cell in slow.cells: cell.fast_support = false
	for sim in [fast,slow]:
		sim.profiling = true
		sim.cells.resize(7)
		for i in sim.cells.size():
			var c = sim.cells[i]
			c.position = Sim.Medium.wrap_position(Vector2(4090,1280)+Vector2(i%3*66,i/3*60))
			c.velocity = Vector2(40-i*12,i*7)
			c.activity = 0.0 if i == 6 else 1.0
		for i in 4: sim._contacts(1.0/180)
	var same := true
	for i in fast.cells.size():
		var a = fast.cells[i]
		var b = slow.cells[i]
		same = same and a.position.distance_to(b.position)<0.000001 and a.velocity.distance_to(b.velocity)<0.000001 and absf(a.angular_velocity-b.angular_velocity)<0.000001 and a.membrane.points == b.membrane.points
	check.call(same,"Native contact broad phase retains sequential crowded seam impulses and membrane dents")
	check.call(fast.profile_counts == slow.profile_counts,"Native and reference contacts report identical pair and contact counts")

static func _hidden_feeding(check: Callable) -> void:
	var fast = Sim.new(971)
	var slow = Sim.new(971)
	slow.native_feeding = false
	for sim in [fast,slow]:
		var c = sim.cells[3]
		c.position = Vector2(4090,40)
		sim.habitat_geometry.enabled = false
		sim.particles.clear()
		sim.grid.rebuild(sim.particles)
		c.substrate = 0
		c.oxygen = 0
		c.carbon = 0
		for i in 900:
			sim.spawn_particle([Sim.NUTRIENT,Sim.OXYGEN,Sim.CARBON,Sim.WASTE][i%4],c.position+Vector2.from_angle(i*2.4)*(25+i%120),Vector2.ZERO,0.4,i%3)
		sim.rng.seed = 171
		for i in 40: sim.offscreen_ecology._feed(sim,c,0.125)
	var a = fast.cells[3]
	var b = slow.cells[3]
	var same := true
	for i in fast.particles.size():
		same = same and fast.particles[i].alive == slow.particles[i].alive and fast.particles[i].amount == slow.particles[i].amount
	check.call(same and a.substrate == b.substrate and a.oxygen == b.oxygen and a.carbon == b.carbon and a.eaten == b.eaten,"Native hidden feeding preserves probabilistic finite-packet intake and all shared storage caps")
	check.call(fast.rng.state == slow.rng.state and fast.offscreen_ecology.intake == slow.offscreen_ecology.intake and a.foreign_intake == b.foreign_intake,"Native hidden feeding preserves encounter random stream and material counters")
	# The actual stem-path callback remains part of accepted encounters.
	for sim in [fast,slow]:
		sim.habitat_geometry.enabled = true
		sim.rng.seed = 172
		for i in 5: sim.offscreen_ecology._feed(sim,sim.cells[3],0.125)
	check.call(fast.rng.state == slow.rng.state and fast.cells[3].eaten == slow.cells[3].eaten,"Native hidden feeding retains solid-path rejection")

static func _compression(check: Callable) -> void:
	var fast = Sim.Cell.Membrane.new(67,391)
	var slow = Sim.Cell.Membrane.new(67,391)
	slow.native_constraints = false
	for i in 40:
		fast.compress(i*1.73,1.0+i%4,67)
		slow.compress(i*1.73,1.0+i%4,67)
	var error := 0.0
	for i in fast.COUNT:
		error = maxf(error,fast.points[i].distance_to(slow.points[i]))
		error = maxf(error,fast.previous[i].distance_to(slow.previous[i]))
	check.call(error < 0.001 and absf(fast.maximum_radius-slow.maximum_radius)<0.001,"Native repeated membrane dents preserve radial geometry and velocity history")

static func _halo_timestamp(check: Callable) -> void:
	var fast = Sim.new(121)
	var slow = Sim.new(121)
	slow.native_particles = false
	for sim in [fast,slow]:
		sim.particles.clear()
		sim.grid.rebuild(sim.particles)
		sim.time = 3
		sim.spawn_particle(Sim.WASTE,sim.player.position+Vector2(sim.view_half.x+140,0))
		sim.particles[0].chemical_at = 1
		sim._chemistry(1.0/60)
	check.call(fast.particles[0].chemical_at == slow.particles[0].chemical_at,"Native unary clock marking matches reference inactive halo candidates")

static func _bounds(check: Callable) -> void:
	var fast = Sim.new(143)
	var slow = Sim.new(143)
	for sim in [fast,slow]:
		sim.particles.clear()
		sim.grid.rebuild(sim.particles)
		var origin: Vector2 = sim.habitat_geometry.plants[0].p
		for i in 600:
			sim.spawn_particle(Sim.NUTRIENT,origin+Vector2.from_angle(i*2.4)*(i%180))
			var p: Dictionary = sim.particles[-1]
			p.previous = p.p
			p.p = Sim.Medium.wrap_position(p.p+Vector2.from_angle(i*1.73)*160)
			p.updated = 1
		sim.habitat_geometry.accelerator.obstacle_particles(sim.particles,range(600),1,sim == fast)
	var same := true
	for i in 600:
		same = same and fast.particles[i].p == slow.particles[i].p and fast.particles[i].v == slow.particles[i].v and fast.particles[i].previous == slow.particles[i].previous
	check.call(same,"Swept stem bounds reject only impossible contacts without changing collisions or history")

static func _bookkeeping(check: Callable) -> void:
	var fast = Sim.new(251)
	var slow = Sim.new(251)
	slow.native_transport_bookkeeping = false
	for sim in [fast,slow]:
		sim.particles[0].alive = false
		sim.particles[1].transport_at = 100.0
		sim.background_credit = 0.75
		sim.background_cursor = sim.particles.size()-17
	for i in 8:
		for sim in [fast,slow]:
			sim.camera_follows_player = false
			sim.camera_position = Vector2(i*311,2550)
			sim.revision += 1
			sim._move_particles(0.17)
			sim.habitat_geometry.move_particles(sim.particles,sim.foreground_particle_ids,sim.revision,sim.grid,true)
			sim._settle_transport(sim.foreground_particle_ids,false)
	check.call(fast.particles == slow.particles and fast.rng.state == slow.rng.state and fast.background_rng.state == slow.background_rng.state,"Native transport bookkeeping preserves packet history, camera catch-up and both random streams")
	check.call(fast.background_cursor == slow.background_cursor and fast.background_credit == slow.background_credit and fast.foreground_particle_ids == slow.foreground_particle_ids,"Native background batching preserves round-robin order and scheduling credit")

static func _cell_bounds(check: Callable) -> void:
	var sim = Sim.new(351)
	var plain = Sim.Habitat.new(0)
	plain.plants = sim.habitat_geometry.plants
	plain.forms = sim.habitat_geometry.forms
	plain.rebuild()
	plain.native_bounds = false
	var same := true
	for i in 40:
		var a = Sim.Cell.clone_state(sim.player)
		a.activity = 1
		a.position = Sim.Medium.wrap_position(sim.habitat_geometry.plants[i%sim.habitat_geometry.plants.size()].p+Vector2.from_angle(i*2.4)*(80+i%6*20))
		a.velocity = Vector2.from_angle(i*1.73)*80
		a.angle = i*0.23
		var b = Sim.Cell.clone_state(a)
		var finish: Vector2 = Sim.Medium.wrap_position(a.position+a.velocity*0.15)
		sim.habitat_geometry.move_cell(a,a.position,finish,0.15)
		plain.move_cell(b,b.position,finish,0.15)
		same = same and a.position == b.position and a.velocity == b.velocity and a.angular_velocity == b.angular_velocity and a.membrane.points == b.membrane.points
	check.call(same,"Cell stem bounds preserve swept impacts, sequential overlap impulses and membrane dents")

static func _dirty_chemistry(check: Callable) -> void:
	var fast = Sim.new(551)
	var slow = Sim.new(551)
	slow.native_chemistry_writes = false
	for i in 30:
		for sim in [fast,slow]:
			sim.time += 1.0/60
			sim.revision += 1
			sim._chemistry(1.0/60)
	check.call(fast.particles == slow.particles and fast.chemistry_events == slow.chemistry_events and fast.rng.state == slow.rng.state,"Dirty chemistry writes and sparse scratch clearing preserve consecutive reaction batches exactly")

static func _mesh(check: Callable) -> void:
	var membrane = Sim.Cell.Membrane.new(77,923)
	for i in 10: membrane.compress(i*1.37,3,77)
	var outline := membrane.outline()
	var art = preload("res://scripts/membrane_art.gd")
	for detailed in [true,false]:
		var shape := outline
		if not detailed:
			shape = PackedVector2Array()
			for i in range(0,outline.size(),4): shape.append(outline[i])
		var fast: Array = art.arrays(shape)
		var slow: Array = art.arrays(shape,false)
		var error := 0.0
		for i in fast[Mesh.ARRAY_VERTEX].size():
			error = maxf(error,fast[Mesh.ARRAY_VERTEX][i].distance_to(slow[Mesh.ARRAY_VERTEX][i]))
		check.call(error < 0.00001 and fast[Mesh.ARRAY_COLOR] == slow[Mesh.ARRAY_COLOR] and fast[Mesh.ARRAY_TEX_UV] == slow[Mesh.ARRAY_TEX_UV] and fast[Mesh.ARRAY_INDEX] == slow[Mesh.ARRAY_INDEX],"Batched membrane artwork preserves both mesh LODs, ring colors, UVs and every triangle")

static func _compaction(check: Callable) -> void:
	var fast = Sim.new(741)
	var slow = Sim.new(741)
	slow.native_particle_compaction = false
	for sim in [fast,slow]:
		sim.background_cursor = sim.particles.size()-13
		for i in sim.particles.size(): sim.particles[i].alive = i%7 == 0
		sim._compact_particles()
	check.call(fast.particles == slow.particles and fast.background_cursor == slow.background_cursor,"Native particle compaction preserves survivors and round-robin scheduling identity")
	for sim in [fast,slow]:
		for p in sim.particles: p.alive = false
		sim._compact_particles()
	check.call(fast.particles.is_empty() and slow.particles.is_empty() and fast.background_cursor == 0 and slow.background_cursor == 0,"Compaction handles an entirely depleted habitat without invalid cursor arithmetic")
