extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Archive = preload("res://scripts/lineage_archive.gd")
const Score = preload("res://scripts/music_score.gd")

static func world():
	var sim = Sim.new(821)
	sim.habitat_geometry.enabled = false
	sim.pending_replacements.clear()
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.pheromones.clear()
	sim.grid.clear()
	return sim

static func mass(sim) -> float:
	var result: float = sim.lineage.stored_material()
	for cell in sim.cells:
		if not cell.dead: result += cell.organic_mass()
	for packet in sim.particles:
		if packet.alive: result += packet.amount*Sim.Catalog.material(packet.kind)
	return result

static func fund(sim) -> void:
	var quote: Dictionary = sim.offspring_quote()
	sim.player.biomass += quote.material
	sim.player.energy = 100
	sim.player.reserve(maxf(60,quote.material),quote.material)

static func run(check: Callable) -> void:
	var sim = world()
	var run = sim.evolution
	var offered: Array = run.offers.duplicate()
	run.choose(offered[0])
	run.spend(1,"fixture purchase")
	run.clock = 170
	run.crisis_seconds[0] = 21
	var initial: float = mass(sim)
	var founder = sim.player
	var motif: Array = Score.lineage_motif(sim.seed_value,founder.lineage_id())
	founder.death_hint = "Fixture toxin exposure"
	sim._die(founder)
	check.call(sim.lineage.recover(sim,0.01),"A dead founder hatches its prepaid reserve")
	check.call(sim.player != founder and sim.player.generation == 0 and sim.lineage.dormant.is_empty(),"The reserve is a different existing body and cannot fake a descendant victory")
	check.call(absf(mass(sim)-initial) < 0.01 and sim.external_input == 0,"Death and hatching conserve the initial bank and released tissue")
	check.call(run.clock == 170 and run.points == 2 and run.learned == [offered[0]] and run.offers == offered and run.chosen and run.crisis_seconds[0] == 21,"Death preserves clock, AP spending, draft and crisis progress")
	check.call(Score.lineage_motif(sim.seed_value,sim.player.lineage_id()) == motif,"The family theme continues through reserve recovery")
	check.call(sim.lineage.records[0].cause == "Fixture toxin exposure" and sim.lineage.records[0].state == "dead","Family history records the actual fatal process")
	fund(sim)
	initial = mass(sim)
	var parent = sim.player
	check.call(sim.divide_lineage(false,false) and sim.player == parent,"Early division releases a living successor without taking direct control")
	var child = sim.cells[-1]
	check.call(child.generation == 1 and absf(mass(sim)-initial) < 0.01,"A real successor inherits anatomy and consumes funded parental material")
	var child_position: Vector2 = child.position
	var child_health: float = child.health
	sim._die(parent)
	check.call(sim.lineage.recover(sim,0.01) and sim.player == child,"Death prefers a living family member")
	check.call(child.position == child_position and child.health == child_health,"Handoff neither teleports nor heals an existing descendant")
	check.call(not run.terminal() and run.points == 3,"Ordinary death is continuation without a fresh AP allowance")
	fund(sim)
	initial = mass(sim)
	var oxygen: float = child.oxygen
	var energy: float = child.energy+child.brood_energy
	check.call(sim.divide_lineage(true,false),"An additional dormant successor can be bought")
	var cyst = sim.lineage.dormant[0]
	check.call(absf(mass(sim)-initial) < 0.01 and child.oxygen+cyst.oxygen == oxygen and is_equal_approx(child.energy+child.brood_energy+cyst.energy,energy-20),"Dormant offspring conserves tissue/oxygen and pays division ATP")
	var atp: float = cyst.energy
	var tissue: float = cyst.organic_mass()
	for i in 10: sim.step(1.0/60)
	check.call(cyst.energy == atp and cyst.organic_mass() == tissue,"Stored cysts neither farm resources nor run hidden physiology")
	sim._die(child)
	check.call(sim.lineage.recover(sim,1) and sim.player == cyst and cyst.generation == 2,"A purchased reserve carries its actual generation and anatomy")
	sim._die(cyst)
	check.call(not sim.lineage.recover(sim,1) and run.status == "lost","Only exhausting all family and reserves ends the expedition")

	sim = world()
	fund(sim)
	sim.begin_build()
	check.call(not sim.divide_lineage(),"A draft cannot leak an independently funded body before commit")
	sim.evolution.accept_challenge("metabolism",sim.player)
	sim.evolution.offers.append("fixture")
	sim.cancel_build()
	check.call(sim.evolution.challenge == "" and sim.evolution.challenge_cell == -1 and "fixture" not in sim.evolution.offers,"Internal preview cancellation restores all challenge and draft state")
	for i in 2:
		fund(sim)
		check.call(sim.divide_lineage(true,false),"Additional reserves are separately funded")
	fund(sim)
	initial = mass(sim)
	check.call(not sim.divide_lineage(true,false) and mass(sim) == initial,"The bounded bank rejects additional bodies atomically")
	# Recovery can wait for space without consuming or losing the reserve.
	sim = world()
	sim._die(sim.player)
	var blocker = Sim.Cell.new(999,sim.player.position)
	blocker.body = 10000000
	blocker.update_geometry()
	blocker.membrane = Sim.Cell.Membrane.new(blocker.radius)
	sim.cells.append(blocker)
	check.call(not sim.lineage.recover(sim,1) and not sim.evolution.terminal() and sim.lineage.dormant.size() == 1,"A blocked hatch waits without discarding funded material")
	sim.cells.erase(blocker)
	check.call(sim.lineage.recover(sim,1),"A waiting reserve hatches when a real opening exists")
	if preload("res://tests/test_policy.gd").GAMEPLAY_OBJECTIVES_ENABLED:
		# Three crises, not three instants alive or a timer alone.
		sim = world()
		sim.player.generation = 1
		run = sim.evolution
		for stage in 3:
			run.clock = run.CRISIS_STARTS[stage]
			run.tide = mini(6,int(run.clock/run.TIDE_SECONDS))
			for i in 62:
				sim.player.processed += 0.1
				run.advance(1,sim)
			check.call(run.crisis_seconds[stage] >= 60,"Each crisis records sustained observed metabolism")
			run.clock = run.CRISIS_ENDS[stage]-1
			sim.player.processed += 0.1
			run.advance(1,sim)
		check.call(run.status == "won" and run.completed == [true,true,true],"A healthy descendant with three earned crisis records wins")
		sim = world()
		run = sim.evolution
		run.clock = 600
		sim.player.activity = 0
		for i in 70:
			sim.player.fixed_carbon += 1
			run.advance(1,sim)
		check.call(run.crisis_seconds[2] == 0,"Dormant or founder bodies cannot earn independent-descendant survival")
		for condition in ["empty ATP","offscreen","stale metabolism"]:
			sim = world()
			run = sim.evolution
			sim.player.generation = 1
			run.observe_successor(sim.player)
			run.clock = 809
			run.tide = 6
			run.crisis_seconds = [60.0,60.0,60.0]
			run.viable_seconds = 60
			run.metabolism_age = 0
			if condition == "empty ATP": sim.player.energy = 0
			elif condition == "offscreen": sim.player.activity = 0
			else: run.metabolism_age = 16
			run.advance(1,sim)
			check.call(run.status == "lost","Final viability rejects "+condition+" despite earlier achievements")
			var reason: String = {"empty ATP":"ATP below 10","offscreen":"outside the observed area","stale metabolism":"no recent feeding"}[condition]
			check.call(reason in run.ending,"The ending explains the specific missing condition")
		# Specific rivals pay ordinary costs on existing population introductions.
		sim = world()
		for stage in 3:
			run = sim.evolution
			run.clock = run.CRISIS_STARTS[stage]+31
			run.tide = mini(6,int(run.clock/120))
			run.resistance_clock = run.clock-1
			var rival = Sim.Cell.new(200+stage)
			rival.biomass = 100
			var before := rival.organic_mass()
			run.newcomer(rival,sim)
			check.call(rival.rival_name != "" and rival.biomass < 100 and is_equal_approx(rival.organic_mass(),before),"Named rivals buy functional anatomy without extra mass or immunity")
			var other = Sim.Cell.new(300+stage)
			run.newcomer(other,sim)
			check.call(other.rival_name == "","Each crisis names at most one rival without adding population")
	else: print("SKIPPED gameplay objectives: lineage crisis and victory checks (owner hold)")
	_archive(check,sim)

