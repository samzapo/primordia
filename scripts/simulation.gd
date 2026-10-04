extends RefCounted
## The authoritative world. It has no scene-tree, rendering, or input dependency.
const Grid = preload("res://scripts/spatial_grid.gd")
const Membrane = preload("res://scripts/membrane.gd")
const WORLD := Vector2(1016, 632)
const NUTRIENT := 0
const OXYGEN := 1
const WASTE := 2
const DANGER := 3
const TOXIN := 4
const KINDS := ["propulsion", "protection", "offensive", "regenerative", "feeding", "sensing"]
const COST := [8.0, 10.0, 12.0, 10.0, 8.0, 6.0]
var rng := RandomNumberGenerator.new()
var grid: Grid = Grid.new()
var particles: Array = []
var organs: Array[String] = ["feeding", "", "sensing", "", "propulsion", "", "", ""]
var position := Vector2(405, 325)
var velocity := Vector2.ZERO
var angle := -0.15
var angular_velocity := 0.0
var radius := 47.0
var membrane: Membrane = Membrane.new(radius)
var predator := Vector2(900, 490)
var predator_velocity := Vector2.ZERO
var predator_health := 100.0
var predator_radius := 57.0
var predator_stun := 0.0
var health := 100.0
var energy := 72.0
var biomass := 18.0
var substrate := 4.0
var oxygen := 16.0
var processed := 0.0
var eaten := 0
var time := 0.0
var reaction_flash := 0.0
var hurt_flash := 0.0
var bite_cooldown := 0.0
var emission_clock := 0.0
var attack_clock := 0.0
var spawn_clock := 0.0
var waste_clock := 0.0
var state := "EXPLORING"
var target_vector := Vector2.RIGHT
var sensor_active := false
var threat_detected := false
var threat_direction := Vector2.ZERO
var won := false
var reactions := 0.0
var food_sources := [Vector2(520, 265), Vector2(700, 420), Vector2(230, 170), Vector2(270, 490), Vector2(825, 160)]

func _init(seed_value: int = 20261004) -> void:
	rng.seed = seed_value
	for i in 180:
		spawn_particle(NUTRIENT, food_sources[i % food_sources.size()] + Vector2(rng.randfn(0, 42), rng.randfn(0, 38)))
	for i in 280:
		spawn_particle(OXYGEN, Vector2(rng.randf_range(15, WORLD.x - 15), rng.randf_range(15, WORLD.y - 15)))
	grid.rebuild(particles)

func count(kind: String) -> int:
	return organs.count(kind)

func slot_position(slot: int) -> Vector2:
	return position + Vector2.from_angle(angle + TAU * slot / 8.0) * (radius + 7)

func install(kind: String, slot: int) -> bool:
	var index := KINDS.find(kind)
	if index < 0 or slot < 0 or slot >= 8 or organs[slot] != "" or health <= 0:
		return false
	if biomass < COST[index]:
		return false
	biomass -= COST[index]
	organs[slot] = kind
	return true

func remove(slot: int) -> bool:
	if slot < 0 or slot >= 8 or organs[slot] == "" or health <= 0:
		return false
	biomass += COST[KINDS.find(organs[slot])] * 0.5
	organs[slot] = ""
	return true

func spawn_particle(kind: int, p: Vector2, v: Vector2 = Vector2.ZERO) -> void:
	var life := -1.0
	if kind == WASTE: life = 5.0
	if kind == DANGER: life = 4.0
	if kind == TOXIN: life = 2.8
	particles.append({"kind": kind, "p": p.clamp(Vector2(5, 5), WORLD - Vector2(5, 5)), "v": v, "life": life, "phase": rng.randf() * TAU, "alive": true})

