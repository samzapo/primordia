extends RefCounted
## Current living family and lifetime counters; reproduction makes living daughters.
var root_id := 0
var dormant: Array = [] # Retired checkpoint field; discarded on the next authority tick.
var records: Array = []
var notices: Array[String] = []
var serial := 0
var recovery_clock := 0.0
var founder_material := 0.0
var progression # Shared with the owning account; checkpoint graph preserves identity.
var births := 0
var deaths := 0
var total_cells:=0
var highest_generation:=0

func initialize(sim) -> void:
	register(sim.player,-1,0,"active",sim.time)

func stored_material() -> float:
	var amount := 0.0
	for cell in dormant: amount += cell.organic_mass()
	return amount

func discard_stored(sim) -> void:
	# Owner retires old banked bodies without hatching or replacing them.
	if dormant.is_empty():return
	for cell in dormant:
		sim.build_waste+=cell.organic_mass()
		records.erase(record_for(cell.id))
		sim.inherited_lineages.erase(cell.id)
		sim.investment.cells.erase(cell.id);sim.investment.npc.erase(cell.id)
	dormant.clear()

func active_family(sim) -> Array:
	var family: Array = []
	for cell in sim.cells:
		if not cell.dead and cell.health > 0 and cell.lineage_id() == root_id: family.append(cell)
	return family

func register(cell, parent: int, generation: int, state: String, now: float) -> void:
	cell.generation = generation
	if not record_for(cell.id).is_empty():return
	total_cells+=1;highest_generation=maxi(highest_generation,generation)
	records.append({"id":cell.id,"parent":parent,"generation":generation,"state":state,"born":now})
	# Only current living records remain; totals outlive individual cells.

func record_for(identity: int) -> Dictionary:
	for record in records:
		if record.id == identity: return record
	return {}

func notify(value: String) -> void:
	serial += 1
	notices.append(value)
	if notices.size() > 8: notices.pop_front()

func died(cell, sim) -> void:
	if cell.lineage_id() != root_id: return
	var record := record_for(cell.id)
	if record.is_empty() or record.state == "dead": return
	records.erase(record)
	deaths += 1
	notify("Generation %d lost · %s\nIts family and habitat continue." % [cell.generation,cell.death_hint])

func adopted(cell, sim, _hatched: bool) -> void:
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
	notify("%s · generation %d\n%s" % ["Family continues",cell.generation,sim.evolution.objective(sim)])
	sim._record_sound("division",cell.position,cell.id)

func recover(sim, _dt: float) -> bool:
	if not sim.player.dead and sim.player.health > 0: return true
	var family := active_family(sim)
	if not family.is_empty():
		family.sort_custom(func(a,b): return a.generation > b.generation if a.generation != b.generation else a.health > b.health)
		adopted(family[0],sim,false)
		return true
	sim.evolution.fail("EXPEDITION ENDED · No living family remains.\nYour lineage's generation and lifetime total are retained.")
	return false

func statistics() -> Dictionary:
	return {"generation":highest_generation,"total":total_cells}

func summary(sim) -> String:
	var stats:=statistics()
	return "Generation %d · %d total cells\n%d living family" % [stats.generation,stats.total,active_family(sim).size()]

func biography(record: Dictionary) -> String:
	return "Generation %d · cell %d · %s" % [record.generation,record.id,record.state]
