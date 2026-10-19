extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Contact = preload("res://scripts/contacts.gd")
const Cell = Sim.Cell
const DT := 1.0/60
static func body(id: int, at: Vector2):
	var cell = Cell.new(id,at)
	cell.organs.clear()
	cell.activity = 1
	cell.membrane = Cell.Membrane.new(cell.radius)
	return cell
static func area(cell) -> float:
	var value := 0.0
	for i in cell.membrane.COUNT: value += cell.membrane.points[i].cross(cell.membrane.points[(i+1)%cell.membrane.COUNT])*0.5
	return value
static func run(check: Callable) -> void:
	var a = body(0,Vector2(2000,1200))
	var b = body(1,a.position+Vector2(a.radius*2-2,0))
	a.velocity = Vector2(90,35)
	b.velocity = Vector2(-10,-5)
	var momentum: Vector2 = a.velocity*a.mass+b.velocity*b.mass
	var kinetic: float = 0.5*a.mass*a.velocity.length_squared()+0.5*b.mass*b.velocity.length_squared()
	var initial_area := area(a)
	var initial_edge: float = a.support(0)
	Contact.pair(a,b,DT,true)
	check.call((a.velocity*a.mass+b.velocity*b.mass-momentum).length() < 0.01,"Cell contact transfers equal/opposite linear momentum")
	var after: float = 0.5*a.mass*a.velocity.length_squared()+0.5*b.mass*b.velocity.length_squared()+0.5*a.inertia*a.angular_velocity*a.angular_velocity+0.5*b.inertia*b.angular_velocity*b.angular_velocity
	check.call(after <= kinetic*1.001 and b.velocity.x > 20,"Collision transfers motion without creating kinetic energy")
	check.call(absf(a.angular_velocity) > 0.01 and absf(b.angular_velocity) > 0.01,"Glancing contact creates rotation through tangential friction")
	check.call(a.support(0) < initial_edge and absf(area(a)-initial_area)/initial_area < 0.001,"Collision compresses the local membrane while preserving enclosed area")
	check.call(Geometry2D.triangulate_polygon(a.membrane.outline()).size() > 0,"A contacted membrane remains renderable")
	for i in 180: a.membrane.step(DT,a.radius,Vector2.ZERO,i*DT)
	check.call(a.membrane.points[0].is_finite() and absf(area(a)-initial_area)/initial_area < 0.01,"The compressed gel relaxes without losing pressure or finite geometry")
	a = body(0,Vector2(4090,1280))
	b = body(1,Vector2(60,1280))
	a.velocity = Vector2(80,0)
	Contact.pair(a,b,DT,true)
	check.call(b.velocity.x > 0 and Sim.Medium.offset(a.position,b.position).x > 0,"Physical impulses cross the wrapping seam")
	b.activity = 0
	var asleep: Vector2 = b.position
	var resting_velocity: Vector2 = b.velocity
	Contact.pair(a,b,DT,true)
	check.call(b.position == asleep and b.velocity == resting_velocity,"Dormant contact boundaries never acquire hidden motion")
	_plants(check)
	_spikes(check)
	_hunting(check)
	_pruning(check)

static func _plants(check: Callable) -> void:
	var sim = preload("res://tests/pheromones.gd").isolated()
	var cell = sim.player
	cell.organs.clear()
	cell.membrane = Cell.Membrane.new(cell.radius)
	var h = sim.habitat_geometry
	h.forms = [{"branches":[{"a":Vector2(0,-150),"b":Vector2(0,150),"r":6.0,"depth":2}]}]
	h.plants = [{"p":Vector2(2100,1280),"radius":180.0,"form":0,"angle":0.0}]
	h.rebuild()
	cell.position = Vector2(1990,1280)
	cell.velocity = Vector2(900,130)
	var original: float = cell.support(0)
	h.move_cell(cell,cell.position,cell.position+Vector2(300,40),0.05)
	check.call(cell.position.x < 2100 and cell.velocity.x < 0,"Fast membrane/stem collision stops crossing and rebounds")
	check.call(absf(cell.angular_velocity) > 0.01,"Sliding along a stem spins the cell through friction")
	check.call(cell.support(0) < original,"Plant contact visibly dents the approach side")
	cell.organs.clear()
	cell.position = Vector2(2100,1280)
	cell.velocity = Vector2.ZERO
	h.move_cell(cell,cell.position,cell.position,DT)
	check.call(absf(cell.position.x-2100) > cell.radius*0.8,"Initial overlap exactly on a stem gets a finite separating normal")


static func _spikes(check: Callable) -> void:
	var cell = Cell.new()
	check.call(not cell.add_organ("offensive",0),"Retired physical spikes cannot be installed")
	check.call(cell.add_organ("poreforming",0,"graze",false),"Chemical gland replaces spike construction")

static func _hunting(check: Callable) -> void:
	var test = preload("res://tests/pheromones.gd")
	var sim = test.isolated()
	var prey = sim._make_cell(sim.player.position+Vector2(150,0),"grazer")
	prey.organs.clear()
	prey.body = 900
	var packet: Dictionary = test.deliver(sim,prey)
	check.call(not packet.report.defended,"An unarmed unarmored cell emits an undefended snapshot")
	test.listen(sim)
	check.call(sim.player.target_id == prey.id,"Hunting receptor accepts larger undefended prey")
	prey.add_organ("protection",0,"graze",false)
	prey.position += Vector2(300,90)
	test.listen(sim)
	check.call(sim.player.target_id == prey.id and sim.player.target_position == packet.report.at,"Later defenses and movement cannot retroactively change received information")
	sim.time += 0.1
	test.deliver(sim,prey)
	test.listen(sim,1.6)
	check.call(sim.player.target_id == prey.id and sim.player.target_position==prey.position,"A new defended larger report remains a valid non-family target at its latest received location")
	prey.body = 10
	sim.time += 0.1
	test.deliver(sim,prey)
	test.listen(sim)
	check.call(sim.player.target_id == prey.id,"Smaller prey remains eligible even with reported armor")
	sim.player.recycle(0)
	sim.player.add_organ("poreforming",0,"graze",false)
	test.listen(sim,1.6)
	check.call(sim.player.target_id == -1 and sim.player.signals.is_empty(),"Replacing the receptor with a spike clears sensory memory")
	sim.player.add_organ("hunting",1,"hunt",false)
	sim.player.add_organ("sensing",-1,"flee",false)
	prey.body = 900
	prey.add_organ("toxin",2,"graze",false)
	sim.time += 0.1
	packet = test.deliver(sim,prey)
	for receptor in sim.player.organs:
		if receptor.kind == "sensing": packet.p = sim.player.organ_position(receptor)
	sim.grid.rebuild(sim.particles)
	test.listen(sim)
	check.call(sim.player.target_mode == "flee","Explicit flight takes priority over hunting")


static func _pruning(check: Callable) -> void:
	var results: Array = []
	for pruning in [false,true]:
		var sim = preload("res://tests/pheromones.gd").isolated()
		sim.spatial_queries = pruning
		sim.habitat_geometry.enabled = false
		var near = body(80,sim.player.position+Vector2(70,0))
		sim.cells.append(near)
		sim._contacts(DT)
		results.append([sim.player.position,sim.player.velocity,near.position,near.velocity,near.health])
	check.call(results[0] == results[1],"Spatial contact pruning preserves ordinary body collision")
