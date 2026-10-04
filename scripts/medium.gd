extends RefCounted
## Mass-lumped, viscous 2D medium. Not an incompressible Navier-Stokes solver.
const SIZE := 64.0
const COLS := 64
const ROWS := 40
const WORLD := Vector2(COLS * SIZE, ROWS * SIZE)
const NODE_MASS := 22.0
var velocity := PackedVector2Array()
var activity := PackedFloat32Array()
var driven := true

func _init() -> void:
	velocity.resize(COLS * ROWS)
	activity.resize(COLS * ROWS)
	for y in ROWS:
		for x in COLS:
			velocity[index(x, y)] = current(Vector2(x + 0.5, y + 0.5) * SIZE)

static func wrap_position(p: Vector2) -> Vector2:
	return Vector2(fposmod(p.x, WORLD.x), fposmod(p.y, WORLD.y))

static func offset(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(wrapf(b.x - a.x, -WORLD.x * 0.5, WORLD.x * 0.5), wrapf(b.y - a.y, -WORLD.y * 0.5, WORLD.y * 0.5))

static func visibility(p: Vector2, camera: Vector2) -> float:
	var d = offset(camera, p) / Vector2(508, 316)
	var t = clampf((1.0 - d.length()) / 0.28, 0, 1)
	return t * t * (3 - 2 * t)

static func index(x: int, y: int) -> int:
	return posmod(y, ROWS) * COLS + posmod(x, COLS)

func current(p: Vector2) -> Vector2:
	# Explicit externally maintained tide plus periodic vortices.
	return Vector2(11 + 17 * sin(TAU * p.y / WORLD.y * 4), 15 * sin(TAU * p.x / WORLD.x * 4))

func stencil(p: Vector2) -> Array:
	var q = wrap_position(p) / SIZE - Vector2.ONE * 0.5
	var base = Vector2i(q.floor())
	var f = q - Vector2(base)
	return [[index(base.x, base.y), (1-f.x)*(1-f.y)], [index(base.x+1, base.y), f.x*(1-f.y)], [index(base.x, base.y+1), (1-f.x)*f.y], [index(base.x+1, base.y+1), f.x*f.y]]

func sample(p: Vector2) -> Vector2:
	var result = Vector2.ZERO
	for pair in stencil(p): result += velocity[pair[0]] * pair[1]
	return result

func set_camera(camera: Vector2) -> void:
	for y in ROWS:
		for x in COLS:
			activity[index(x,y)] = visibility(Vector2(x + 0.5, y + 0.5) * SIZE, camera)

func exchange(body, arm: Vector2, dt: float, strength: float = 16.0) -> Vector2:
	# Implicit drag impulse with exact equal/opposite momentum transfer to wet nodes.
	# Dormant nodes neither accept impulses nor contribute to the coupled sample.
	var weights = stencil(body.position + arm)
	var total = 0.0
	for pair in weights:
		pair[1] *= activity[pair[0]]
		total += pair[1]
	if total < 0.0001: return Vector2.ZERO
	var flow = Vector2.ZERO
	var inverse_fluid_mass = 0.0
	for pair in weights:
		pair[1] /= total
		flow += velocity[pair[0]] * pair[1]
		inverse_fluid_mass += pair[1] * pair[1] / NODE_MASS
	var relative: Vector2 = flow - body.velocity - Vector2(-arm.y, arm.x) * body.angular_velocity
	var speed = relative.length()
	if speed < 0.00001: return Vector2.ZERO
	var axis = relative / speed
	var inverse_mass: float = 1.0/body.mass + pow(arm.cross(axis), 2)/body.inertia + inverse_fluid_mass
	var impulse = relative * (1 - exp(-strength * inverse_mass * dt)) / inverse_mass
	body.velocity += impulse / body.mass
	body.angular_velocity += arm.cross(impulse) / body.inertia
	for pair in weights: velocity[pair[0]] -= impulse * pair[1] / NODE_MASS
	return impulse

func deposit(p: Vector2, impulse: Vector2) -> bool:
	var weights = stencil(p)
	var total = 0.0
	for pair in weights:
		pair[1] *= activity[pair[0]]
		total += pair[1]
	if total < 0.0001: return false
	for pair in weights: velocity[pair[0]] += impulse * pair[1] / (NODE_MASS * total)
	return true

func step(dt: float) -> void:
	# Symmetric local viscosity conserves momentum; dormant neighbors are sealed.
	var delta = PackedVector2Array()
	delta.resize(velocity.size())
	for y in ROWS:
		for x in COLS:
			var i = index(x,y)
			if activity[i] <= 0: continue
			for j in [index(x+1,y), index(x,y+1)]:
				var amount = minf(activity[i], activity[j]) * minf(dt * 0.8, 0.2)
				var exchange_velocity = (velocity[j] - velocity[i]) * amount
				delta[i] += exchange_velocity
				delta[j] -= exchange_velocity
			if driven:
				# External tide is an explicit momentum/energy source and sink.
				delta[i] += (current(Vector2(x+0.5,y+0.5)*SIZE) - velocity[i]) * (1-exp(-dt*activity[i]*0.12))
	for i in velocity.size(): velocity[i] += delta[i]

func momentum() -> Vector2:
	var sum = Vector2.ZERO
	for v in velocity: sum += v * NODE_MASS
	return sum