func step(dt: float) -> void:
	if health <= 0: return
	time += dt
	hurt_flash = maxf(0, hurt_flash - dt * 2)
	reaction_flash = maxf(0, reaction_flash - dt * 2)
	bite_cooldown -= dt
	predator_stun = maxf(0, predator_stun - dt)
	for particle in particles:
		var flow := Vector2(sin(particle.p.y * 0.009 + time * 0.16), cos(particle.p.x * 0.008 + time * 0.12)) * 4.0
		particle.p += (particle.v + flow + Vector2.from_angle(particle.phase + time) * 1.2) * dt
		particle.v *= exp(-dt * (0.2 if particle.kind == TOXIN else 1.2))
		particle.p = particle.p.clamp(Vector2(5, 5), WORLD - Vector2(5, 5))
		if particle.life >= 0:
			particle.life -= dt
			if particle.life <= 0: particle.alive = false
	grid.rebuild(particles)
	_sense()
	_move(dt)
	_feed()
	_metabolize(dt)
	_predate(dt)
	_defend(dt)
	particles = particles.filter(func(p): return p.alive)
	spawn_clock += dt
	if spawn_clock >= 0.4:
		spawn_clock -= 0.4
		if particles.size() < 700:
			var source: Vector2 = food_sources[rng.randi_range(0, food_sources.size() - 1)]
			spawn_particle(NUTRIENT, source + Vector2(rng.randfn(0, 45), rng.randfn(0, 40)))
			spawn_particle(OXYGEN, Vector2(rng.randf_range(10, WORLD.x-10), rng.randf_range(10, WORLD.y-10)))
	radius = 47.0 + minf(19.0, processed * 0.16)
	won = processed >= 40.0 and time >= 90.0

func _sense() -> void:
	var food := Vector2.ZERO
	var threat := Vector2.ZERO
	sensor_active = false
	threat_detected = false
	for slot in 8:
		if organs[slot] != "sensing": continue
		var receptor := slot_position(slot)
		for index in grid.query(receptor, 185.0):
			var particle: Dictionary = particles[index]
			if not particle.alive: continue
			var offset: Vector2 = particle.p - receptor
			var distance := offset.length()
			if distance > 185.0: continue
			if particle.kind == NUTRIENT:
				food += (particle.p - position).normalized() / maxf(28, distance)
				sensor_active = true
			elif particle.kind == DANGER:
				threat -= (particle.p - position).normalized() * (1.0 - distance / 185.0)
				threat_detected = true
	if threat_detected and threat.length() > 0.01:
		target_vector = threat.normalized()
		threat_direction = -target_vector
		state = "EVADING PREDATOR"
	elif sensor_active and food.length() > 0.01:
		target_vector = food.normalized()
		state = "SEEKING NUTRIENTS"
	else:
		target_vector = Vector2.from_angle(angle + sin(time * 0.37) * 0.7)
		state = "EXPLORING"
	# Chemoreceptors also relay local membrane contact at the pool boundary.
	# This is an autonomous tactile response, never a player steering command.
	if count("sensing") > 0:
		var inward := Vector2.ZERO
		var margin := radius + 65.0
		if position.x < margin: inward.x += 1
		if position.x > WORLD.x - margin: inward.x -= 1
		if position.y < margin: inward.y += 1
		if position.y > WORLD.y - margin: inward.y -= 1
		if inward != Vector2.ZERO:
			target_vector = (target_vector + inward * 3.0).normalized()
			state = "BOUNDARY CONTACT · TURNING"
	if count("propulsion") == 0: state = "DRIFTING · NO PROPULSION"
	elif energy <= 1: state = "LOW ENERGY · DRIFTING"

func _move(dt: float) -> void:
	var steering := clampf(wrapf(target_vector.angle() - angle, -PI, PI), -1, 1)
	var force := Vector2.ZERO
	var torque := 0.0
	for slot in 8:
		if organs[slot] != "propulsion" or energy < 1.0: continue
		var normal := Vector2.from_angle(angle + TAU * slot / 8.0)
		var thrust := -normal.rotated(-steering * 0.85) * 215.0
		force += thrust
		torque += (normal * radius).cross(thrust) / (radius * radius)
		energy = maxf(0, energy - dt * 0.38)
	var acceleration := force / (1.0 + processed * 0.008) - velocity * 3.5
	velocity += acceleration * dt
	angular_velocity += (torque * 0.95 - angular_velocity * 5.0) * dt
	angle = wrapf(angle + angular_velocity * dt, -PI, PI)
	position += velocity * dt
	var bounded := position.clamp(Vector2.ONE * (radius + 25), WORLD - Vector2.ONE * (radius + 25))
	if bounded != position:
		velocity *= -0.4
		angular_velocity += 1.3 * dt
	position = bounded
	membrane.step(dt, radius, acceleration.rotated(-angle), time)