static func _archive(check: Callable, sim) -> void:
	var a = Archive.new()
	a.begin()
	var gene: String = sim.evolution.offers[0]
	sim.evolution.choose(gene)
	a.sync(sim)
	check.call(gene in a.discovered and a.expeditions.size() == 1,"Discoveries and family history are archived without granting power")
	var next = Sim.Evolution.new(992)
	var points: int = next.points
	check.call(a.recall(next,gene) and next.chosen and next.points == points,"Recalling consumes the ordinary draft choice, not installation resources")
	check.call(not a.recall(next,gene),"Recall cannot refresh or repeat a draft")
	# Use an isolated temporary fixture; never touch the player's actual history.
	a.path = "user://lineage-test-%d.json" % Time.get_ticks_usec()
	a.persist = true
	check.call(a.save_history(),"History writes an atomic JSON checkpoint")
	var b = Archive.new()
	b.persist = true
	b.path = a.path
	b.load_history()
	check.call(b.discovered == a.discovered and b.expeditions.size() == 1,"History and unlocked choices survive an application reload")
	var file := FileAccess.open(a.path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"discovered":42,"expeditions":[{"id":"bad","status":[],"seconds":"oops","family":[0,{"cause":[],"born":"bad","id":{}}]}]}))
	file.close()
	var corrupted = Archive.new()
	corrupted.path = a.path
	corrupted.persist = true
	corrupted.load_history()
	check.call(corrupted.discovered.is_empty() and corrupted.expeditions.size() == 1 and corrupted.expeditions[0].family.size() == 1,"Malformed history fields are sanitized before display")
	check.call(sim.lineage.biography(corrupted.expeditions[0].family[0]) is String,"Sanitized history remains readable")
	DirAccess.remove_absolute(a.path)
