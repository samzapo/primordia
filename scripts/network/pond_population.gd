extends RefCounted
## Explicit server introductions; these are new inventories, never paid reproduction.
const Sim=preload("res://scripts/simulation.gd")
const MIN_LIVING := 15
const RESTART_EXIT := 75

static func living(world) -> Array:
	return world.cells.filter(func(cell):return not cell.dead and cell.health>0)

static func introduce(world,player: bool=false):
	if living(world).size()>=world.MAX_LIVE_CELLS:return null
	var cell=Sim.Cell.new(world.next_id)
	cell.role="player" if player else "grazer"
	cell.body=60.0 if player else world.rng.randf_range(14,32)
	cell.biomass=36.0 if player else 10.0
	cell.angle=world.rng.randf()*TAU
	cell.update_geometry()
	cell.membrane=Sim.Cell.Membrane.new(cell.radius,absi(world.seed_value*1000003+cell.id*9176))
	cell.add_organ("feeding",0 if player else 1.4,"graze",false)
	if not player:
		cell.add_organ("propulsion",PI,"graze",false)
		cell.add_organ("photosynthesis",0,"graze",false)
	cell.update_geometry()
	var placed:=false
	for attempt in 256:
		var at:=Vector2(world.rng.randf()*Sim.WORLD.x,world.rng.randf()*Sim.WORLD.y)
		if world.safe_birth_position(at,cell.extent()):
			cell.position=at;cell.previous_position=at;placed=true;break
	if not placed:return null
	cell.previous_angle=cell.angle
	cell.sense_clock=(cell.id%9)/60.0
	world.next_id+=1
	world.cells.append(cell)
	return cell

static func enroll(world,account: Dictionary,cell,keep_history: bool=true) -> void:
	if keep_history and account.has("lineage"):
		var history: Array=account.get("previous_lineages",[])
		history.append({"root":account.root,"ended":world.time,"lineage":account.lineage})
		account.previous_lineages=history.slice(maxi(0,history.size()-8))
	var ledger=world._family_ledger(cell)
	var record: Dictionary=ledger.record_for(cell.id)
	if record.is_empty():ledger.register(cell,-1,cell.generation,"active",world.time)
	else:record.state="active"
	var evolution=Sim.Evolution.new(world.seed_value^cell.id);evolution.sandbox=true
	account.root=cell.lineage_id();account.selected=cell.id;account.current=cell
	ledger.progression=evolution
	account.lineage=ledger;account.evolution=evolution;account.edit=int(account.get("edit",0))+1
	account.erase("restart_at")
	cell.role="player"

static func replenish(world) -> int:
	var added:=0
	for missing in maxi(0,MIN_LIVING-living(world).size()):
		if introduce(world)==null:break
		added+=1
	return added

static func fresh(accounts: Dictionary) -> Dictionary:
	var seed_number:=int(Crypto.new().generate_random_bytes(4).decode_u32(0)&0x7fffffff)
	var world=Sim.new(seed_number)
	world.server_mode=true;world.evolution.sandbox=true;world.pending_replacements.clear()
	var founders:=living(world)
	if accounts.size()>founders.size():return {"error":"Initial pond cannot hold all retained accounts"}
	var index:=0
	for account in accounts.values():
		enroll(world,account,founders[index],false)
		# Old-world command receipts cannot authorize an edit in a new pond.
		account.receipts={};account.erase("previous_lineages")
		index+=1
	return {"world":world}