func _feed() -> void:
	for slot in 8:
		if organs[slot] != "feeding": continue
		var mouth := slot_position(slot)
		for index in grid.query(mouth, 24.0):
			var particle: Dictionary = particles[index]
			if particle.alive and particle.kind == NUTRIENT and particle.p.distance_squared_to(mouth) < 24.0 * 24.0 and substrate <= 23.0:
				particle.alive = false
				substrate += 1.0
				eaten += 1
				reaction_flash = 1.0
	for index in grid.query(position, radius + 12):
		var particle: Dictionary = particles[index]
		if particle.alive and particle.kind == OXYGEN and particle.p.distance_to(position) < radius + 12 and oxygen <= 29.0:
			particle.alive = false
			oxygen += 1.0

func _metabolize(dt: float) -> void:
	# Coarse-grained game reaction: 1 substrate + 1 O2 -> 3 ATP + 0.8 biomass + waste.
	# Quantities are game units, not a claim of molecular stoichiometry.
	var amount := minf(minf(substrate, oxygen), 1.8 * dt)
	substrate -= amount
	oxygen -= amount
	energy = minf(100, energy + amount * 3.0)
	biomass += amount * 0.8
	processed += amount
	reactions += amount
	energy = maxf(0, energy - dt * 0.20)
	waste_clock += amount
	if waste_clock >= 1:
		waste_clock -= 1
		spawn_particle(WASTE, position - Vector2.from_angle(angle) * radius, -Vector2.from_angle(angle) * 14)
	if energy <= 0: health = maxf(0, health - dt * 1.4)
	var repairs := count("regenerative")
	if repairs > 0 and health < 100 and energy > 3 and biomass > 0.1:
		var healed := minf(100 - health, repairs * 3.0 * dt)
		health += healed
		energy -= healed * 0.6
		biomass -= healed * 0.06

func _predate(dt: float) -> void:
	emission_clock += dt
	if emission_clock >= 0.25:
		emission_clock -= 0.25
		for i in 3:
			var direction := Vector2.from_angle(rng.randf() * TAU)
			spawn_particle(DANGER, predator + direction * predator_radius, direction * 24)
	var offset := position - predator
	var desired := offset.normalized() * (31.0 if time < 30 else 42.0)
	if predator_stun > 0 or predator_health <= 0:
		desired = -offset.normalized() * 55.0
		if predator_health <= 0:
			predator_health = 100
			predator_stun = 14
	predator_velocity = predator_velocity.lerp(desired, 1.0 - exp(-dt * 1.4))
	predator += predator_velocity * dt
	predator = predator.clamp(Vector2.ONE * 65, WORLD - Vector2.ONE * 65)
	var contact := radius + predator_radius - 7.0
	if offset.length() < contact:
		var normal := offset.normalized() if offset.length() > 0.01 else Vector2.LEFT
		position = (predator + normal * contact).clamp(Vector2.ONE * (radius + 25), WORLD - Vector2.ONE * (radius + 25))
		velocity += normal * 25.0 * dt
		if bite_cooldown <= 0 and predator_stun <= 0:
			var damage := 15.0 * pow(0.60, count("protection"))
			health = maxf(0, health - damage)
			hurt_flash = 1.0
			bite_cooldown = 1.1
			# Local membrane compression exposes the collision visually.
			for i in membrane.COUNT:
				var world_point: Vector2 = position + membrane.points[i].rotated(angle)
				if world_point.distance_to(predator) < predator_radius + 10:
					membrane.points[i] *= 0.82

func _defend(dt: float) -> void:
	attack_clock -= dt
	if attack_clock <= 0 and energy > 4 and threat_detected:
		for slot in 8:
			if organs[slot] != "offensive" or energy < 2.0: continue
			var start := slot_position(slot)
			spawn_particle(TOXIN, start, threat_direction * 145)
			energy -= 2.0
		attack_clock = 1.1
	for particle in particles:
		if particle.kind == TOXIN and particle.alive and particle.p.distance_to(predator) < predator_radius:
			particle.alive = false
			predator_health -= 12.0
			predator_stun = maxf(predator_stun, 1.4)
