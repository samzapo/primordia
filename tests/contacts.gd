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
	cell.position = Vector2(1980,1280)
	cell.velocity = Vector2(100,0)
	cell.angular_velocity = 0
	cell.membrane = Cell.Membrane.new(cell.radius)
	cell.angle = 0
	cell.add_organ("offensive",0,"graze",false)
	var before := {"p":cell.position,"angle":cell.angle}
	cell.position.x += 40
	sim._spike_plants(cell,cell.organs[0],before,DT)
	check.call(cell.position.x < 2020 and cell.velocity.x <= 1,"Spike shaft catches a solid stem before the cell body touches it")
	cell.organs.clear()
	cell.position = Vector2(2100,1280)
	cell.velocity = Vector2.ZERO
	h.move_cell(cell,cell.position,cell.position,DT)
	check.call(absf(cell.position.x-2100) > cell.radius*0.8,"Initial overlap exactly on a stem gets a finite separating normal")


static func _spikes(check: Callable) -> void:
	var sim = preload("res://tests/pheromones.gd").isolated()
	var attacker = sim.player
	attacker.organs.clear()
	attacker.angle = 0
	attacker.energy = 0
	attacker.membrane = Cell.Membrane.new(attacker.radius)
	attacker.add_organ("offensive",0,"graze",false)
	var prey = body(99,attacker.position+Vector2(112,0))
	sim.cells.append(prey)
	prey.velocity = Vector2(-120,18)
	var health: float = prey.health
	var initial := Sim.Medium.offset(attacker.position,prey.position).length()
	sim._spike_contacts(DT)
	check.call(prey.velocity.x > -120 and attacker.velocity.x < 0,"An unpowered spike physically transfers impact into its owner")
	check.call(Sim.Medium.offset(attacker.position,prey.position).length() > initial,"Spike contact separates bodies at the weapon instead of allowing visual impalement")
	check.call(prey.health < health and attacker.energy == 0,"Mechanical puncture can wound a cell that runs into an unpowered spike")
	check.call(attacker.target_id == -1 and attacker.signals.is_empty(),"Spike contact never acquires a sensory target")
	# A fair isolated comparison verifies the mobility advantage.
	var hits: Array[float] = []
	for speed in [20.0,160.0]:
		var striker = body(7,Vector2(2000,1280))
		striker.angle = 0
		striker.energy = 0
		striker.add_organ("offensive",0,"graze",false)
		var victim = body(8,Vector2(2112,1280))
		victim.velocity = Vector2(-speed,0)
		sim.cells = [striker,victim]
		sim._spike_contacts(DT)
		hits.append(100-victim.health)
	check.call(hits[1] > hits[0]*3 and hits[1] >= 40,"Greater impact speed earns substantially more spike damage without an attack multiplier")
	sim.cells = [attacker,prey]
	# Three substantial collisions can kill exposed, repairing prey.
	prey.lineage = -1
	prey.health = 100
	prey.energy = 100
	prey.biomass = 20
	for impact in 3:
		prey.position = attacker.position+Vector2(112,0)
		attacker.velocity = Vector2.ZERO
		prey.velocity = Vector2(-160,0)
		sim._spike_contacts(DT)
		if impact < 2: prey.heal(1.0)
	check.call(prey.health <= 0,"Three solid spike impacts kill exposed prey even with repair between hits")
	prey.health = 100
	prey.holes.clear()
	# Cross the shaft quickly, without crossing the owner's body.
	attacker.position = Vector2(2000,1280)
	prey.position = Vector2(2082,1190)
	var starts := {attacker.id:{"p":attacker.position,"angle":0.0},prey.id:{"p":prey.position,"angle":0.0}}
	prey.position.y += 190
	prey.velocity = Vector2(0,900)
	sim._spike_contacts(DT,starts)
	check.call(prey.position.y < 1280 and prey.velocity.y < 900,"Swept spike contact catches a fast cell crossing its shaft")
	# Recognition removes injury, not collision; no false live-source sensor.
	prey.lineage = attacker.lineage_id()
	prey.position = attacker.position+Vector2(112,0)
	prey.velocity = Vector2(-100,0)
	health = prey.health
	sim._spike_contacts(DT)
	check.call(prey.health == health and prey.velocity.x > -100,"Relatives collide with spikes without deliberate injury")

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
	check.call(sim.player.target_id == -1,"A new defended larger report cancels eligibility")
	prey.body = 10
	sim.time += 0.1
	test.deliver(sim,prey)
	test.listen(sim)
	check.call(sim.player.target_id == prey.id,"Smaller prey remains eligible even with reported armor")
	sim.player.recycle(0)
	sim.player.add_organ("offensive",0,"graze",false)
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
		sim.player.organs.clear()
		sim.player.add_organ("offensive",0,"graze",false)
		sim.player.angle = 0
		var near = body(80,sim.player.position+Vector2(115,15))
		near.velocity = Vector2(-160,0)
		sim.cells.append(near)
		sim.cells.append(body(81,sim.player.position+Vector2(800,500)))
		sim._spike_contacts(DT)
		results.append([sim.player.position,sim.player.velocity,near.position,near.velocity,near.health])
	check.call(results[0] == results[1],"Conservative spike candidate rejection preserves physical contact and injury")
