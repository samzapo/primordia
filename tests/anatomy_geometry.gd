extends RefCounted
const Cell = preload("res://scripts/cell.gd")
const Sim = preload("res://scripts/simulation.gd")
static func run(check: Callable) -> void:
	var cell = Cell.new(44)
	cell.organs.clear()
	for i in cell.membrane.COUNT:
		var a: float = TAU*i/cell.membrane.COUNT
		cell.membrane.points[i] = Vector2.from_angle(a)*cell.radius*(1+0.22*sin(2*a))
	cell.membrane.outline_dirty = true
	cell.membrane.geometry_dirty = true
	var worst := 0.0
	for i in 64:
		var a: float = TAU*i/64.0
		var radius: float = cell.radius*(1+0.22*sin(2*a))
		var derivative: float = cell.radius*0.44*cos(2*a)
		var tangent := Vector2(-sin(a),cos(a))*radius+Vector2.from_angle(a)*derivative
		var normal: Vector2 = cell.local_normal(a)
		worst = maxf(worst,absf(normal.dot(tangent.normalized())))
		check.call(normal.is_finite() and normal.dot(Vector2.from_angle(a)) > 0,"Deformed membrane attachment normals remain finite and outward")
	print("NORMAL_TANGENT_ERROR ",worst)
	check.call(worst < 0.045,"Attachment normals follow an independently specified curved membrane tangent")
	var organ := {"kind":"feeding","a":0.0,"scale":1.0}
	cell.angle = 0.8
	var normal: Vector2 = cell.organ_normal(organ).rotated(cell.angle)
	var base: Vector2 = cell.position+cell.local_point(organ.a).rotated(cell.angle)
	check.call((cell.organ_position(organ)-base).normalized().distance_to(normal) < 0.0001,"Attachment offsets use membrane normals rather than nucleus rays")
	check.call((cell.pore_center(organ)-cell.organ_position(organ)).normalized().distance_to(normal) < 0.0001,"Pore suction and intake centers follow the mounted axis")
	check.call(absf(cell.local_normal(0).angle()) > 0.3,"A sloped membrane produces visibly nonradial organ orientation")
	# The sensed organ faces the cue with that same local normal.
	var sim = Sim.new(82)
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.grid.clear()
	sim.player.membrane = Cell.clone_state(cell.membrane)
	sim.player.organs.clear()
	sim.player.add_organ("hunting",0,"hunt",false)
	var prey = sim._make_cell(sim.player.position+Vector2(600,0),"grazer")
	preload("res://tests/pheromones.gd").deliver(sim,prey)
	preload("res://tests/pheromones.gd").listen(sim)
	check.call(is_equal_approx(sim.player.target_mouth,sim.player.organ_normal(sim.player.organs[0]).angle()),"Pursuit aligns the receptor's membrane normal to the target")
