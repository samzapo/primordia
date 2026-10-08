extends RefCounted
const Sim = preload("res://scripts/simulation.gd")

# External stationary reservoir isolates terminal swimming speed from advection.
static func swim(size_factor: float, flagella: int) -> float:
	var sim = Sim.new(328)
	sim.cells = [sim.player]
	sim.habitat_geometry.enabled = false
	var body = sim.player
	body.organs.clear()
	body.body = 60*size_factor
	body.biomass = 18*size_factor
	body.brood_mass = 0
	body.update_geometry()
	body.membrane = preload("res://scripts/membrane.gd").new(body.radius)
	for i in flagella: body.add_organ("propulsion",PI+0.18*(i-(flagella-1)*0.5),"graze",false)
	body.facing = Vector2.RIGHT
	body.target = Vector2.RIGHT
	var total := 0.0
	for i in 1200:
		sim.fluid.velocity.fill(Vector2.ZERO)
		sim.fluid.activity.fill(1)
		body.energy = body.energy_reference()
		sim._motion_cell(body,1.0/60)
		if i >= 1100: total += body.velocity.length()/100.0
	return total

static func run(check: Callable) -> void:
	var baseline = Sim.Cell.new()
	var large = Sim.Cell.new()
	large.body = baseline.body*8
	large.biomass = baseline.biomass*8
	large.update_geometry()
	check.call(is_equal_approx(large.radius/baseline.radius,sqrt(8)) and is_equal_approx(large.fluid_drag()/baseline.fluid_drag(),sqrt(8)),"Eightfold represented volume scales radius and membrane drag by sqrt(8)")
	var small_speed := swim(1,1)
	var big_speed := swim(8,1)
	var powered_speed := swim(8,2)
	print("SIZE DRAG: baseline=%.3f doubled_radius=%.3f double_propulsion=%.3f" % [small_speed,big_speed,powered_speed])
	check.call(big_speed < small_speed*0.65 and big_speed > small_speed*0.35,"A larger cell has lower steady swimming speed at equal propulsion, beyond slower initial acceleration")
	check.call(powered_speed > big_speed*1.5,"Extra ordinary propulsion still helps a larger cell overcome its drag")
	check.call(Sim.Offscreen._swim(large) == 0,"A passive body receives no hidden swimming power")
	baseline.add_organ("propulsion",PI,"graze",false)
	large.add_organ("propulsion",PI,"graze",false)
	check.call(Sim.Offscreen._swim(large) < Sim.Offscreen._swim(baseline),"Coarse hunting mobility reflects the same greater drag, with no offscreen size boost")
	for body in [baseline,large]:
		var fluid = Sim.Medium.new()
		fluid.driven = false
		fluid.velocity.fill(Vector2.ZERO)
		fluid.activity.fill(1)
		body.velocity = Vector2(40,10)
		var before: Vector2 = body.velocity*body.mass+fluid.momentum()
		var kinetic: float = 0.5*body.mass*body.velocity.length_squared()
		for i in 6: fluid.exchange(body,Vector2.from_angle(TAU*i/6.0)*body.radius,0.5,body.fluid_drag()/6.0)
		var after: Vector2 = body.velocity*body.mass+fluid.momentum()
		var energy: float = 0.5*body.mass*body.velocity.length_squared()+0.5*body.inertia*body.angular_velocity*body.angular_velocity
		for velocity in fluid.velocity: energy += 0.5*Sim.Medium.NODE_MASS*velocity.length_squared()
		check.call(after.distance_to(before) < 0.1 and energy <= kinetic+0.1,"Size-dependent drag retains equal/opposite momentum and dissipates kinetic energy even at coarse dt")
		fluid.velocity.fill(Vector2(30,0))
		body.velocity = Vector2.ZERO
		body.angular_velocity = 0
		for i in 6: fluid.exchange(body,Vector2.from_angle(TAU*i/6.0)*body.radius,0.5,body.fluid_drag()/6.0)
		check.call(body.velocity.x > 0 and body.velocity.x <= 30.01,"Larger passive cells are still carried by currents, with no world-speed clamp")
