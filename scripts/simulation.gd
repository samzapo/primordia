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
var food_sources: Array[Vector2] = []

func _init(seed_number: int = 20261004, profile: int = 0) -> void:
	seed_value = seed_number
	rng.seed = seed_number
	habitat = clampi(profile,0,2)
	player.role = "player"
	player.add_organ("feeding",0,"graze",false)
	player.add_organ("sensing",1.15,"graze",false)
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
	fluid.set_camera(player.position)

func _make_cell(p: Vector2, role: String):
	var cell = Cell.new(next_id,p)
	next_id += 1
	cell.role = role
	cell.angle = rng.randf()*TAU
	cell.body = 135.0 if role == "hunter" else rng.randf_range(14,32)
	cell.biomass = 35 if role == "hunter" else 10
	cell.update_geometry()
	cell.membrane = Cell.Membrane.new(cell.radius)
	cell.add_organ("feeding",0,"engulf" if role == "hunter" else "graze",false)
	cell.add_organ("sensing",1.25,"graze",false)
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
	cells.append(cell)
	return cell

func screen_position(p: Vector2) -> Vector2:
	return VIEW*0.5+Medium.offset(player.position,p)

func install(kind: String, local_angle: float, mode: String = "graze") -> bool:
	return player.add_organ(kind,local_angle,mode)

func remove(index: int) -> bool:
	var debris: float = player.recycle(index)
	if debris < 0: return false
	spawn_particle(WASTE,player.position,Vector2.ZERO,debris)
	return true

func spawn_particle(kind: int, p: Vector2, v: Vector2 = Vector2.ZERO, amount: float = 1.0, owner: int = -1, source_radius: float = 0.0) -> void:
	if amount <= 0: return
	var life = -1.0
	if kind == DANGER: life = 3.0
	if kind == TOXIN: life = 2.8
	particles.append({"kind":kind,"p":Medium.wrap_position(p),"v":v,"amount":amount,"life":life,"age":0.0,"alive":true,"owner":owner,"source_radius":source_radius})

func _emit_material(kind: int, at: Vector2, amount: float, motion: Vector2 = Vector2.ZERO) -> void:
	for index in grid.query(at,18):
		if index >= particles.size(): continue
		var p: Dictionary = particles[index]
		if p.alive and p.kind == kind and p.amount < 3 and Medium.visibility(p.p,player.position) > 0 and Medium.offset(at,p.p).length() < 18:
			p.v = (p.v*p.amount+motion*amount)/(p.amount+amount)
			p.amount += amount
			return
	spawn_particle(kind,at,motion,amount)

func step(dt: float) -> void:
	if player.dead: return
	time += dt
	fluid.set_camera(player.position)
	fluid.step(dt)
	active_cells = 0
	for cell in cells:
		cell.activity = Medium.visibility(cell.position,player.position)
		if cell.activity > 0 and not cell.dead:
			active_cells += 1
			var local_dt: float = dt*cell.activity
			cell.age += local_dt
			cell.hurt_flash = maxf(0,cell.hurt_flash-local_dt*2)
			cell.reaction_flash = maxf(0,cell.reaction_flash-local_dt*2)
	_move_particles(dt)
	grid.rebuild(particles)
	_chemistry(dt)
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		var local_dt: float = dt*cell.activity
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
		cell.drift_organs(local_dt,(fluid.sample(cell.position)-cell.velocity).rotated(-cell.angle))
		# Shrinkage can shed crowded organs, releasing their remaining material.
		while cell.occupied() > cell.perimeter() and not cell.organs.is_empty():
			var organ: Dictionary = cell.organs.pop_back()
			spawn_particle(WASTE,cell.organ_position(organ),Vector2.ZERO,organ.material)
		cell.membrane.step(local_dt,cell.radius,Vector2.ZERO,cell.age,cell.aspect)
		_emit_and_attack(cell,local_dt)
	# Short motion substeps plus swept contacts avoid crossing from one side to the other.
	for substep in 3:
		_motion(dt/3.0)
		_contacts(dt/3.0)
	_intercell_feeding(dt)
	_toxin_contacts()
	for cell in cells.duplicate():
		if cell.activity > 0 and cell.health <= 0 and not cell.dead: _die(cell)
	particles = particles.filter(func(p): return p.alive)
	spawn_clock += dt
	if spawn_clock >= 0.5:
		spawn_clock -= 0.5
		grid.rebuild(particles)
		_replenish()
	won = player.processed >= 40 and time+0.000001 >= 90

