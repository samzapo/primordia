extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const DT := 1.0/60
static func fixture(seed_value: int = 318):
	var sim = Sim.new(seed_value)
	sim.evolution.enabled = false
	sim.cells = [sim.player]
	sim.pending_replacements.clear()
	sim.particles.clear()
	sim.pheromones.clear()
	sim.grid.rebuild(sim.particles)
	sim.habitat_geometry.enabled = false
	sim.camera_follows_player = false
	sim.camera_position = Vector2.ZERO
	sim.view_half = Vector2(100,100)
	return sim

static func organic(sim) -> float:
	var total: float = sim.respiration_loss+sim.lineage.stored_material()-sim.external_input
	for cell in sim.cells:
		if not cell.dead: total += cell.organic_mass()
	for p in sim.particles:
		if p.alive: total += p.amount*Sim.Catalog.material(p.kind)
	return total

static func run(check: Callable) -> void:
	var sim = fixture()
	var cell = sim.player
	cell.chemistry.receive(0,2,2,cell.position+cell.local_point(0))
	var initial: float = organic(sim)
	var stored: float = cell.substrate
	for i in 90: sim.step(DT)
	check.call(cell.age > 1 and absf(cell.age+cell.coarse_elapsed-sim.time) < 0.00001,"Hidden living cells receive all real elapsed biology time")
	if preload("res://tests/test_policy.gd").GAMEPLAY_BALANCE_ENABLED:
		check.call(cell.substrate < stored and cell.processed > 0,"Offscreen growth consumes actual substrate")
	check.call(absf(organic(sim)-initial) < 0.001,"Coarse metabolism/secretion conserve accounted organic resources")
	var age: float = cell.age
	sim.begin_build()
	for i in 90: sim.step(DT)
	check.call(sim.player.age == age,"Editing pauses coarse biology as well as visible biology")
	sim.commit_build()
	cell = sim.player
	sim.camera_position = cell.position
	sim.step(DT)
	check.call(absf(cell.age-sim.time) < 0.00001 and cell.coarse_elapsed == 0,"Camera promotion settles pending biology once without losing time")
	check.call(not sim.coarse_mode and not sim.fluid.global_coupling,"Coarse processing restores foreground execution state")
	_barriers_and_scavenging(check)
	_feeding(check)
	_hunting(check)
	_events(check)
	_chemistry(check)
	_decoy_binding(check)
	_transitions(check)
	_starvation(check)

static func _feeding(check: Callable) -> void:
	var sim = fixture()
	var cell = sim.player
	cell.substrate = 0
	for i in 60: sim.spawn_particle(sim.NUTRIENT,cell.position+Vector2.from_angle(i*2.4)*95,Vector2.ZERO,0.3,900)
	var before: float = organic(sim)
	var outside := 0.0
	for i in 20: sim.offscreen_ecology._feed(sim,cell,0.5)
	outside = cell.eaten
	check.call(outside > 0 and cell.substrate <= cell.gut_capacity(),"Wider offscreen absorption reaches real resources and respects gut capacity")
	check.call(absf(organic(sim)-before) < 0.001,"Wide feeding transfers existing particles without a biomass/ATP bonus")
	var eaten: float = cell.eaten
	sim.camera_position = cell.position
	for i in 20: sim.offscreen_ecology._feed(sim,cell,1)
	check.call(cell.eaten == eaten,"Background feeding cannot vacuum visible particles")
	sim.camera_position = Vector2.ZERO
	cell.organs.clear()
	for i in 20: sim.offscreen_ecology._feed(sim,cell,1)
	check.call(cell.eaten == eaten,"No feeding pore means no offscreen nutrient absorption")

static func pair():
	var sim = fixture()
	var attacker = sim.player
	attacker.organs.clear()
	attacker.add_organ("hunting",0,"hunt",false)
	attacker.add_organ("poreforming",0.35,"graze",false)
	attacker.add_organ("poreforming",-0.35,"graze",false)
	attacker.add_organ("feeding",1.4,"graze",false)
	attacker.add_organ("propulsion",PI,"graze",false)
	var prey = sim._make_cell(attacker.position+Vector2(110,0),"grazer")
	prey.role = "ancestor" # No replacement endowment in this closed fixture.
	prey.organs.clear()
	prey.activity = 0
	prey.angle = PI
	attacker.activity = 0
	attacker.angle = 0
	attacker.target_id = prey.id
	attacker.target_mode = "hunt"
	attacker.target_memory = 1
	return sim

