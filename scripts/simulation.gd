extends RefCounted
## Authoritative fixed-step ecology, independent of input and scene nodes.
const Evolution = preload("res://scripts/evolution.gd")
const Genes = preload("res://scripts/mutations.gd")
var evolution
var build_original = null
var build_state: Dictionary = {}
var build_waste := 0.0
const Backend = preload("res://scripts/backend.gd")
var kernels = Backend.create()
var gpu_transport = null
var native_particles := kernels != null
var native_fluid := kernels != null
var native_render := kernels != null
var native_exclusion := kernels != null
var spatial_queries := true
var stagger_sensing := true
var cell_index = preload("res://scripts/cell_index.gd").new()

const Habitat = preload("res://scripts/habitat.gd")
var habitat_geometry

const Grid = preload("res://scripts/spatial_grid.gd")
const Cell = preload("res://scripts/cell.gd")
const Medium = preload("res://scripts/medium.gd")
const WORLD := Medium.WORLD
const VIEW := Vector2(1016,632)
const KINDS := Cell.KINDS
const COST := Cell.COST
const NUTRIENT := 0
const OXYGEN := 1
const WASTE := 2
const DANGER := 3
const TOXIN := 4
const CARBON := 5
const ENZYME := 6
const ANTITOXIN := 7
const ACID := 8
const BUFFER := 9
const DECOY := 10
const SPECIES_COUNT := 11
const Acidity = preload("res://scripts/acidity.gd")
const HABITATS := ["BALANCED TIDE", "LEAN HUNTING GROUNDS", "RICH / ARMORED HUNTERS"]
var rng := RandomNumberGenerator.new()
var grid = Grid.new()
var reaction_grid = Grid.new(16.0)
var fluid = Medium.new()
var acidity = Acidity.new()
var player = Cell.new(0,Vector2(2048,1280))
var cells: Array = []
var particles: Array = []
var events: Array = []
var pending_replacements: Array = []
var next_id := 1
var inherited_lineages: Dictionary = {}
var time := 0.0
var habitat := 0
var seed_value := 20261004
var spawn_clock := 0.0
var won := false
var recycled := 0.0
var external_input := 0.0
var respiration_loss := 0.0
var kills := 0
var active_cells := 0
var active_particles := 0
var view_half := VIEW*0.5
var revision := 0
var profile_usec: Dictionary = {}
var camera_position := Vector2(2048,1280)
var camera_follows_player := true
var chemistry_events := {"decay":0,"combine":0,"recycle":0,"detox":0,"spoil":0,"enzyme":0,"neutralize":0}

func _init(seed_number: int = 20261004, profile: int = 0) -> void:
	seed_value = seed_number
	rng.seed = seed_number
	evolution = Evolution.new(seed_number)
	habitat = clampi(profile,0,2)
	player.role = "player"
	player.biomass = 36
	player.update_geometry()
	player.membrane = Cell.Membrane.new(player.radius,absi(seed_value*1000003))
	player.add_organ("feeding",0,"graze",false)
	player.add_organ("propulsion",PI,"graze",false)
	cells.append(player)
	# Whole habitats are stored. Only organisms inside the microscope advance.
	for i in 18:
		if habitat == 0 and i%5 == 3:
			pending_replacements.append({"role":"hunter","id":-1,"not_before":240.0})
			continue
		var p = player.position + Vector2.from_angle(i*2.4)* (1050+i*45 if i%5 == 3 else 220 if i == 0 else 340+i*94)
		_make_cell(Medium.wrap_position(p), "hunter" if i%5 == 3 else "grazer")
	habitat_geometry = Habitat.new(seed_number,cells)
	# Initial clouds are retained products of these cells' pre-observation life.
	# No environmental spawner runs after initialization.
	for cell in cells: _seed_cell_products(cell)
	grid.rebuild(particles)
	fluid.set_camera(player.position if camera_follows_player else camera_position,view_half)

func _make_cell(p: Vector2, role: String):
	var cell = Cell.new(next_id,p)
	next_id += 1
	cell.role = role
	cell.angle = rng.randf()*TAU
	cell.body = 135.0 if role == "hunter" else rng.randf_range(14,32)
	cell.biomass = 35 if role == "hunter" else 10
	cell.update_geometry()
	cell.membrane = Cell.Membrane.new(cell.radius,absi(seed_value*1000003+cell.id*9176))
	cell.add_organ("feeding",1.1 if role == "hunter" else 1.4,"graze",false)
	cell.add_organ("propulsion",PI,"graze",false)
	if role == "hunter":
		cell.add_organ("offensive",0,"graze",false)
		if habitat == 2:
			cell.add_organ("toxin",1.8,"graze",false)
			cell.biomass = 90
			cell.update_geometry()
			cell.membrane = Cell.Membrane.new(cell.radius,absi(seed_value*1000003+cell.id*9176))
			for a in [0.6,1.9,2.6,3.7,5.65]: cell.add_organ("protection",a,"graze",false)
			cell.add_organ("regenerative",4.4,"graze",false)
	else:
		cell.add_organ("photosynthesis",0,"graze",false)
	cell.update_geometry()
	cell.previous_angle = cell.angle
	if stagger_sensing: cell.sense_clock = (cell.id%9)/60.0
	cells.append(cell)
	return cell

func screen_position(p: Vector2) -> Vector2:
	return view_half+Medium.offset(camera_position if not camera_follows_player else player.position,p)

func activity_at(p: Vector2) -> float:
	return Medium.visibility(p,player.position if camera_follows_player else camera_position,view_half)

func local_particle_ids(margin: float = 0.0) -> Array[int]:
	if grid.source_size != particles.size(): grid.rebuild(particles)
	return grid.query_rect(player.position if camera_follows_player else camera_position,view_half+Vector2.ONE*margin)

func cell_by_id(identity: int):
	for cell in cells:
		if cell.id == identity and not cell.dead: return cell
	return null

func install(kind: String, local_angle: float, mode: String = "graze", size: float = 1.0) -> bool:
	var cost := Evolution.install_price(size)
	if evolution.terminal() or (evolution.enabled and evolution.points < cost): return false
	if not player.add_organ(kind,local_angle,mode,true,size): return false
	evolution.spend(cost,"Install "+kind)
	return true

func remove(index: int) -> bool:
	var debris: float = player.recycle(index)
	if debris < 0: return false
	_build_debris(debris)
	return true

