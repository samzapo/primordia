extends RefCounted
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Lineage=preload("res://scripts/lineage.gd")
static func run(check: Callable) -> void:
	var ledger=Lineage.new();ledger.root_id=41
	var first=Sim.Cell.new(41);var child=Sim.Cell.new(42);child.lineage=41
	ledger.register(first,-1,0,"active",0);ledger.register(child,41,1,"living",1)
	ledger.register(child,41,1,"living",1)
	check.call(ledger.statistics()=={"generation":1,"total":2},"Actual cell registration tracks generation and lifetime total without duplicates")
	var world=Sim.new(615,0,false);world.cells=[first,child];world.player=first;world.lineage=ledger
	ledger.died(child,world)
	check.call(ledger.records.size()==1 and ledger.record_for(child.id).is_empty() and ledger.total_cells==2,"A deceased relative is removed while the total remains")
	check.call(ledger.highest_generation==1,"Losing the youngest generation cannot erase lineage progress")
	var retained=Codec.new().restore(Codec.new().capture(ledger))
	check.call(retained.statistics()==ledger.statistics() and retained.records==ledger.records,"Summary counters persist independently of individual histories")
	var account: Dictionary={"root":41,"selected":41,"current":first,"lineage":ledger,"evolution":Sim.Evolution.new(615),"access_hash":"isolated-private-fixture","display_name":"Fixture player","seen_release":"2026-10-17-clear-building","sequence":8,"edit":3,"receipts":{8:{"ok":true}}}
	var saved: Dictionary={"world_id":"a".repeat(32),"epoch":3,"tick":10,"graph":Codec.new().capture({"world":world,"accounts":{"fixture-session":account}})}
	var original: PackedByteArray=var_to_bytes(saved)
	var result: Dictionary=preload("res://scripts/network/pond_reset.gd").prepare(saved)
	check.call(not result.has("error") and result.world!=world and result.world.time==0,"An explicit pond reset creates new ecology, not a restart of old bodies")
	var fresh: Dictionary=result.accounts["fixture-session"]
	check.call(fresh.access_hash==account.access_hash and fresh.display_name==account.display_name and fresh.seen_release==account.seen_release,"A reset retains access credentials, names and update acknowledgements")
	check.call(fresh.sequence==8 and fresh.edit==4 and fresh.receipts.is_empty() and not fresh.has("previous_lineages"),"Old-world edits/history cannot authorize actions in the fresh pond")
	check.call(not fresh.current.dead and result.world.cells.has(fresh.current) and fresh.lineage.total_cells>0,"Retained accounts attach to an actual fresh living lineage")
	check.call(var_to_bytes(saved)==original,"Reset preparation leaves the retained predecessor unchanged")
	check.call(result.world.cells.all(func(cell):return cell.organs.all(func(organ):return organ.kind!="sanctuary")),"Fresh worlds contain no removed Sanctuary")

	var notes=preload("res://scripts/network/release_notes.gd")
	var pending: Array=notes.pending_all({},"experimental")
	check.call(pending.all(func(note):return note.items.all(func(item):return not item.contains("or Sanctuary"))),"Missed update notices never offer the withdrawn Sanctuary")
