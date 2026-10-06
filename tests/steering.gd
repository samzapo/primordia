extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Cues = preload("res://tests/pheromones.gd")
const Family = preload("res://tests/lineage.gd")
const DT := 1.0/60

static func fixture():
	var sim = Cues.isolated()
	sim.habitat_geometry.enabled = false
	sim.player.add_organ("feeding",PI,"graze",false)
	var prey = sim._make_cell(sim.player.position+Vector2(100,0),"grazer")
	Cues.deliver(sim,prey)
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position-Vector2(140,0),Vector2.ZERO,1,prey.id)
	sim.grid.rebuild(sim.particles)
	return sim

static func arrive(sim, organ: Dictionary, mode: String, score: float, identity: int = -1, sampled: float = 0, lineage: int = -1) -> void:
	sim.player.sense_clock = 10
	sim.player.signals.append({"p":Vector2.ZERO,"mode":mode,"score":score,"sample_at":sampled,
		"id":identity,"at":sim.player.position+Vector2(100,0),"organ_id":organ.id,
		"expires_at":sim.time+10,"lineage":lineage})
	sim._sense(sim.player,DT)

static func run(check: Callable) -> void:
	var sim = fixture()
	var cell = sim.player
	var hunting: Dictionary = cell.organs[0]
	var pore: Dictionary = cell.organs[1]
	Cues.listen(sim)
	check.call(cell.target_mode == "hunt","Default hunting outranks competing grazing from actual local cues")
	var hunted: int = cell.target_id
	arrive(sim,pore,"graze",1)
	check.call(cell.target_mode == "hunt" and cell.target_id == hunted,"A later grazing arrival cannot overwrite stronger remembered hunting")
	cell.set_steering_strength(pore.id,3.3)
	Cues.listen(sim,2)
	check.call(cell.target_mode == "hunt","A near-tie at reception keeps refreshing the incumbent rather than expiring it")
	cell.set_steering_strength(pore.id,4)
	Cues.listen(sim)
	check.call(cell.target_mode == "graze" and cell.target_organ_id == pore.id,"Strong grazing can deliberately outweigh hunting at reception and delivery")
	cell.set_steering_strength(hunting.id,2)
	Cues.listen(sim)
	check.call(cell.target_mode == "hunt","Higher hunting weight wins the same unchanged local cues")
	cell.set_steering_strength(pore.id,0)
	check.call(cell.signals.all(func(packet):return packet.organ_id != pore.id),"Disabling steering removes stale in-flight pore signals")
	var before: float = cell.eaten
	sim.spawn_particle(Sim.NUTRIENT,cell.pore_center(pore),Vector2.ZERO,0.4,77)
	sim.grid.rebuild(sim.particles)
	sim._feed(cell)
	check.call(cell.eaten > before and pore.consume_flash > 0,"A steering-disabled pore still absorbs real food and animates consumption")
	var energy: float = cell.energy
	sim.fluid.set_camera(cell.position,sim.view_half)
	var fluid_before: int = hash(sim.fluid.velocity)
	sim._suction(DT)
	check.call(cell.energy < energy and hash(sim.fluid.velocity) != fluid_before,"A steering-disabled pore still pays for and drives its feeding current")
	# Coherent switching, flight priority and bounded memory.
	sim = Cues.isolated()
	cell = sim.player
	hunting = cell.organs[0]
	cell.add_organ("feeding",PI,"graze",false)
	pore = cell.organs[-1]
	arrive(sim,hunting,"hunt",1,97,2,97)
	arrive(sim,pore,"graze",1.1,-1,3)
	check.call(cell.target_mode == "hunt","Near-equal competing signals retain the current direction")
	arrive(sim,pore,"graze",1.21,-1,3)
	check.call(cell.target_mode == "graze","A signal with more than a 20 percent lead interrupts the current drive")
	arrive(sim,pore,"graze",1,-1,1)
	check.call(cell.target_sample_at == 3,"An older delayed sample cannot rewind the same organ's target")
	cell.add_organ("sensing",1.6,"flee",false)
	var flight: Dictionary = cell.organs[-1]
	arrive(sim,flight,"flee",100,98,4,98)
	cell.set_steering_strength(hunting.id,4)
	arrive(sim,hunting,"hunt",1000,97,5,97)
	check.call(cell.target_mode == "flee","Explicit flight wins regardless of hunting strength or packet arrival order")
	check.call(not cell.set_steering_strength(flight.id,0),"Hunting/feeding tuning cannot silently disable the flight receptor")
	cell.organs.erase(flight)
	sim._sense(cell,DT)
	check.call(cell.target_memory == 0,"Removing the selected receptor immediately invalidates its memory")
	arrive(sim,hunting,"hunt",3,97,5,97)
	for i in 80: sim._sense(cell,DT)
	check.call(cell.target_memory == 0 and cell.target_id == -1,"No local cue means pursuit memory expires rather than locking the cell")
	arrive(sim,pore,"graze",1,-1,6)
	check.call(cell.target_mode == "graze","Food takes over once an unrefreshed hunting cue expires")
	cell.set_steering_strength(pore.id,0)
	check.call(cell.target_memory == 0,"Disabling the selected steering drive invalidates its active memory")
	# Anatomical tuning survives editing and paid inheritance.
	sim = fixture()
	sim.player.set_steering_strength(sim.player.organs[1].id,0.25)
	var resources: Array = [sim.player.biomass,sim.player.energy,sim.evolution.points]
	sim.begin_build()
	check.call(Sim.Cell.steering_strength(sim.player.organs[1]) == 0.25,"Paused anatomical editing preserves steering settings")
	sim.player.set_steering_strength(sim.player.organs[1].id,0.5)
	sim.commit_build()
	check.call(resources == [sim.player.biomass,sim.player.energy,sim.evolution.points],"Tuning direction preference changes no tissue, ATP or AP")
	var child = sim.make_offspring(sim.player,sim.offspring_quote())
	check.call(Sim.Cell.steering_strength(child.organs[1]) == 0.5,"Offspring inherit the parent's anatomical signal strengths")
	child.set_steering_strength(child.organs[1].id,0)
	check.call(Sim.Cell.steering_strength(sim.player.organs[1]) == 0.5,"A child's tuning is independent of its parent's organs")
	_family(check)