func spawn_particle(kind: int, p: Vector2, v: Vector2 = Vector2.ZERO, amount: float = 1.0, owner: int = -1, source_radius: float = 0.0) -> void:
	if amount <= 0: return
	if grid.source_size != particles.size(): grid.rebuild(particles)
	particles.append({"kind":kind,"p":Medium.wrap_position(p),"previous":Medium.wrap_position(p),"v":v,"amount":amount,"age":0.0,"alive":true,"owner":owner,"source_radius":source_radius,"angle":rng.randf()*TAU,"previous_angle":0.0,"spin":rng.randfn(0,0.8),"direction":Vector2.RIGHT,"capacity":amount})
	particles[-1].previous_angle = particles[-1].angle
	particles[-1].direction = Vector2.from_angle(particles[-1].angle)
	grid.insert(particles.size()-1,particles[-1].p)

func _emit_material(kind: int, at: Vector2, amount: float, motion: Vector2 = Vector2.ZERO, owner: int = 0) -> void:
	# Packet merging requires oriented contact, never an emission shortcut.
	var count := maxi(1,ceili(amount/0.35))
	for i in count: spawn_particle(kind,at,motion,amount/count,owner)

func step(dt: float) -> void:
	if player.dead or evolution.terminal() or build_original != null: return
	time += dt
	revision += 1
	if grid.source_size != particles.size(): grid.rebuild(particles)
	var mark := Time.get_ticks_usec()
	fluid.set_camera(player.position if camera_follows_player else camera_position,view_half)
	if native_fluid:
		fluid.velocity = kernels.fluid_step(fluid.velocity,fluid.activity,fluid.tide,dt,fluid.driven)
		if revision%6 == 0: acidity.values = kernels.acid_step(acidity.values,fluid.velocity,fluid.activity,dt*6)
	else:
		fluid.step(dt)
		if revision%6 == 0: acidity.step(dt*6,fluid)
	active_cells = 0
	for cell in cells:
		cell.previous_position = cell.position
		cell.previous_angle = cell.angle
		cell.activity = activity_at(cell.position)
		if cell.activity > 0 and not cell.dead:
			active_cells += 1
			var local_dt: float = dt*cell.activity
			cell.age += local_dt
			cell.hurt_flash = maxf(0,cell.hurt_flash-local_dt*2)
			cell.reaction_flash = maxf(0,cell.reaction_flash-local_dt*2)
	_suction(dt)
	profile_usec["fluid"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	_move_particles(dt)
	habitat_geometry.move_particles(particles,local_particle_ids(64),revision,grid,native_particles)
	_chemistry(dt)
	profile_usec["particles"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		var local_dt: float = dt*cell.activity
		cell.animate_resources(local_dt)
		_clear_receptors(cell,local_dt)
		_sense(cell,local_dt)
		_feed(cell)
		_acid_stress(cell,local_dt)
		_photosynthesize(cell,local_dt)
		_metabolize(cell,local_dt)
		cell.heal(local_dt)
		for leak in cell.leaks:
			var normal := Vector2.from_angle(cell.angle+leak.a)
			_emit_material(NUTRIENT,cell.position+cell.local_point(leak.a).rotated(cell.angle)+normal*12,leak.amount,normal*12,cell.id)
		# Tiny continuous emissions are aggregated into material-bearing packets.
		if cell.waste >= 0.2:
			_emit_material(WASTE,cell.position-Vector2.from_angle(cell.angle)*(cell.radius+12),cell.waste,Vector2.ZERO,cell.id)
			cell.waste = 0
		cell.update_geometry()
		# Shrinkage can shed crowded organs, releasing their remaining material.
		while cell.occupied() > cell.perimeter() and not cell.organs.is_empty():
			var organ: Dictionary = cell.organs.pop_back()
			cell.lost_organs.append(organ.duplicate(true))
			spawn_particle(WASTE,cell.organ_position(organ),Vector2.ZERO,organ.material,cell.id)
		var traction := PackedVector2Array()
		for point in cell.membrane.points:
			var arm: Vector2 = point.rotated(cell.angle)
			traction.append((fluid.sample(cell.position+arm)-cell.velocity-arm.orthogonal()*cell.angular_velocity).rotated(-cell.angle).limit_length(90))
		cell.membrane.step(local_dt,cell.radius,cell.shape_acceleration.rotated(-cell.angle),cell.age+cell.id*1.7,1.0,traction)
		cell.render_revision += 1
		_emit_and_attack(cell,local_dt)
	profile_usec["biology"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	# Short motion substeps plus swept contacts avoid crossing from one side to the other.
	var before_motion: Dictionary = {}
	for cell in cells: before_motion[cell.id] = cell.velocity
	for substep in 3:
		_motion(dt/3.0)
		_contacts(dt/3.0)
		for cell in cells:
			if cell.dead or cell.activity <= 0: continue
			var contact: Array = habitat_geometry.move(cell.position,cell.position,cell.velocity,cell.extent())
			cell.position = contact[0]
			cell.velocity = contact[1]
	for cell in cells:
		cell.shape_acceleration = ((cell.velocity-before_motion[cell.id])/dt).limit_length(600)
	profile_usec["motion"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	if spatial_queries: cell_index.rebuild(cells)
	_spike_contacts(dt)
	_toxin_contacts()
	_receptor_contacts()
	_exclude_particles()
	for cell in cells.duplicate():
		if cell.activity > 0 and cell.health <= 0 and not cell.dead: _die(cell)
	spawn_clock += dt
	if spawn_clock >= 0.5:
		spawn_clock -= 0.5
		particles = particles.filter(func(p): return p.alive)
		grid.rebuild(particles)
		_replace_population()
	profile_usec["ecology"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	evolution.advance(dt,self)
	profile_usec["evolution"] = Time.get_ticks_usec()-mark
	won = evolution.status == "won"

func _move_particles(dt: float) -> void:
	if gpu_transport != null:
		active_particles = gpu_transport.step(particles,local_particle_ids(64),fluid.velocity,player.position if camera_follows_player else camera_position,view_half,dt,revision,rng)
		grid.rebuild(particles)
		return
	if native_particles:
		active_particles = kernels.transport(particles,local_particle_ids(64),fluid.velocity,player.position if camera_follows_player else camera_position,view_half,dt,revision,rng)
		grid.rebuild(particles)
		return
	active_particles = 0
	for index in local_particle_ids(64):
		var particle: Dictionary = particles[index]
		if not particle.alive: continue
		var scale = activity_at(particle.p)
		if scale <= 0: continue
		active_particles += 1
		var step_dt = dt*scale
		particle.updated = revision
		particle.previous = particle.p
		particle.p = Medium.wrap_position(particle.p+(particle.v+fluid.sample(particle.p))*step_dt+Vector2(rng.randfn(),rng.randfn())*sqrt(12*step_dt))
		grid.move(index,particle.previous,particle.p)
		particle.v *= exp(-step_dt*0.8)
		particle.age += step_dt
		particle.previous_angle = particle.angle
		particle.angle = wrapf(particle.angle+particle.spin*step_dt+rng.randfn()*sqrt(1.2*step_dt),-PI,PI)
		particle.direction = Vector2.from_angle(particle.angle)

func _chemistry(dt: float) -> void:
	if native_particles:
		var result: Dictionary = kernels.chemistry(particles,local_particle_ids(),acidity.values,player.position if camera_follows_player else camera_position,view_half,dt,revision,rng)
		acidity.values = result.acid
		respiration_loss += result.loss
		recycled += result.recycled
		for kind in result.events: chemistry_events[kind] += result.events[kind]
		return
	# Unimolecular decay is stochastic. Pair reactions are deterministic contact
	# rules: both binding patches must face their partner within 60 degrees.
	var local_ids := local_particle_ids()
	reaction_grid.clear()
	for index in local_ids:
		var p: Dictionary = particles[index]
		p.reaction_activity = activity_at(p.p) if p.alive else 0.0
		p.contact_radius = particle_radius(p.kind)*particle_scale(p.amount)
		if p.reaction_activity > 0: reaction_grid.insert(index,p.p)
	for index in local_ids:
		var p: Dictionary = particles[index]
		if not p.alive: continue
		var local_dt: float = dt*p.reaction_activity
		if local_dt <= 0: continue
		if p.kind in [ACID,BUFFER]:
			var sign_value := 1.0 if p.kind == ACID else -1.0
			var used := absf(acidity.exchange(p.p,sign_value*minf(p.capacity,local_dt*0.2)))
			p.capacity -= used
			if p.capacity <= 0.000001: p.kind = WASTE
		if chance([0.003,0.008,0.006,0.65,0.1,0.001,0.02,0.015,0.008,0.008,0.08][p.kind],local_dt):
			if p.kind != OXYGEN and p.kind != DANGER: respiration_loss += p.amount
			p.alive = false
			chemistry_events.decay += 1
			continue
		if p.kind == DANGER or p.get("reacted",-1) == revision: continue
		for other_index in reaction_grid.query(p.p,18):
			if other_index <= index: continue
			var other: Dictionary = particles[other_index]
			if not other.alive or other.kind == DANGER or other.get("reacted",-1) == revision: continue
			var delta := Medium.offset(p.p,other.p)
			var contact: float = p.contact_radius+other.contact_radius
			if delta.length_squared() > contact*contact: continue
			var normal := delta.normalized() if delta.length_squared() > 0.000001 else Vector2.RIGHT
			var acid := acidity.sample(p.p)
			var alignment := binding_threshold(p.kind,other.kind,acid)
			if p.direction.dot(normal) >= alignment and other.direction.dot(-normal) >= alignment and _react_pair(p,other,acid):
				p.reacted = revision
				other.reacted = revision
				break
			# Unsuccessful contacts separate softly and tumble, giving binding sites
			# another encounter rather than allowing particles to remain overlaid.
			var push := normal*(contact-delta.length())*0.25
			p.v -= push*8
			other.v += push*8

static func particle_radius(kind: int) -> float:
	return [4.0,2.5,3.0,2.5,5.0,3.0,4.0,4.0,3.0,3.0,3.5][kind]

static func particle_scale(amount: float) -> float:
	return clampf(sqrt(amount/0.3),0.8,1.7)

static func binding_threshold(a: int, b: int, acid: float) -> float:
	if ENZYME in [a,b] and WASTE in [a,b]:
		# A modeled acid hydrolase has an acidic optimum. This is an affinity
		# abstraction, not a claim that pH literally widens a molecular patch.
		return 0.5+0.46*pow(clampf(absf(acid-0.4)/0.4,0,1),2)
	return 0.5

func _acid_stress(cell, dt: float) -> void:
	var exposure := acidity.sample(cell.position)
	var demand: float = maxf(0,exposure-0.15)*dt*5*cell.growth_scale()
	var spent: float = cell.spend_energy(demand)
	var overload := maxf(0,exposure-0.5)*0.8+(demand-spent)*0.15/maxf(dt,0.00001)
	cell.acid_stress = clampf(cell.acid_stress+(overload-0.12)*dt,0,1)
	if cell.acid_stress > 0.6:
		cell.health = maxf(0,cell.health-dt*(cell.acid_stress-0.6)*8)

func _react_pair(a: Dictionary, b: Dictionary, acid: float = 0.0) -> bool:
	if b.kind == ENZYME and a.kind == WASTE: return _react_pair(b,a,acid)
	if a.kind == ENZYME and b.kind == WASTE and acid < 0.9:
		b.kind = NUTRIENT
		recycled += b.amount
		chemistry_events.enzyme += 1
		return true
	if b.kind == ANTITOXIN and a.kind == TOXIN: return _react_pair(b,a,acid)
	if a.kind == ANTITOXIN and b.kind == TOXIN:
		a.kind = WASTE
		a.amount += b.amount
		b.alive = false
		chemistry_events.neutralize += 1
		return true
	if a.kind in [ACID,BUFFER] and b.kind in [ACID,BUFFER] and a.kind != b.kind:
		var neutralized: float = minf(a.capacity,b.capacity)
		a.capacity -= neutralized
		b.capacity -= neutralized
		if a.capacity <= 0.000001: a.kind = WASTE
		if b.capacity <= 0.000001: b.kind = WASTE
		return true
	if a.kind == OXYGEN and b.kind in [WASTE,TOXIN]: return _react_pair(b,a,acid)
	if a.kind == WASTE and b.kind == OXYGEN and b.amount >= a.amount*0.15 and acid < 0.8:
		var amount: float = a.amount
		a.kind = NUTRIENT
		a.amount = amount*0.6
		b.kind = CARBON
		b.amount = amount*0.4
		recycled += amount*0.6
		chemistry_events.recycle += 1
		return true
	if a.kind == TOXIN and b.kind == NUTRIENT: return _react_pair(b,a,acid)
	if a.kind == NUTRIENT and b.kind == TOXIN:
		a.kind = WASTE
		chemistry_events.spoil += 1
		return true
	if a.kind == b.kind and a.kind in [NUTRIENT,WASTE,CARBON,OXYGEN] and a.amount+b.amount <= 1.4:
		if a.kind == TOXIN and a.owner != b.owner: return false
		var total: float = a.amount+b.amount
		if total <= 0: return false
		# Normalize weights before float-vector arithmetic: tiny photosynthetic
		# remainders can be below float32 range while their ratio is well-defined.
		a.v = a.v.lerp(b.v,b.amount/total)
		a.amount += b.amount
		b.alive = false
		chemistry_events.combine += 1
		return true
	return false

func chance(rate: float, dt: float) -> bool:
	return rng.randf() < 1.0-exp(-maxf(0,rate)*maxf(0,dt))

func light_at(at: Vector2) -> float:
	var p := Medium.wrap_position(at)
	var field := 0.5+0.28*sin(TAU*p.x/WORLD.x*3+0.4)+0.22*cos(TAU*p.y/WORLD.y*3-0.8)
	return clampf(field*(0.5 if habitat == 1 else 1.25 if habitat == 2 else 1.0)*evolution.light_factor,0.02,1.0)

func light_direction(at: Vector2) -> Vector2:
	var p := Medium.wrap_position(at)
	return Vector2(0.28*TAU*3/WORLD.x*cos(TAU*p.x/WORLD.x*3+0.4),-0.22*TAU*3/WORLD.y*sin(TAU*p.y/WORLD.y*3-0.8)).normalized()

func _photosynthesize(cell, dt: float) -> void:
	for organ in cell.organs:
		if organ.kind != "photosynthesis": continue
		var light := light_at(cell.organ_position(organ))
		if not chance(10*light*organ.scale*organ.scale*organ.hp/organ.max_hp*Genes.factor(organ,"sun" if light >= 0.5 else "shade"),dt): continue
		# Light drives a coarse dissolved-carbon fixation event. Water is an
		# implicit medium reservoir; oxygen units are not organic mass units.
		var amount: float = minf(cell.carbon,0.35)
		if amount <= 0: continue
		cell.carbon -= amount
		cell.biomass += amount*0.35
		var stored: float = minf(amount*0.35,maxf(0,cell.gut_capacity()-cell.substrate))
		cell.substrate += stored
		var food := amount*0.65-stored
		cell.fixed_carbon += amount
		if cell == player: evolution.record("photo",amount)
		cell.oxygen_produced += amount*2.5
		cell.energy = minf(cell.energy_capacity(),cell.energy+amount*4)
		var at: Vector2 = cell.organ_position(organ)+cell.local_point(organ.a).normalized().rotated(cell.angle)*16
		spawn_particle(OXYGEN,at,Vector2.from_angle(rng.randf()*TAU)*12,amount*2.5,cell.id)
		spawn_particle(NUTRIENT,at,Vector2.from_angle(rng.randf()*TAU)*18,food,cell.id)
		cell.consumed(organ,amount)

func _seed_cell_products(cell) -> void:
	# Explicit cell-derived starting stocks, representing earlier metabolism.
	var food_count := 55 if habitat != 1 else 14
	cell.carbon += food_count*0.3+24
	cell.oxygen += 36
	for i in (food_count+180):
		var kind := NUTRIENT if i < food_count else CARBON if i < food_count+60 else OXYGEN
		var amount := 0.3 if kind != CARBON else 0.4
		if kind == OXYGEN: cell.oxygen -= amount
		else: cell.carbon -= amount
		var at: Vector2 = cell.position+Vector2.from_angle(rng.randf()*TAU)*(cell.radius+12+rng.randf()*160)
		spawn_particle(kind,at,Vector2.ZERO,amount,cell.id)

func _suction(dt: float) -> void:
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		for organ in cell.organs:
			if organ.kind != "feeding" or cell.energy <= 0: continue
			var local_dt: float = dt*cell.activity
			var health: float = organ.hp/organ.max_hp
			fluid.suction(cell,cell.pore_center(organ),110*sqrt(organ.scale),24*organ.scale*health*Genes.factor(organ,"suction"),local_dt)
			cell.spend_energy(local_dt*0.18*organ.scale*organ.scale,organ)

func _sense(cell, dt: float) -> void:
	# A memory or in-flight signal cannot outlive its source organ.
	cell.signals = cell.signals.filter(func(packet): return not cell.organ_by_id(packet.organ_id).is_empty())
	if cell.organ_by_id(cell.target_organ_id).is_empty(): cell.target_memory = 0
	cell.sense_clock -= dt
	cell.target_memory = maxf(0,cell.target_memory-dt)
	if cell.sense_clock <= 0:
		cell.sense_clock = 0.15
		cell.sensed = false
		var best: Dictionary = {}
		var best_score := -1.0
		for organ in cell.organs:
			if organ.kind not in ["feeding","sensing","offensive","photosynthesis"]: continue
			var mode: String = "hunt" if organ.kind == "offensive" else "light" if organ.kind == "photosynthesis" else organ.mode
			var reach: float = (760.0 if mode == "hunt" else 310.0)*sqrt(organ.scale)*(1-organ.blocked*0.65)*Genes.factor(organ,"sense")
			var receptor: Vector2 = cell.organ_position(organ)
			if mode == "light":
				var direction := light_direction(receptor)
				if best_score < 0.7 and direction.length_squared() > 0.01 and light_at(receptor) < 0.98:
					best_score = 0.7
					best = {"mode":"light","id":-1,"at":cell.position+direction*150,"a":organ.a,"organ_id":organ.id}
				continue
			var food := Vector2.ZERO
			for index in grid.query(receptor,reach):
				var p: Dictionary = particles[index]
				if not p.alive or p.owner == cell.id: continue
				var distance: float = Medium.offset(receptor,p.p).length()
				if distance > reach: continue
				if mode == "graze" and p.kind == NUTRIENT:
					food += Medium.offset(cell.position,p.p).normalized()*p.amount/maxf(25,distance)
				elif p.kind == DANGER and mode in ["hunt","flee"]:
					var prey = cell_by_id(p.owner)
					if prey == null or prey.lineage_id() == cell.lineage_id(): continue
					if mode == "hunt" and prey.organic_mass() >= cell.organic_mass(): continue
					var score := (100.0 if mode == "flee" else 2.0)+1.0/(1+distance)
					if prey.id == cell.target_id: score += 0.05
					if score > best_score:
						best_score = score
						best = {"mode":mode,"id":prey.id,"at":prey.position,"a":organ.a,"organ_id":organ.id}
			if food.length() > 0.001 and best_score < 1:
				best_score = 1
				best = {"mode":"graze","id":-1,"at":cell.position+food.normalized()*100,"a":organ.a,"organ_id":organ.id}
		if not best.is_empty():
			cell.sensed = true
			cell.signals.append({"p":cell.local_point(best.a)*0.75,"mode":best.mode,"id":best.id,"at":best.at,"fear":best.mode == "flee","organ_id":best.organ_id})
	for packet in cell.signals:
		packet.p = packet.p.move_toward(Vector2.ZERO,dt*(220+cell.radius*2))
		if packet.p.length() < 5:
			cell.target_id = packet.id
			cell.target_position = packet.at
			cell.target_mode = packet.mode
			cell.target_organ_id = packet.organ_id
			cell.target_memory = 1.2
	cell.signals = cell.signals.filter(func(packet): return packet.p.length() >= 5)
	if cell.target_memory > 0:
		cell.facing = Medium.offset(cell.position,cell.target_position).normalized()
		cell.target = -cell.facing if cell.target_mode == "flee" else cell.facing
		cell.threat = cell.facing if cell.target_id >= 0 else Vector2.ZERO
		cell.state = {"graze":"FORAGING","hunt":"PURSUING SMALLER CELL","light":"SEEKING LIGHT","flee":"FLEEING"}.get(cell.target_mode,"EXPLORING")
		var organ: Dictionary = cell.organ_by_id(cell.target_organ_id)
		cell.target_mouth = cell.local_point(organ.a).angle() if not organ.is_empty() else 0.0
	else:
		cell.target = Vector2.from_angle(cell.angle+sin(cell.age*0.4+cell.id)*0.6)
		cell.facing = cell.target
		cell.threat = Vector2.ZERO
		cell.target_id = -1
		cell.target_mouth = 0
		cell.state = "EXPLORING"
	if cell.count("propulsion") == 0: cell.state = "DRIFTING · PORE PUMPING"

func _feed(cell) -> void:
	for organ in cell.organs:
		if organ.kind != "feeding": continue
		var mouth: Vector2 = cell.pore_center(organ)
		var reach: float = cell.pore_radius(organ)+8
		for index in grid.query(mouth,reach):
			var p: Dictionary = particles[index]
			if not p.alive or p.kind != NUTRIENT or activity_at(p.p) <= 0: continue
			if Medium.offset(mouth,p.p).length() <= reach:
				var amount = minf(p.amount,maxf(0,cell.gut_capacity()-cell.substrate))
				p.amount -= amount
				cell.substrate += amount
				cell.eaten += amount
				if p.owner != cell.id: cell.foreign_intake += amount
				if amount > 0: cell.consumed(organ,amount)
				if p.amount <= 0.000001: p.alive = false
	for index in grid.query(cell.position,cell.extent()+12):
		var p: Dictionary = particles[index]
		if p.alive and p.kind == CARBON and cell.count("photosynthesis") > 0 and activity_at(p.p) > 0 and Medium.offset(cell.position,p.p).length() < cell.extent()+18:
			var carbon_taken: float = minf(p.amount,maxf(0,30*cell.growth_scale()-cell.carbon))
			cell.carbon += carbon_taken
			if p.owner != cell.id: cell.foreign_intake += carbon_taken
			p.amount -= carbon_taken
			if p.amount <= 0.000001: p.alive = false
		if p.alive and p.kind == OXYGEN and activity_at(p.p) > 0 and Medium.offset(cell.position,p.p).length() < cell.support(Medium.offset(cell.position,p.p).angle())+14:
			var amount = minf(p.amount,maxf(0,cell.oxygen_capacity()-cell.oxygen))
			cell.oxygen += amount
			p.amount -= amount
			if p.amount <= 0.000001: p.alive = false

func _metabolize(cell, dt: float) -> void:
	# Storage mobilization bridges a food gap; it is not free ATP. It transfers
	# existing tissue through the same limited metabolic pathways.
	cell.reserve_activity = maxf(0,cell.reserve_activity-dt)
	if cell.energy < 20 and cell.substrate < 1:
		var mobilized: float = minf(maxf(0,cell.biomass-8),dt*0.3*cell.growth_scale())
		cell.biomass -= mobilized
		cell.substrate += mobilized
		cell.reserve_used += mobilized
		if mobilized > 0: cell.reserve_activity = 2
	var capacity: float = dt*1.8*cell.growth_scale()*(1-cell.acid_stress*0.6)
	var amount = minf(minf(cell.substrate,cell.oxygen),capacity)
	cell.substrate -= amount
	cell.oxygen -= amount
	cell.energy = minf(cell.energy_capacity(),cell.energy+amount*5.0)
	cell.biomass += amount*0.7
	cell.carbon += amount*0.1
	cell.waste += amount*0.2
	cell.processed += amount
	cell.fermentation_activity = maxf(0,cell.fermentation_activity-dt)
	var fermented: float = minf(cell.substrate,maxf(0,capacity-amount))
	if fermented > 0:
		cell.substrate -= fermented
		cell.energy = minf(cell.energy_capacity(),cell.energy+fermented*2)
		cell.biomass += fermented*0.3
		cell.waste += fermented*0.3
		cell.carbon += fermented*0.1
		# Unrecoverable end products leave the represented material pool. This
		# prevents waste/enzyme recycling from becoming a closed energy source.
		respiration_loss += fermented*0.3
		cell.processed += fermented
		cell.fermented += fermented
		cell.fermentation_activity = 2
	cell.spend_energy(dt*0.264*cell.growth_scale())
	for organ in cell.organs: cell.spend_energy(dt*organ.scale*organ.scale*Genes.factor(organ,"upkeep",0.0),organ)
	if cell.energy <= 0: cell.health = maxf(0,cell.health-dt*2)

func _secretion_needed(cell, organ: Dictionary, kind: int) -> bool:
	if kind == BUFFER: return acidity.sample(cell.organ_position(organ)) > 0.02 or cell.acid_stress > 0.03
	if kind not in [ENZYME,ANTITOXIN]: return true
	var wanted := WASTE if kind == ENZYME else TOXIN
	var at: Vector2 = cell.organ_position(organ)
	var reach: float = 140*sqrt(organ.scale)
	for index in grid.query(at,reach):
		var packet: Dictionary = particles[index]
		if not packet.alive or packet.kind != wanted or activity_at(packet.p) <= 0: continue
		if wanted == TOXIN and inherited_lineages.get(packet.owner,packet.owner) == cell.lineage_id(): continue
		if Medium.offset(at,packet.p).length_squared() <= reach*reach: return true
	return false

func _emit_and_attack(cell, dt: float) -> void:
	if chance(4.0,dt):
		var direction := Vector2.from_angle(rng.randf()*TAU)
		spawn_particle(DANGER,cell.position+direction*(cell.radius+9),direction*20,0.2,cell.id,cell.radius)
	if cell.carbon > (3.0 if cell.count("photosynthesis") == 0 else 20.0) and chance(5.0,dt):
		var amount: float = minf(0.3,cell.carbon)
		cell.carbon -= amount
		spawn_particle(CARBON,cell.position-Vector2.from_angle(cell.angle)*(cell.radius+12),Vector2.ZERO,amount,cell.id)
	for organ in cell.organs:
		var kind: int = {"feeding":ENZYME,"neutralizing":ANTITOXIN,"acidifying":ACID,"regenerative":BUFFER}.get(organ.kind,-1)
		var energy_cost := 0.15*Genes.factor(organ,"secretion_cost")
		if kind < 0 or cell.biomass < 0.06 or cell.energy < energy_cost: continue
		if kind != ENZYME and cell.energy < 12: continue
		var rate := 0.35 if kind == ENZYME else 2.0
		if not chance(rate*organ.scale*organ.scale*Genes.factor(organ,"secretion"),dt): continue
		# Query only on a scheduled secretion attempt, rather than every tick.
		if not _secretion_needed(cell,organ,kind): continue
		cell.biomass -= 0.06
		cell.spend_energy(energy_cost,organ)
		var direction: Vector2 = cell.local_point(organ.a).normalized().rotated(cell.angle)
		spawn_particle(kind,cell.organ_position(organ)+direction*10,direction*18*Genes.factor(organ,"dispersal"),0.06,cell.id)
		particles[-1].capacity = 0.25 if kind in [ACID,BUFFER] else 0.06
		organ.charge_flash = 1
		if cell == player and kind == ACID: evolution.record("acid",0.06)
	# Cellular stress also releases a material-bearing toxic byproduct.
	if cell.health < 90 and cell.biomass > 0.08 and chance(0.6,dt):
		cell.biomass -= 0.08
		var direction := Vector2.from_angle(rng.randf()*TAU)
		spawn_particle(TOXIN,cell.position+direction*(cell.radius+12),direction*24,0.08,cell.id)

	for organ in cell.organs:
		if organ.kind != "toxin": continue
		organ["burst_clock"] = maxf(0,float(organ.get("burst_clock",0))-dt)
		if organ.burst_clock > 0 or cell.target_id < 0 or cell.threat.length_squared() < 0.01: continue
		var burst: float = organ.scale*organ.scale*Genes.factor(organ,"burst")
		if cell.energy < maxf(12,2*burst) or cell.biomass < 0.18*burst: continue
		spawn_particle(DECOY,cell.organ_position(organ),cell.threat*145,0.03*burst,cell.id)
		spawn_particle(TOXIN,cell.organ_position(organ),cell.threat*170,0.15*burst,cell.id)
		cell.spend_energy(2*burst,organ)
		cell.biomass -= 0.18*burst
		organ.consume_flash = 1
		organ.burst_clock = 0.75*Genes.factor(organ,"cooldown")

func _motion(dt: float) -> void:
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		var local_dt: float = dt*cell.activity
		var previous: Vector2 = cell.position
		var steering_power := 0.0
		for organ in cell.organs:
			if cell.energy <= 0: continue
			var pursuing: bool = organ.id == cell.target_organ_id and cell.target_mode in ["hunt","light"]
			if organ.kind != "propulsion" and not pursuing: continue
			var arm: Vector2 = cell.organ_position(organ)-cell.position
			var power: float = (2600.0 if organ.kind == "propulsion" else 1100.0)*organ.scale*organ.scale*(organ.hp/organ.max_hp)*Genes.factor(organ,"thrust")
			var energy_cost: float = local_dt*0.3*organ.scale*organ.scale*Genes.factor(organ,"motion_cost")
			power *= minf(1,cell.energy/maxf(0.000001,energy_cost))
			var impulse: Vector2 = cell.target.normalized()*power*local_dt
			if fluid.deposit(cell.position+arm,-impulse):
				cell.velocity += impulse/cell.mass
				cell.angular_velocity += arm.cross(impulse)/cell.inertia
				steering_power += power
				cell.spend_energy(energy_cost,organ)
		# Flagella can reverse their stroke to retreat while the receptor remains
		# facing the threat. A paired steering impulse also acts on the medium.
		if steering_power > 0:
			var error := wrapf(cell.facing.angle()-cell.target_mouth-cell.angle,-PI,PI)
			var torque := clampf(cell.inertia*(error*12-cell.angular_velocity*7),-steering_power*cell.radius,steering_power*cell.radius)
			var arm: Vector2 = Vector2.from_angle(cell.angle)*cell.radius*0.8
			if fluid.can_couple(cell.position+arm) and fluid.can_couple(cell.position-arm):
				var impulse: Vector2 = arm.orthogonal().normalized()*torque*local_dt/(2*arm.length())
				fluid.deposit(cell.position+arm,-impulse)
				fluid.deposit(cell.position-arm,impulse)
				cell.angular_velocity += torque*local_dt/cell.inertia
		for i in 6:
			var arm = Vector2.from_angle(TAU*i/6.0+cell.angle)*cell.radius
			fluid.exchange(cell,arm,local_dt,15.0)
		cell.angle = wrapf(cell.angle+cell.angular_velocity*local_dt,-PI,PI)
		var plant_contact: Array = habitat_geometry.move(previous,Medium.wrap_position(previous+cell.velocity*local_dt),cell.velocity,cell.extent())
		cell.position = plant_contact[0]
		cell.velocity = plant_contact[1]
		# Continuous sweep against other bodies catches high-speed crossings.
		for other in cells:
			if other == cell or other.dead: continue
			var start = Medium.offset(other.position,previous)
			var travel = Medium.offset(previous,cell.position)
			if start.length() > (cell.extent()+other.extent())+travel.length(): continue
			var distance: float = cell.support((-start).angle())+other.support(start.angle())
			if start.length() < distance-0.2 or travel.length_squared() < 0.00001: continue
			var t = clampf(-start.dot(travel)/travel.length_squared(),0,1)
			if (start+travel*t).length() < distance:
				var a = travel.length_squared()
				var b = 2*start.dot(travel)
				var c = start.length_squared()-distance*distance
				var hit = (-b-sqrt(maxf(0,b*b-4*a*c)))/(2*a)
				if hit >= 0 and hit <= 1: cell.position = Medium.wrap_position(previous+travel*hit)

func _contacts(_dt: float) -> void:
	for iteration in 5:
		for i in cells.size():
			var a = cells[i]
			if a.dead: continue
			for j in range(i+1,cells.size()):
				var b = cells[j]
				if b.dead or (a.activity <= 0 and b.activity <= 0): continue
				var delta = Medium.offset(a.position,b.position)
				if delta.length() > (a.extent()+b.extent()): continue
				var normal = delta.normalized() if delta.length() > 0.001 else Vector2.RIGHT
				var required: float = a.support(normal.angle())+b.support((-normal).angle())
				var penetration = required-delta.length()
				if penetration < -0.1: continue
				var ia: float = a.activity/a.mass
				var ib: float = b.activity/b.mass
				var inverse_mass = ia+ib
				if inverse_mass <= 0: continue
				if penetration > 0:
					a.position = Medium.wrap_position(a.position-normal*penetration*ia/inverse_mass)
					b.position = Medium.wrap_position(b.position+normal*penetration*ib/inverse_mass)
				var closing: float = (b.velocity-a.velocity).dot(normal)
				if closing < 0:
					var impulse = normal*(-closing*1.05/inverse_mass)
					a.velocity -= impulse*ia
					b.velocity += impulse*ib
				if iteration == 0 and penetration > 0:
					for body in [a,b]:
						if body.activity <= 0: continue
						var n = normal if body == a else -normal
						var k = posmod(roundi(fposmod(n.angle()-body.angle,TAU)/TAU*body.membrane.COUNT),body.membrane.COUNT)
						body.membrane.points[k] *= 0.96
						body.membrane.invalidate()

func _spike_contacts(dt: float) -> void:
	for attacker in cells:
		if attacker.dead or attacker.activity <= 0 or attacker.health <= 0: continue
		attacker.feeding_feedback = ""
		for organ in attacker.organs:
			if organ.kind != "offensive": continue
			organ.feeding = false
			var base: Vector2 = attacker.organ_position(organ)
			var direction: Vector2 = attacker.local_point(organ.a).normalized().rotated(attacker.angle)
			var length: float = 42.0*organ.scale
			for prey in cells:
				if prey == attacker or prey.dead or prey.activity <= 0 or prey.health <= 0 or prey.lineage_id() == attacker.lineage_id(): continue
				var d := Medium.offset(base,prey.position)
				var along := clampf(d.dot(direction),0,length)
				var contact: Vector2 = base+direction*along
				var offset := Medium.offset(prey.position,contact)
				if offset.length() > prey.support(offset.angle())+3*organ.scale: continue
				var local_dt := dt*minf(attacker.activity,prey.activity)
				var energy: float = attacker.spend_energy(local_dt*1.2*organ.scale*organ.scale*Genes.factor(organ,"attack_cost"),organ)
				if energy <= 0: continue
				prey.waste += prey.damage(energy*12*Genes.factor(organ,"damage"),offset.angle())
				if attacker == player: evolution.record("spike",energy*12*Genes.factor(organ,"damage"))
				organ.feeding = true
				organ.consume_flash = 1
				organ.link = contact
				attacker.feeding_feedback = "SPIKE CONTACT"
				break

func _exclude_particles() -> void:
	if native_exclusion:
		kernels.exclude(particles,local_particle_ids(),cells,player.position if camera_follows_player else camera_position,view_half)
		grid.rebuild(particles)
		return
	if spatial_queries: cell_index.rebuild(cells)
	# Deliberate visual/gameplay projection: external packets never hide inside
	# cytoplasm. Preserve material, and move bucket/interpolation history too.
	for index in local_particle_ids():
		var p: Dictionary = particles[index]
		if not p.alive or activity_at(p.p) <= 0: continue
		for iteration in 3:
			var moved := false
			for cell_id in cell_index.at(p.p) if spatial_queries else range(cells.size()):
				var cell = cells[cell_id]
				if cell.dead or cell.activity <= 0: continue
				var offset := Medium.offset(cell.position,p.p)
				if offset.length_squared() > pow(cell.extent()+8,2): continue
				var angle := offset.angle() if offset.length_squared() > 0.0001 else index*2.4
				var edge: float = cell.visible_support(angle-cell.angle)+7
				if offset.length() >= edge-0.001: continue
				var before: Vector2 = p.p
				p.p = Medium.wrap_position(cell.position+Vector2.from_angle(angle)*edge)
				p.previous = p.p
				grid.move(index,before,p.p)
				moved = true
			if not moved: break

func _clear_receptors(cell, dt: float) -> void:
	for organ in cell.organs:
		if organ.blocked <= 0: continue
		# Basal unbinding never needs energy. ATP-funded cleaning and repair
		# bodies speed recovery; occupation cannot become a permanent disable.
		organ.blocked = maxf(0,organ.blocked-dt*0.045)
		var cleared: float = minf(organ.blocked,dt*0.18*(1+cell.count("regenerative")*1.5))
		var energy: float = cell.spend_energy(cleared*1.2,organ)
		organ.blocked = maxf(0,organ.blocked-energy/1.2)

func _receptor_contacts() -> void:
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		for organ in cell.organs:
			if organ.kind not in ["feeding","sensing","offensive"]: continue
			var at: Vector2 = cell.organ_position(organ)
			var forward: Vector2 = cell.local_point(organ.a).normalized().rotated(cell.angle)
			var radius: float = 12*organ.scale
			for index in grid.query(at,radius+6):
				var p: Dictionary = particles[index]
				if not p.alive or p.kind != DECOY or inherited_lineages.get(p.owner,p.owner) == cell.lineage_id() or activity_at(p.p) <= 0: continue
				var delta := Medium.offset(at,p.p)
				if delta.length() > radius+particle_radius(p.kind)*particle_scale(p.amount): continue
				var normal := delta.normalized()
				if forward.dot(normal) < 0.25 or p.direction.dot(-normal) < 0.5: continue
				organ.blocked = minf(1,organ.blocked+0.65)
				cell.waste += p.amount
				p.alive = false
				cell.render_revision += 1

func _toxin_contacts() -> void:
	if spatial_queries: cell_index.rebuild(cells)
	for index in local_particle_ids():
		var p: Dictionary = particles[index]
		if not p.alive or p.kind != TOXIN or activity_at(p.p) <= 0: continue
		for cell_id in cell_index.at(p.p) if spatial_queries else range(cells.size()):
			var cell = cells[cell_id]
			if cell.dead or cell.activity <= 0 or cell.lineage_id() == inherited_lineages.get(p.owner,p.owner): continue
			var d = Medium.offset(cell.position,p.p)
			if d.length() <= cell.support(d.angle())+5:
				cell.waste += cell.damage(p.amount*75,d.angle()) + p.amount
				if p.owner == player.id: evolution.record("toxin",p.amount*75)
				p.alive = false
				break

func _die(cell, transferred: float = 0.0) -> void:
	if cell.dead: return
	cell.dead = true
	cell.health = 0
	var total: float = maxf(0,cell.organic_mass()-transferred)
	var count := maxi(24,ceili(total/0.4))
	for i in count:
		var direction = Vector2.from_angle(TAU*i/count)
		spawn_particle(NUTRIENT,cell.position+direction*cell.radius*0.9,direction*24,total/count,cell.id)
	var oxygen: float = maxf(0,cell.oxygen)
	cell.oxygen = 0
	# Retained dissolved resource is released, never manufactured on death.
	var oxygen_packets := ceili(oxygen/0.4)
	for i in oxygen_packets:
		var direction := Vector2.from_angle(TAU*(i+0.5)/oxygen_packets)
		spawn_particle(OXYGEN,cell.position+direction*cell.radius*0.9,direction*24,oxygen/oxygen_packets,cell.id)
	events.append({"time":time,"type":"death","id":cell.id,"released":total,"oxygen_released":oxygen})
	if cell == player: return
	if cell.role == "ancestor":
		cells.erase(cell)
		return
	kills += 1
	cells.erase(cell)
	pending_replacements.append({"role":cell.role,"id":cell.id})
	_replace_population()

func _replace_population() -> void:
	# At wide microscope zoom there may be no hidden space. Defer the explicit
	# replacement trigger until a full organism can fit outside the view.
	for pending in pending_replacements.duplicate():
		if time < float(pending.get("not_before",0)): continue
		if evolution.enabled and evolution.clock < float(pending.get("not_before",0)): continue
		var at := Vector2.ZERO
		var found := false
		for attempt in 24:
			at = Medium.wrap_position(player.position+Vector2.from_angle(rng.randf()*TAU)*1100)
			if attempt > 0: at = Vector2(rng.randf()*WORLD.x,rng.randf()*WORLD.y)
			var hidden := Medium.visibility(at,player.position if camera_follows_player else camera_position,view_half+Vector2.ONE*160) <= 0
			var announced: bool = evolution.enabled and evolution.arrival_budget > 0 and evolution.clock >= evolution.resistance_clock and Medium.offset(player.position,at).length() > 700+player.extent()
			if safe_birth_position(at,160) and (hidden or announced):
				found = true
				break
		if not found: continue
		var role: String = pending.role
		if evolution.enabled and evolution.tide == 1: role = "grazer"
		elif evolution.enabled and evolution.tide >= 2 and evolution.newcomer_count%2 == 0: role = "hunter"
		var replacement = _make_cell(at,role)
		evolution.newcomer(replacement,self)
		evolution.arrival_budget = maxi(0,evolution.arrival_budget-1)
		external_input += replacement.organic_mass()
		events.append({"time":time,"type":"population_arrival" if pending.id < 0 else "population_replacement","id":replacement.id,"replaces":pending.id})
		pending_replacements.erase(pending)

func _build_debris(amount: float) -> void:
	if amount <= 0: return
	if build_original != null: build_waste += amount
	else: spawn_particle(WASTE,player.position,Vector2.ZERO,amount,player.id)

func begin_build() -> void:
	if build_original != null or player.dead or evolution.terminal(): return
	build_original = player
	build_state = {"points":evolution.points,"learned":evolution.learned.duplicate(),"chosen":evolution.chosen,"spending":evolution.spending.duplicate(true),"challenge":evolution.challenge,"challenge_mass":evolution.challenge_mass,"challenge_intake":evolution.challenge_intake,"stable_seconds":evolution.stable_seconds}
	var index := cells.find(player)
	player = Cell.clone_state(player)
	cells[index] = player
	build_waste = 0

func cancel_build() -> void:
	if build_original == null: return
	cells[cells.find(player)] = build_original
	player = build_original
	for key in build_state: evolution.set(key,build_state[key])
	build_original = null
	build_state.clear()
	build_waste = 0

func commit_build() -> void:
	if build_original == null: return
	build_original = null
	build_state.clear()
	_build_debris(build_waste)
	build_waste = 0

func undo_build() -> void:
	cancel_build()
	begin_build()

func resize_organ(identity: int, size: float) -> bool:
	var quote: Dictionary = player.resize_quote(identity,size)
	if quote.is_empty() or (evolution.enabled and evolution.points < quote.ap): return false
	var result: Dictionary = player.resize_organ(identity,size)
	if result.is_empty(): return false
	evolution.spend(result.ap,"Enlarge organ")
	_build_debris(result.debris)
	return true

func mutate_organ(identity: int, gene: String) -> bool:
	var organ: Dictionary = player.organ_by_id(identity)
	if gene not in evolution.learned or organ.is_empty(): return false
	var cost := Genes.adaptation_price(organ)
	if evolution.enabled and evolution.points < cost: return false
	if not player.specialize(identity,gene): return false
	evolution.spend(cost,"Apply "+gene)
	return true

func offspring_quote() -> Dictionary:
	var tissue := 0.0
	for organ in player.organs: tissue += organ.get("max_material",Cell.organ_cost(organ.kind,organ.scale))
	var radius := maxf(34,player.occupied()/(TAU*0.8))
	var body := maxf(30,pow(radius/47.0,3)*78-12)
	var inherited_body := minf(body,maxf(0,player.body-30))
	return {"body":body,"body_transfer":inherited_body,"biomass":12.0,"material":body+12+6+8+tissue-inherited_body,"total_material":body+12+6+8+tissue,"energy":60.0,"oxygen":12.0}

func safe_birth_position(at: Vector2, radius: float) -> bool:
	if not habitat_geometry.clear_at(at,radius): return false
	for cell in cells:
		if not cell.dead and Medium.offset(cell.position,at).length() < cell.extent()+radius+20: return false
	return true

func divide_lineage() -> bool:
	if evolution.offspring_id >= 0 or player.dead: return false
	var quote := offspring_quote()
	if player.brood_mass+0.000001 < quote.material or player.brood_energy < quote.energy: return false
	if player.count("feeding")+player.count("photosynthesis") == 0: return false
	var child = Cell.new(next_id)
	child.role = "player"
	child.lineage = player.lineage_id()
	child.body = quote.body
	child.biomass = quote.biomass
	child.substrate = 6
	child.carbon = 8
	child.oxygen = minf(player.oxygen,quote.oxygen)
	child.energy = 40
	child.organs = player.organs.duplicate(true)
	child.next_organ_id = player.next_organ_id
	for organ in child.organs:
		organ.hp = organ.max_hp
		organ.material = organ.max_material
		organ.blocked = 0
		organ.target_id = -1
		organ.burst_clock = 0.0
		organ.feeding = false
		organ.link = Vector2.ZERO
		organ.consume_flash = 0.0
		organ.consume_clock = 0.0
		organ.charge_flash = 0.0
		organ.consumed_total = 0.0
	child.update_geometry()
	child.membrane = Cell.Membrane.new(child.radius)
	child.membrane.skeleton = Cell.clone_state(player.membrane.skeleton)
	child.membrane.skeleton.begin(child.radius)
	var found := false
	for i in 32:
		child.position = Medium.wrap_position(player.position+Vector2.from_angle(player.angle+TAU*i/32)*(player.extent()+child.extent()+45))
		if safe_birth_position(child.position,child.extent()):
			found = true
			break
	if not found: return false
	player.brood_mass -= quote.material
	player.body -= quote.body_transfer
	player.brood_energy -= quote.energy
	player.oxygen -= child.oxygen
	player.role = "ancestor"
	player.update_geometry()
	child.previous_position = child.position
	child.angle = player.angle
	child.previous_angle = child.angle
	cells.append(child)
	inherited_lineages[child.id] = child.lineage_id()
	player = child
	next_id += 1
	evolution.offspring_id = child.id
	events.append({"type":"division","id":child.id,"time":time,"material":quote.total_material,"reserve_used":quote.material,"body_transferred":quote.body_transfer,"oxygen_transferred":child.oxygen,"atp_used":20})
	return true