static func _hunting(check: Callable) -> void:
	var sim = pair()
	var a = sim.player
	var b = sim.cells[1]
	var initial_energy: float = a.energy
	for i in 30: sim.offscreen_ecology._hunt(sim,a,1)
	check.call(not b.dead and a.energy == initial_energy,"Coarse hunting never substitutes a statistical kill for chemical contact")
	var initial: float = organic(sim)
	var mass: float = b.organic_mass()
	var gut: float = a.substrate
	var oxygen: float = a.oxygen+b.oxygen
	sim.offscreen_ecology._kill(sim,b)
	check.call(b.dead and a.substrate == gut,"A coarse kill lyses the prey without privileged direct consumption")
	check.call(absf(organic(sim)-initial) < 0.001,"Released debris exactly accounts for death material")
	var debris := 0.0
	var released_oxygen := 0.0
	for p in sim.particles:
		debris += p.amount*Sim.Catalog.material(p.kind)
		if p.kind == sim.OXYGEN: released_oxygen += p.amount
	check.call(absf(debris+(a.substrate-gut)-mass) < 0.001 and absf(oxygen-a.oxygen-released_oxygen) < 0.001,"Lysis releases all organic material and retained oxygen exactly once")
	var after: float = organic(sim)
	sim.offscreen_ecology._kill(sim,b)
	check.call(absf(organic(sim)-after) < 0.001,"A corpse can only be awarded once")
	sim = pair()
	a = sim.player
	b = sim.cells[1]
	sim.camera_position = b.position
	for i in 30: sim.offscreen_ecology._hunt(sim,a,1)
	check.call(not b.dead,"A coarse coin toss can never kill a visible encounter")
	sim.camera_position = Vector2.ZERO
	a.target_memory = 0
	for i in 30: sim.offscreen_ecology._hunt(sim,a,1)
	check.call(not b.dead,"Nearby live coordinates never replace a missing pheromone")
	a.target_memory = 1
	a.organs = a.organs.filter(func(o): return o.kind != "hunting")
	for i in 30: sim.offscreen_ecology._hunt(sim,a,1)
	check.call(not b.dead,"Spikes alone remain unable to detect offscreen prey")

static func _events(check: Callable) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 87
	var counts := 0.0
	for trial in 5000: counts += Sim.Offscreen.event_count(random,4)
	check.call(absf(counts/5000-4) < 0.12,"Coarse event multiplicity preserves expected production rather than capping at one")
	var sim = fixture()
	var cell = sim.player
	sim.time = 20
	var packet: Dictionary = sim._emit_pheromone(cell,19.5)
	var snapshot: Dictionary = packet.report.duplicate(true)
	cell.body *= 2
	cell.position += Vector2(400,50)
	check.call(packet.report == snapshot and snapshot.emitted_at == 19.5,"Coarse pheromones retain actual emission-time metadata")
	check.call(not sim._pheromone_alive(packet) or packet.expires_at > sim.time,"Backdated pheromones never extend their sampled lifetimes")

static func _starvation(check: Callable) -> void:
	var sim = fixture()
	var cell = sim.player
	cell.organs.clear()
	cell.substrate = 0
	cell.biomass = 0 # Isolate starvation grace; no biomass remains for stress-toxin secretion.
	cell.carbon = 0
	cell.energy = 0
	cell.health = 1
	sim.time = 1
	sim.offscreen_ecology.advance(sim,cell,1)
	check.call(not cell.dead and cell.health==1,"A brief offscreen fuel shortage cannot kill a cell")
	cell.starvation_seconds=Sim.Cell.STARVATION_GRACE
	sim.time+=12
	sim.offscreen_ecology.advance(sim,cell,12)
	check.call(cell.dead,"Prolonged severe offscreen starvation still releases the cell through ordinary lysis")

static func _chemistry(check: Callable) -> void:
	var sim = fixture()
	var at: Vector2 = sim.player.position+Vector2(90,0)
	sim.spawn_particle(sim.ANTITOXIN,at,Vector2.ZERO,0.3,sim.player.id)
	sim.spawn_particle(sim.TOXIN,at+Vector2(3,0),Vector2.ZERO,0.3,900)
	sim.particles[0].direction = Vector2.RIGHT
	sim.particles[1].direction = Vector2.LEFT
	sim.time = 0.01
	var before: float = organic(sim)
	var ids: Array[int] = [0,1]
	sim._chemistry(0,ids,true)
	check.call(sim.chemistry_events.neutralize == 1,"Hidden chemistry preserves oriented antitoxin/toxin binding")
	check.call(absf(organic(sim)-before) < 0.0001,"Coarse neutralization conserves actual material")
	var count: int = sim.chemistry_events.neutralize
	sim._chemistry(0,ids,true)
	check.call(sim.chemistry_events.neutralize == count,"Overlapping cell patches cannot process chemical time twice")
	sim = fixture()
	at = sim.player.position+Vector2(90,0)
	sim.spawn_particle(sim.ANTITOXIN,at,Vector2.ZERO,0.3,sim.player.id)
	sim.spawn_particle(sim.TOXIN,at+Vector2(3,0),Vector2.ZERO,0.3,900)
	sim.particles[0].direction = Vector2.LEFT
	sim.particles[1].direction = Vector2.RIGHT
	sim.time = 0.01
	sim._chemistry(0,ids,true)
	check.call(sim.chemistry_events.neutralize == 0,"Coarse chemistry never substitutes a coin toss for orientation")
	sim.spawn_particle(sim.ACID,at+Vector2(35,0),Vector2.ZERO,0.3,sim.player.id)
	ids = [2]
	sim.time = 0.5
	sim._chemistry(0,ids,true)
	var capacity: float = sim.particles[2].capacity
	check.call(capacity < 0.3 and sim.acidity.sample(sim.particles[2].p) > 0,"Hidden acid carriers spend their real capacity into the field")
	sim._chemistry(0,ids,true)
	check.call(sim.particles[2].capacity == capacity,"A second hidden cell cannot spend carrier capacity for the same elapsed time")