static func _family(check: Callable) -> void:
	var sim = Family.world()
	var parent = sim.player
	parent.organs.clear()
	parent.add_organ("feeding",PI,"graze",false)
	parent.add_organ("hunting",0,"hunt",false)
	parent.add_organ("offensive",0.5,"graze",false)
	Family.fund(sim)
	check.call(sim.divide_lineage(false,false),"Family safety fixture releases an actual paid child")
	var child = sim.cells[-1]
	check.call(child.lineage_id() == parent.lineage_id(),"Paid offspring inherit the founder signature independently of role")
	# Read actual emitted snapshots in both directions, including after adoption.
	for adopted in [false,true]:
		if adopted: sim.follow_family(child.id)
		for observer in [parent,child]:
			sim.particles.clear()
			sim.grid.clear()
			var source = child if observer == parent else parent
			var organ: Dictionary = observer.organs.filter(func(item):return item.kind == "hunting")[0]
			var packet: Dictionary = sim._emit_pheromone(source)
			packet.p = observer.organ_position(organ)+Vector2(10,0)
			packet.expires_at = sim.time+10
			sim.grid.rebuild(sim.particles)
			observer.signals.clear()
			observer.target_memory = 0
			observer.sense_clock = 0
			observer.set_steering_strength(organ.id,4)
			for i in 40: sim._sense(observer,DT)
			check.call(observer.target_id == -1,"Parent/child pheromones are ignored at maximum hunting strength before and after succession")
	# A family cue already inside the cell cannot bypass recognition.
	var organ: Dictionary = sim.player.organs.filter(func(item):return item.kind == "hunting")[0]
	arrive(sim,organ,"hunt",1000,parent.id,9,parent.lineage_id())
	check.call(sim.player.target_id == -1 and sim.player.signals.is_empty(),"A delayed internal family signal cannot initiate pursuit")
	sim.player.target_id = parent.id
	sim.player.target_lineage = parent.lineage_id()
	sim.player.target_mode = "hunt"
	sim.player.target_organ_id = organ.id
	sim.player.target_memory = 1
	sim._sense(sim.player,DT)
	check.call(sim.player.target_memory == 0,"A remembered family signal cannot survive a lineage handoff")
	# Family recognition preserves physical obstruction but removes injury.
	for attacker in [parent,child]:
		var other = child if attacker == parent else parent
		attacker.angle = 0
		var spike: Dictionary = attacker.organs.filter(func(item):return item.kind == "offensive")[0]
		spike.a = 0
		attacker.position = Vector2(2048,1280)
		attacker.velocity = Vector2.ZERO
		other.position = attacker.position+Vector2(attacker.extent()+other.extent()+16,0)
		other.velocity = Vector2(-150,0)
		for o in other.organs:
			if o.kind == "offensive": o.a = PI
		var hp: float = other.health
		for i in 3: sim._spike_contacts(DT)
		check.call(other.health == hp and not other.dead,"Actual parent/child spike contact is harmless in both directions")
