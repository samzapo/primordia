extends RefCounted
## A bounded family ledger and actual prepaid dormant bodies, never respawn credit.
const MAX_DORMANT := 3
const MAX_ACTIVE := 4
var dormant: Array = []
var records: Array = []
var notices: Array[String] = []
var serial := 0
var recovery_clock := 0.0
var founder_material := 0.0
var births := 0
var deaths := 0

func initialize(sim) -> void:
	register(sim.player,-1,0,"active",sim.time)
	# Part of the initial population inventory, separate from the active founder.
	var reserve = sim.make_offspring(sim.player,sim.offspring_quote())
	reserve.id = sim.next_id
	sim.next_id += 1
	reserve.generation = 0
	reserve.position = sim.player.position
	reserve.previous_position = reserve.position
	reserve.oxygen = 12
	dormant.append(reserve)
	founder_material = reserve.organic_mass()
	sim.inherited_lineages[reserve.id] = reserve.lineage_id()
	register(reserve,-1,0,"dormant",sim.time)

func stored_material() -> float:
	var amount := 0.0
	for cell in dormant: amount += cell.organic_mass()
	return amount

func active_family(sim) -> Array:
	var family: Array = []
	for cell in sim.cells:
		if not cell.dead and cell.health > 0 and cell.lineage_id() == 0: family.append(cell)
	return family

func register(cell, parent: int, generation: int, state: String, now: float) -> void:
	cell.generation = generation
	records.append({"id":cell.id,"parent":parent,"generation":generation,"state":state,"born":now,"ended":-1.0,"cause":"","food":0.0,"fixed":0.0})
	# At most seven physical family members; old history is presentation only.
	if records.size() > 128: records.pop_front()

func record_for(identity: int) -> Dictionary:
	for record in records:
		if record.id == identity: return record
	return {}

func notify(value: String) -> void:
	serial += 1
	notices.append(value)
	if notices.size() > 8: notices.pop_front()

func died(cell, sim) -> void:
	if cell.lineage_id() != 0: return
	var record := record_for(cell.id)
	if record.is_empty() or record.state == "dead": return
	record.state = "dead"
	record.ended = sim.time
	record.food = cell.processed
	record.fixed = cell.fixed_carbon
	record.cause = cell.death_hint
	deaths += 1
	notify("Generation %d lost · %s\nIts family and habitat continue." % [cell.generation,record.cause])

func adopted(cell, sim, hatched: bool) -> void:
	if sim.player.dead: sim.cells.erase(sim.player)
	else:
		sim.player.role = "ancestor"
		var previous := record_for(sim.player.id)
		if not previous.is_empty(): previous.state = "living"
	sim.player = cell
	cell.role = "player"
	cell.activity = 1
	cell.previous_position = cell.position
	cell.previous_angle = cell.angle
	var record := record_for(cell.id)
	if not record.is_empty(): record.state = "active"
	sim.evolution.observe_successor(cell)
	notify("%s · generation %d\n%s" % ["Reserve hatched" if hatched else "Family continues",cell.generation,sim.evolution.objective(sim)])
	sim._record_sound("division",cell.position,cell.id)

func recover(sim, dt: float) -> bool:
	if not sim.player.dead and sim.player.health > 0: return true
	var family := active_family(sim)
	if not family.is_empty():
		# Prefer the youngest generation, then the healthiest known family member.
		family.sort_custom(func(a,b): return a.generation > b.generation if a.generation != b.generation else a.health > b.health)
		adopted(family[0],sim,false)
		return true
	if dormant.is_empty():
		sim.evolution.fail("EXPEDITION ENDED · No living family or dormant reserves remain.\nYour family history and discovered blueprints are retained.")
		return false
	recovery_clock -= dt
	if recovery_clock > 0: return false
	recovery_clock = 0.5
	var child = dormant[0]
	var origin: Vector2 = child.position
	for ring in range(0,6):
		for i in 16:
			var at: Vector2 = sim.Medium.wrap_position(origin+Vector2.from_angle(TAU*i/16)*(ring*110))
			if not sim.safe_birth_position(at,child.extent()): continue
			child.position = at
			child.previous_position = at
			dormant.pop_front()
			sim.cells.append(child)
			adopted(child,sim,true)
			return true
	# Remain in the same world until there is room; never discard a funded body.
	return false

func summary(sim) -> String:
	return "%d living family · %d dormant / %d\n%s" % [active_family(sim).size(),dormant.size(),MAX_DORMANT,sim.evolution.objective(sim)]

func biography(record: Dictionary) -> String:
	return "Generation %d · cell %d · %s\nParent %s · born %.0fs%s" % [record.generation,record.id,record.state,"founder" if record.parent < 0 else str(record.parent),record.born,
		"\nLost at %.0fs: %s\nMetabolized %.1f · fixed %.1f carbon" % [record.ended,record.cause,record.food,record.fixed] if record.state == "dead" else ""]
