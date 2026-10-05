extends RefCounted
## Authoritative fixed-step ecology, independent of input and scene nodes.
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
const HABITATS := ["BALANCED TIDE", "LEAN HUNTING GROUNDS", "RICH / ARMORED HUNTERS"]
var rng := RandomNumberGenerator.new()
var grid = Grid.new()
var fluid = Medium.new()
var player = Cell.new(0,Vector2(2048,1280))
var cells: Array = []
var particles: Array = []
var events: Array = []
var pending_replacements: Array = []
var next_id := 1
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
var food_sources: Array[Vector2] = []

func _init(seed_number: int = 20261004, profile: int = 0) -> void:
	seed_value = seed_number
	rng.seed = seed_number
	habitat = clampi(profile,0,2)
	player.role = "player"
	player.add_organ("feeding",0,"graze",false)
	player.add_organ("propulsion",PI,"graze",false)
	cells.append(player)
	# Whole habitats are stored. Only organisms inside the microscope advance.
	for i in 18:
		var p = player.position + Vector2.from_angle(i*2.4)* (220 if i == 0 else 340+i*94)
		_make_cell(Medium.wrap_position(p), "hunter" if i%5 == 3 else "grazer")
	for i in 28:
		food_sources.append(Medium.wrap_position(player.position + Vector2.from_angle(i*2.4)*(120+i*75)))
	for i in (900 if habitat != 1 else 260):
		var source: Vector2 = food_sources[i%food_sources.size()]
		spawn_particle(NUTRIENT,source+Vector2(rng.randfn(0,44),rng.randfn(0,35)))
	for i in 1900:
		spawn_particle(OXYGEN,Vector2(rng.randf()*WORLD.x,rng.randf()*WORLD.y))
	# A breathing and feeding patch at the initial observation site.
	for i in 75:
		spawn_particle(OXYGEN,player.position+Vector2(rng.randfn(0,180),rng.randfn(0,130)))
	for i in (60 if habitat != 1 else 12):
		spawn_particle(NUTRIENT,player.position+Vector2(rng.randf_range(40,140),rng.randfn(0,36)))
	grid.rebuild(particles)
	fluid.set_camera(player.position,view_half)

func _make_cell(p: Vector2, role: String):
	var cell = Cell.new(next_id,p)
	next_id += 1
	cell.role = role
	cell.angle = rng.randf()*TAU
	cell.body = 135.0 if role == "hunter" else rng.randf_range(14,32)
	cell.biomass = 35 if role == "hunter" else 10
	cell.update_geometry()
	cell.membrane = Cell.Membrane.new(cell.radius)
	cell.add_organ("feeding",0,"engulf" if role == "hunter" else "graze",false,(2.2 if habitat == 2 else 1.7) if role == "hunter" else 1.0)
	cell.add_organ("propulsion",PI,"graze",false)
	if role == "hunter":
		cell.add_organ("offensive",-1.2,"graze",false)
		if habitat == 2:
			cell.biomass = 90
			cell.update_geometry()
			cell.membrane = Cell.Membrane.new(cell.radius)
			for a in [0.6,1.9,2.6,3.7,5.65]: cell.add_organ("protection",a,"graze",false)
			cell.add_organ("regenerative",4.4,"graze",false)
	cell.update_geometry()
	cell.previous_angle = cell.angle
	cells.append(cell)
	return cell

func screen_position(p: Vector2) -> Vector2:
	return view_half+Medium.offset(player.position,p)

func activity_at(p: Vector2) -> float:
	return Medium.visibility(p,player.position,view_half)

func local_particle_ids(margin: float = 0.0) -> Array[int]:
	if grid.source_size != particles.size(): grid.rebuild(particles)
	return grid.query_rect(player.position,view_half+Vector2.ONE*margin)

func cell_by_id(identity: int):
	for cell in cells:
		if cell.id == identity and not cell.dead: return cell
	return null

func install(kind: String, local_angle: float, mode: String = "graze", size: float = 1.0) -> bool:
	return player.add_organ(kind,local_angle,mode,true,size)

func remove(index: int) -> bool:
	var debris: float = player.recycle(index)
	if debris < 0: return false
	spawn_particle(WASTE,player.position,Vector2.ZERO,debris)
	return true