func _move_particles(dt: float) -> void:
	active_particles = 0
	for particle in particles:
		if not particle.alive: continue
		var scale = Medium.visibility(particle.p,player.position)
		if scale <= 0: continue
		active_particles += 1
		var step_dt = dt*scale
		particle.p = Medium.wrap_position(particle.p+(particle.v+fluid.sample(particle.p))*step_dt)
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
	for waste in particles:
		if not waste.alive or waste.kind != WASTE or waste.age < 0.8: continue
		var local_dt = dt*Medium.visibility(waste.p,player.position)
		if local_dt <= 0: continue
		for index in grid.query(waste.p,34):
			var oxygen: Dictionary = particles[index]
			if not oxygen.alive or oxygen.kind != OXYGEN or Medium.offset(waste.p,oxygen.p).length() > 34: continue
			if Medium.visibility(oxygen.p,player.position) <= 0: continue
			var amount = minf(minf(waste.amount,oxygen.amount),minf(local_dt,dt*Medium.visibility(oxygen.p,player.position))*1.2)
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

func _sense(cell, dt: float) -> void:
	cell.sense_clock -= dt
	if cell.sense_clock <= 0:
		cell.sense_clock = 0.22
		cell.sensed = false
		for organ in cell.organs:
			if organ.kind != "sensing": continue
			var food = Vector2.ZERO
			var fear = Vector2.ZERO
			var attack = Vector2.ZERO
			var receptor: Vector2 = cell.organ_position(organ)
			for index in grid.query(receptor,190):
				var p: Dictionary = particles[index]
				if not p.alive or p.owner == cell.id: continue
				var d = Medium.offset(receptor,p.p)
				if d.length() > 190: continue
				if p.kind == NUTRIENT and cell.has_mode("graze"):
					food += Medium.offset(cell.position,p.p).normalized()*p.amount/maxf(25,d.length())
				elif p.kind == DANGER:
					var toward = Medium.offset(cell.position,p.p).normalized()
					if (cell.has_mode("parasite") and p.source_radius > cell.radius*1.12) or (cell.has_mode("engulf") and p.source_radius < cell.radius*0.78):
						food += toward*0.06
						attack = toward
					elif p.source_radius > cell.radius*1.12:
						fear -= toward*0.07
						attack = toward
			var vector = fear if fear.length() > 0.01 else food
			if vector.length() > 0.001:
				cell.sensed = true
				cell.signals.append({"p":cell.local_point(organ.a)*0.82,"direction":vector.normalized(),"fear":fear.length()>0.01,"attack":attack})
	# Signals are particles transported to an internal relay; arrival triggers behavior.
	for packet in cell.signals:
		packet.p = packet.p.move_toward(Vector2.ZERO,dt*140)
		if packet.p.length() < 5:
			cell.target = packet.direction
			cell.threat = packet.attack
			cell.state = "EVADING" if packet.fear else ("SEEKING HOST" if cell.has_mode("parasite") else "SEEKING FOOD")
	cell.signals = cell.signals.filter(func(s): return s.p.length() >= 5)
	if not cell.sensed and cell.signals.is_empty():
		cell.target = Vector2.from_angle(cell.angle + sin(cell.age*0.4+cell.id)*0.6)
		cell.state = "EXPLORING"
		cell.threat = Vector2.ZERO
	if cell.count("propulsion") == 0: cell.state = "DRIFTING"

func _feed(cell) -> void:
	for organ in cell.organs:
		if organ.kind != "feeding" or organ.mode != "graze": continue
		var mouth: Vector2 = cell.organ_position(organ)
		for index in grid.query(mouth,30):
			var p: Dictionary = particles[index]
			if not p.alive or p.kind != NUTRIENT or Medium.visibility(p.p,player.position) <= 0: continue
			if Medium.offset(mouth,p.p).length() <= 30:
				var amount = minf(p.amount,maxf(0,24-cell.substrate))
				p.amount -= amount
				cell.substrate += amount
				cell.eaten += amount
				if amount > 0: cell.reaction_flash = 1.0
				if p.amount <= 0.000001: p.alive = false
	for index in grid.query(cell.position,cell.radius*cell.aspect+12):
		var p: Dictionary = particles[index]
		if p.alive and p.kind == OXYGEN and Medium.visibility(p.p,player.position) > 0 and Medium.offset(cell.position,p.p).length() < cell.radius+12:
			var amount = minf(p.amount,maxf(0,30-cell.oxygen))
			cell.oxygen += amount
			p.amount -= amount
			if p.amount <= 0.000001: p.alive = false