static func _transitions(check: Callable) -> void:
	var sim = fixture()
	var cell = sim.player
	var pending_before: float = cell.age
	for cycle in 12:
		sim.camera_position = Vector2.ZERO
		for i in 12: sim.step(DT)
		sim.camera_position = cell.position
		sim.step(DT)
	check.call(absf(cell.age+cell.coarse_elapsed-sim.time-pending_before) < 0.00001,"Repeated camera changes neither lose nor duplicate biology time")
	var settled = fixture()
	var hidden = fixture()
	for world in [settled,hidden]:
		world.player.organs.clear()
		world.player.add_organ("propulsion",PI,"graze",false)
		world.time = 0.5
	settled.offscreen_ecology.advance(settled,settled.player,0.5,false)
	hidden.offscreen_ecology.advance(hidden,hidden.player,0.5,true)
	check.call(absf(settled.player.energy-hidden.player.energy) < 0.00001,"Promotion pays the same propulsion cost as a hidden interval")

static func _barriers_and_scavenging(check: Callable) -> void:
	var sim = pair()
	var a = sim.player
	var b = sim.cells[1]
	var h = sim.habitat_geometry
	h.enabled = true
	h.forms = [{"branches":[{"a":Vector2(0,-100),"b":Vector2(0,100),"r":6.0,"depth":2}]}]
	h.plants = [{"p":a.position+Vector2(70,0),"radius":120.0,"form":0,"angle":0.0}]
	h.rebuild()
	check.call(not Sim.Offscreen._clear_path(sim,a.position,b.position),"Solid stems separate hidden encounters")
	for i in 20: sim.offscreen_ecology._hunt(sim,a,1)
	check.call(not b.dead,"A probabilistic hunter cannot kill through a solid plant")
	h.enabled = false
	a.energy = 0
	sim.offscreen_ecology._hunt(sim,a,1)
	check.call(not b.dead and a.energy == 0,"Offscreen hunting cannot create attack power without particles")
	a.energy = 72
	var observer = sim._make_cell(a.position+Vector2(80,30),"grazer")
	observer.role = "ancestor"
	observer.substrate = 0
	observer.organs.clear()
	observer.add_organ("feeding",0,"graze",false)
	var initial: float = organic(sim)
	sim.offscreen_ecology._kill(sim,b)
	for i in 40: sim.offscreen_ecology._feed(sim,observer,0.5)
	check.call(observer.eaten > 0,"Lysed prey feeds another nearby scavenger through ordinary absorption")
	check.call(absf(organic(sim)-initial) < 0.0001,"Scavenging transfers finite corpse material without a second payout")
	var state: int = sim.rng.state
	sim.time += 0.5
	sim.offscreen_ecology.advance(sim,a,0.5)
	check.call(sim.rng.state == state,"Offscreen draws do not advance the foreground random stream")

static func _decoy_binding(check: Callable) -> void:
	var sim = fixture()
	var cell = sim.player
	cell.organs.clear()
	cell.add_organ("feeding",0,"graze",false)
	var organ: Dictionary = cell.organs[0]
	var forward: Vector2 = cell.local_point(organ.a).normalized().rotated(cell.angle)
	var at: Vector2 = cell.organ_position(organ)+forward*3
	sim.spawn_particle(sim.DECOY,at,Vector2.ZERO,0.3,900)
	var packet: Dictionary = sim.particles[-1]
	packet.direction = forward
	sim.offscreen_ecology._exposure(sim,cell,100)
	check.call(packet.alive and organ.blocked == 0,"Hidden decoys still require the correct binding orientation")
	packet.direction = -forward
	sim.offscreen_ecology._exposure(sim,cell,100)
	check.call(not packet.alive and organ.blocked > 0,"Oriented hidden receptor competition consumes its real decoy")