func spawn_particle(kind: int, p: Vector2, v: Vector2 = Vector2.ZERO, amount: float = 1.0, owner: int = -1, source_radius: float = 0.0) -> void:
	if amount <= 0: return
	if grid.source_size != particles.size(): grid.rebuild(particles)
	var life = -1.0
	if kind == DANGER: life = 3.0
	if kind == TOXIN: life = 2.8
	particles.append({"kind":kind,"p":Medium.wrap_position(p),"previous":Medium.wrap_position(p),"v":v,"amount":amount,"life":life,"age":0.0,"alive":true,"owner":owner,"source_radius":source_radius})
	grid.insert(particles.size()-1,particles[-1].p)

func _emit_material(kind: int, at: Vector2, amount: float, motion: Vector2 = Vector2.ZERO) -> void:
	for index in grid.query(at,18):
		if index >= particles.size(): continue
		var p: Dictionary = particles[index]
		if p.alive and p.kind == kind and p.amount < 3 and activity_at(p.p) > 0 and Medium.offset(at,p.p).length() < 18:
			p.v = (p.v*p.amount+motion*amount)/(p.amount+amount)
			p.amount += amount
			return
	spawn_particle(kind,at,motion,amount)

func step(dt: float) -> void:
	if player.dead: return
	time += dt
	revision += 1
	if grid.source_size != particles.size(): grid.rebuild(particles)
	var mark := Time.get_ticks_usec()
	fluid.set_camera(player.position,view_half)
	fluid.step(dt)
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
	_chemistry(dt)
	profile_usec["particles"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		var local_dt: float = dt*cell.activity
		cell.animate_resources(local_dt)
		_sense(cell,local_dt)
		_feed(cell)
		_metabolize(cell,local_dt)
		cell.heal(local_dt)
		for leak in cell.leaks:
			var normal := Vector2.from_angle(cell.angle+leak.a)
			_emit_material(NUTRIENT,cell.position+cell.local_point(leak.a).rotated(cell.angle)+normal*12,leak.amount,normal*12)
		# Tiny continuous emissions are aggregated into material-bearing packets.
		if cell.waste >= 0.5:
			spawn_particle(WASTE,cell.position-Vector2.from_angle(cell.angle)*cell.radius,Vector2.ZERO,cell.waste)
			cell.waste = 0
		cell.update_geometry()
		# Shrinkage can shed crowded organs, releasing their remaining material.
		while cell.occupied() > cell.perimeter() and not cell.organs.is_empty():
			var organ: Dictionary = cell.organs.pop_back()
			spawn_particle(WASTE,cell.organ_position(organ),Vector2.ZERO,organ.material)
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
		cell.shape_acceleration = ((cell.velocity-before_motion[cell.id])/dt).limit_length(600)
	profile_usec["motion"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	_intercell_feeding(dt)
	_toxin_contacts()
	_exclude_particles()
	for cell in cells.duplicate():
		if cell.activity > 0 and cell.health <= 0 and not cell.dead: _die(cell)
	spawn_clock += dt
	if spawn_clock >= 0.5:
		spawn_clock -= 0.5
		particles = particles.filter(func(p): return p.alive)
		grid.rebuild(particles)
		_replenish()
		_replace_population()
	profile_usec["ecology"] = Time.get_ticks_usec()-mark
	won = player.processed >= 40 and time+0.000001 >= 90

func _move_particles(dt: float) -> void:
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
		particle.p = Medium.wrap_position(particle.p+(particle.v+fluid.sample(particle.p))*step_dt)
		grid.move(index,particle.previous,particle.p)
		particle.v *= exp(-step_dt*0.8)
		particle.age += step_dt
		if particle.life >= 0:
			particle.life -= step_dt
			if particle.life <= 0:
				if particle.kind == TOXIN:
					particle.kind = WASTE
					particle.life = -1.0
				else: particle.alive = false

func _chemistry(dt: float) -> void:
	# Decomposition requires local oxygen. 0.6 recycled food + 0.4 respired loss.
	for particle_index in local_particle_ids():
		var waste: Dictionary = particles[particle_index]
		if not waste.alive or waste.kind != WASTE or waste.age < 0.8: continue
		var local_dt = dt*activity_at(waste.p)
		if local_dt <= 0: continue
		for index in grid.query(waste.p,34):
			var oxygen: Dictionary = particles[index]
			if not oxygen.alive or oxygen.kind != OXYGEN or Medium.offset(waste.p,oxygen.p).length() > 34: continue
			if activity_at(oxygen.p) <= 0: continue
			var amount = minf(minf(waste.amount,oxygen.amount),minf(local_dt,dt*activity_at(oxygen.p))*1.2)
			waste.amount -= amount
			oxygen.amount -= amount
			if oxygen.amount <= 0.000001: oxygen.alive = false
			if waste.amount <= 0.000001: waste.alive = false
			recycled += amount*0.6
			respiration_loss += amount*0.4
			# Accumulate products in a packet; do not create a particle per tick.
			if not waste.has("product"): waste.product = 0.0
			waste.product += amount*0.6
			if waste.product >= 0.4 or not waste.alive:
				spawn_particle(NUTRIENT,waste.p,Vector2.ZERO,waste.product)
				waste.product = 0.0
			break

func _suction(dt: float) -> void:
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		for organ in cell.organs:
			if organ.kind != "feeding" or cell.energy <= 0: continue
			var local_dt: float = dt*cell.activity
			var health: float = organ.hp/organ.max_hp
			fluid.suction(cell,cell.pore_center(organ),110*sqrt(organ.scale),24*organ.scale*health,local_dt)
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
			if organ.kind not in ["feeding","sensing"]: continue
			var mode: String = organ.mode
			var reach := 310.0*sqrt(organ.scale)
			var receptor: Vector2 = cell.organ_position(organ)
			var food := Vector2.ZERO
			for index in grid.query(receptor,reach):
				var p: Dictionary = particles[index]
				if not p.alive or p.owner == cell.id: continue
				var distance: float = Medium.offset(receptor,p.p).length()
				if distance > reach: continue
				if mode in ["graze","engulf"] and p.kind == NUTRIENT:
					food += Medium.offset(cell.position,p.p).normalized()*p.amount/maxf(25,distance)
				elif p.kind == DANGER and mode in ["engulf","parasite","flee"]:
					var prey = cell_by_id(p.owner)
					if prey == null: continue
					if mode == "engulf" and cell.pore_radius(organ) <= prey.radius*0.72: continue
					if mode == "parasite" and prey.radius <= cell.radius*1.05: continue
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
		cell.state = {"graze":"FORAGING","engulf":"PURSUING PREY","parasite":"SEEKING HOST","flee":"FLEEING"}.get(cell.target_mode,"EXPLORING")
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
		if organ.kind != "feeding" or organ.mode == "parasite": continue
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
				if amount > 0: cell.consumed(organ,amount)
				if p.amount <= 0.000001: p.alive = false
	for index in grid.query(cell.position,cell.extent()+12):
		var p: Dictionary = particles[index]
		if p.alive and p.kind == OXYGEN and activity_at(p.p) > 0 and Medium.offset(cell.position,p.p).length() < cell.support(Medium.offset(cell.position,p.p).angle())+14:
			var amount = minf(p.amount,maxf(0,cell.oxygen_capacity()-cell.oxygen))
			cell.oxygen += amount
			p.amount -= amount
			if p.amount <= 0.000001: p.alive = false

func _metabolize(cell, dt: float) -> void:
	var amount = minf(minf(cell.substrate,cell.oxygen),dt*1.8*cell.growth_scale())
	cell.substrate -= amount
	cell.oxygen -= amount
	cell.energy = minf(cell.energy_capacity(),cell.energy+amount*5.0)
	cell.biomass += amount*0.8
	cell.waste += amount*0.2
	cell.processed += amount
	cell.spend_energy(dt*0.264*cell.growth_scale())
	if cell.energy <= 0: cell.health = maxf(0,cell.health-dt*2)

func _emit_and_attack(cell, dt: float) -> void:
	cell.emission_clock += dt
	if cell.emission_clock >= 0.7:
		cell.emission_clock -= 0.7
		for i in 2:
			var direction = Vector2.from_angle(rng.randf()*TAU)
			spawn_particle(DANGER,cell.position+direction*cell.radius,direction*16,1,cell.id,cell.radius)
	cell.attack_clock -= dt
	if cell.attack_clock > 0 or not cell.sensed or cell.threat.length() < 0.01: return
	for organ in cell.organs:
		if organ.kind != "offensive" or cell.energy < 2 or cell.biomass < 0.15: continue
		var aim: Vector2 = cell.threat if cell.threat.length() > 0 else cell.target
		spawn_particle(TOXIN,cell.organ_position(organ),aim*170,0.15,cell.id)
		cell.spend_energy(2,organ)
		cell.biomass -= 0.15
	cell.attack_clock = 0.75

func _motion(dt: float) -> void:
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		var local_dt: float = dt*cell.activity
		var previous: Vector2 = cell.position
		var steering_power := 0.0
		for organ in cell.organs:
			if organ.kind != "propulsion" or cell.energy <= 0: continue
			var arm: Vector2 = cell.organ_position(organ)-cell.position
			var power: float = 2600.0*organ.scale*organ.scale*(organ.hp/organ.max_hp)
			var impulse: Vector2 = cell.target.normalized()*power*local_dt
			if fluid.deposit(cell.position+arm,-impulse):
				cell.velocity += impulse/cell.mass
				cell.angular_velocity += arm.cross(impulse)/cell.inertia
				steering_power += power
				cell.spend_energy(local_dt*0.3*organ.scale*organ.scale,organ)
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
		cell.position = Medium.wrap_position(cell.position+cell.velocity*local_dt)
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

static func polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size(): area += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(area)*0.5

func engulf_coverage(eater, organ: Dictionary, prey) -> float:
	var center: Vector2 = eater.pore_center(organ)
	var offset := Medium.offset(center,prey.position)
	var aperture_radius: float = eater.pore_radius(organ)
	if offset.length() > aperture_radius+prey.extent(): return 0.0
	var aperture := PackedVector2Array()
	for i in 48: aperture.append(Vector2.from_angle(TAU*i/48)*aperture_radius)
	var outline: PackedVector2Array = Transform2D(prey.angle,offset)*prey.membrane.outline()
	var covered := 0.0
	for intersection in Geometry2D.intersect_polygons(aperture,outline): covered += polygon_area(intersection)
	return clampf(covered/maxf(0.001,polygon_area(outline)),0,1)

func _intercell_feeding(dt: float) -> void:
	for eater in cells.duplicate():
		if eater.dead or eater.health <= 0 or eater.activity <= 0: continue
		eater.feeding_feedback = ""
		for organ in eater.organs:
			if organ.kind != "feeding" or organ.mode == "graze": continue
			organ.feeding = false
			organ.coverage = 0.0
			organ.feedback = "Seeking prey / grazing" if organ.mode == "engulf" else "Seeking a larger host"
			var mouth: Vector2 = eater.pore_center(organ)
			var touched := false
			for prey in cells.duplicate():
				if prey == eater or prey.dead or prey.activity <= 0 or prey.health <= 0: continue
				var separation := Medium.offset(mouth,prey.position)
				var reach: float = 52.0*organ.scale if organ.mode == "parasite" else eater.pore_radius(organ)
				if separation.length() > prey.extent()+reach: continue
				var surface: float = prey.support((-separation).angle())
				if separation.length() > surface+reach: continue
				if organ.mode == "parasite" and prey.radius <= eater.radius*1.05:
					organ.feedback = "Host must be larger than you"
					continue
				if organ.mode == "engulf":
					organ.coverage = engulf_coverage(eater,organ,prey)
					organ.feedback = "Coverage %d%% · needs more than 50%%" % roundi(organ.coverage*100)
					if organ.coverage <= 0.5: continue
				if eater.substrate >= eater.gut_capacity()-0.001:
					organ.feedback = "Gut full · digesting"
					continue
				if organ.target_id != prey.id: organ.progress = 0.0
				organ.target_id = prey.id
				organ.link = Medium.wrap_position(prey.position-separation.normalized()*surface)
				touched = true
				var local_dt := dt*minf(eater.activity,prey.activity)
				var relative: Vector2 = prey.velocity-eater.velocity
				var inverse_mass: float = 1.0/eater.mass+1.0/prey.mass
				var impulse := relative*(1-exp(-local_dt*4))/inverse_mass
				eater.velocity += impulse/eater.mass
				prey.velocity -= impulse/prey.mass
				var damage: float = prey.damage(local_dt*(16.0*organ.scale*organ.scale if organ.mode == "parasite" else 26.0),(-separation).angle())
				prey.waste += damage
				organ.feeding = true
				if organ.mode == "parasite":
					if not prey.punctured_at((-separation).angle()):
						organ.feedback = "Piercing local armor"
						break
					var amount: float = prey.drain(minf(3.5*organ.scale*organ.scale*local_dt,eater.gut_capacity()-eater.substrate))
					eater.substrate += amount
					eater.stolen += amount
					eater.consumed(organ,amount)
					organ.progress = minf(1,organ.progress+local_dt)
					organ.feedback = "Draining biomass"
				else:
					organ.progress = 1-prey.health/100
					organ.feedback = "Engulfing · %d%% covered" % roundi(organ.coverage*100)
					if prey.health <= 0:
						var taken: float = minf(eater.gut_capacity()-eater.substrate,prey.organic_mass())
						eater.substrate += taken
						eater.engulfed += 1
						eater.eaten += taken
						eater.consumed(organ,taken)
						_die(prey,taken)
				break
			if not touched:
				organ.progress = maxf(0,organ.progress-dt)
				organ.target_id = -1
			eater.feeding_feedback = organ.feedback

func _exclude_particles() -> void:
	# Deliberate visual/gameplay projection: external packets never hide inside
	# cytoplasm. Preserve material, and move bucket/interpolation history too.
	for index in local_particle_ids():
		var p: Dictionary = particles[index]
		if not p.alive or activity_at(p.p) <= 0: continue
		for iteration in 3:
			var moved := false
			for cell in cells:
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

func _toxin_contacts() -> void:
	for index in local_particle_ids():
		var p: Dictionary = particles[index]
		if not p.alive or p.kind != TOXIN or activity_at(p.p) <= 0: continue
		for cell in cells:
			if cell.dead or cell.activity <= 0 or cell.id == p.owner: continue
			var d = Medium.offset(cell.position,p.p)
			if d.length() <= cell.support(d.angle())+5:
				cell.waste += cell.damage(18,d.angle()) + p.amount
				p.alive = false
				break

func _die(cell, transferred: float = 0.0) -> void:
	if cell.dead: return
	cell.dead = true
	cell.health = 0
	var total: float = maxf(0,cell.organic_mass()-transferred)
	for i in 24:
		var direction = Vector2.from_angle(TAU*i/24)
		spawn_particle(NUTRIENT,cell.position+direction*cell.radius*0.65,direction*16,total/24,cell.id)
	events.append({"time":time,"type":"death","id":cell.id,"released":total})
	if cell == player: return
	kills += 1
	cells.erase(cell)
	pending_replacements.append({"role":cell.role,"id":cell.id})
	_replace_population()

func _replace_population() -> void:
	# At wide microscope zoom there may be no hidden space. Defer the explicit
	# replacement trigger until a full organism can fit outside the view.
	for pending in pending_replacements.duplicate():
		var at := Vector2.ZERO
		var found := false
		for attempt in 24:
			at = Medium.wrap_position(player.position+Vector2.from_angle(rng.randf()*TAU)*1100)
			if attempt > 0: at = Vector2(rng.randf()*WORLD.x,rng.randf()*WORLD.y)
			if Medium.visibility(at,player.position,view_half+Vector2.ONE*160) <= 0:
				found = true
				break
		if not found: continue
		var replacement = _make_cell(at,pending.role)
		external_input += replacement.organic_mass()
		events.append({"time":time,"type":"population_replacement","id":replacement.id,"replaces":pending.id})
		pending_replacements.erase(pending)

func _replenish() -> void:
	# Photosynthetic/external habitat input; frozen regions receive no ordinary spawns.
	for source in food_sources:
		if activity_at(source) < 0.45: continue
		var local_food = 0
		var local_oxygen = 0
		for index in grid.query(source,100):
			if index >= particles.size(): continue
			var p: Dictionary = particles[index]
			if p.alive and Medium.offset(source,p.p).length() < 100:
				if p.kind == NUTRIENT: local_food += 1
				if p.kind == OXYGEN: local_oxygen += 1
		var food_pulse := habitat != 1 or roundi(time*2)%8 == 0
		if food_pulse and local_food < (35 if habitat == 0 else (7 if habitat == 1 else 65)):
			spawn_particle(NUTRIENT,source+Vector2(rng.randfn(0,30),rng.randfn(0,30)))
			external_input += 1
		if local_oxygen < 30: spawn_particle(OXYGEN,source+Vector2(rng.randfn(0,55),rng.randfn(0,55)),Vector2.ZERO,2)