func _metabolize(cell, dt: float) -> void:
	var amount = minf(minf(cell.substrate,cell.oxygen),dt*1.8)
	cell.substrate -= amount
	cell.oxygen -= amount
	cell.energy = minf(100,cell.energy+amount*5.0)
	cell.biomass += amount*0.8
	cell.waste += amount*0.2
	cell.processed += amount
	cell.energy = maxf(0,cell.energy-dt*(0.16+cell.mass*0.001))
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
		cell.energy -= 2
		cell.biomass -= 0.15
	cell.attack_clock = 0.75

func _motion(dt: float) -> void:
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		var local_dt: float = dt*cell.activity
		var previous: Vector2 = cell.position
		var steering = clampf(wrapf(cell.target.angle()-cell.angle,-PI,PI),-1,1)
		for organ in cell.organs:
			if organ.kind != "propulsion" or cell.energy <= 0: continue
			var arm: Vector2 = (cell.organ_position(organ)-cell.position)
			var direction = -Vector2.from_angle(cell.angle+organ.a).rotated(-steering*0.85)
			var impulse = direction*2600.0*local_dt*(organ.hp/organ.max_hp)
			if fluid.deposit(cell.position+arm,-impulse):
				cell.velocity += impulse/cell.mass
				cell.angular_velocity += arm.cross(impulse)/cell.inertia
				cell.energy = maxf(0,cell.energy-local_dt*0.3)
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
			if start.length() > (cell.radius+other.radius)*1.4+travel.length(): continue
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
				if delta.length() > (a.radius+b.radius)*1.35: continue
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

func _intercell_feeding(dt: float) -> void:
	for eater in cells.duplicate():
		if eater.dead or eater.health <= 0 or eater.activity <= 0: continue
		for organ in eater.organs:
			if organ.kind != "feeding" or organ.mode == "graze": continue
			var mouth: Vector2 = eater.organ_position(organ)
			for prey in cells.duplicate():
				if prey == eater or prey.dead or prey.activity <= 0 or prey.health <= 0: continue
				var separation = Medium.offset(mouth,prey.position)
				var reach = 44.0 if organ.mode == "parasite" else 20.0
				if separation.length() > prey.support((-separation).angle())+reach: continue
				var local_dt = dt*minf(eater.activity,prey.activity)
				if organ.mode == "parasite" and prey.radius > eater.radius*1.12 and eater.substrate < 24:
					# A proboscis must first puncture the local organelle/membrane.
					var damage: float = prey.damage(local_dt*5,(-separation).angle())
					prey.waste += damage
					if prey.holes.is_empty(): continue
					var amount: float = prey.drain(minf(2.8*local_dt,24-eater.substrate))
					eater.substrate += amount
					eater.stolen += amount
					eater.reaction_flash = 1.0
					eater.state = "PARASITIZING"
				elif organ.mode == "engulf" and eater.radius > prey.radius*1.35:
					var released: float = prey.damage(45*local_dt,(-separation).angle())
					prey.waste += released
					if prey.health <= 0:
						var taken: float = minf(24-eater.substrate,prey.organic_mass())
						# Transfer whole prey: portion to gut, remainder to environmental debris.
						eater.substrate += taken
						eater.engulfed += 1
						eater.eaten += taken
						_die(prey,taken)

func _toxin_contacts() -> void:
	for p in particles:
		if not p.alive or p.kind != TOXIN or Medium.visibility(p.p,player.position) <= 0: continue
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
		spawn_particle(NUTRIENT,cell.position+direction*cell.radius*0.65,direction*16,total/24)
	events.append({"time":time,"type":"death","id":cell.id,"released":total})
	if cell == player: return
	kills += 1
	cells.erase(cell)
	var at = Medium.wrap_position(player.position+Vector2.from_angle(rng.randf()*TAU)*1100)
	var replacement = _make_cell(at,cell.role)
	external_input += replacement.organic_mass()
	events.append({"time":time,"type":"population_replacement","id":replacement.id,"replaces":cell.id})

func _replenish() -> void:
	# Photosynthetic/external habitat input; frozen regions receive no ordinary spawns.
	for source in food_sources:
		if Medium.visibility(source,player.position) < 0.45: continue
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
