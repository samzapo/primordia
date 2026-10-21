extends RefCounted
## Uniform-diffusivity Lagrangian transport; matching native and GPU formulas.
const Medium = preload("res://scripts/medium.gd")

static func advect(at: Vector2, velocity: Vector2, fluid, elapsed: float) -> Vector2:
	if elapsed <= 0.05:
		return Medium.wrap_position(at+(fluid.transport_sample(at)+velocity)*elapsed)
	# A few midpoint samples follow bends in the cached flow instead of taking
	# one long straight Euler jump. Launch velocity has an exact drag integral.
	var steps := clampi(ceili(elapsed/0.25),1,8)
	var h := elapsed/steps
	var damping := exp(-0.8*h)
	for i in steps:
		var midpoint: Vector2 = at+fluid.transport_sample(at)*(h*0.5)+velocity*((1.0-exp(-0.4*h))/0.8)
		at = Medium.wrap_position(at+fluid.transport_sample(midpoint)*h+velocity*((1.0-damping)/0.8))
		velocity *= damping
	return at

static func advance(p: Dictionary, fluid, elapsed: float, revision: int, rng: RandomNumberGenerator) -> void:
	p.previous = p.p
	p.previous_angle = p.angle
	p.updated = revision
	p.transport_jump = elapsed > 0.05
	var tracer: bool = p.kind == 3
	var velocity: Vector2 = Vector2.ZERO if tracer else p.v
	var nx := rng.randfn()
	var ny := rng.randfn()
	p.p = Medium.wrap_position(advect(p.p,velocity,fluid,elapsed)+Vector2(nx,ny)*sqrt((240.0 if tracer else 12.0)*elapsed))
	p.v = velocity*exp(-0.8*elapsed)
	p.age += elapsed
	p.angle = wrapf(p.angle+p.spin*elapsed+rng.randfn()*sqrt(1.2*elapsed),-PI,PI)
	if tracer: p.angle = 0.0
	p.direction = Vector2.ZERO if tracer else Vector2.from_angle(p.angle)
