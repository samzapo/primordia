extends SceneTree
const Store = preload("res://scripts/network/world_store.gd")
const Fork = preload("res://scripts/network/pond_fork.gd")
const Sim = preload("res://scripts/simulation.gd")
const Codec = preload("res://scripts/network/state_codec.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var scratch: String = OS.get_environment("PRIMORDIA_FORK_FIXTURE")
	if scratch.is_empty():
		quit(1)
		return
	var source := Store.new()
	source.directory = scratch.path_join("source")
	var target := Store.new()
	target.directory = scratch.path_join("experimental")
	var world = Sim.new(28,0,false)
	world.cells = [world.player]
	world.player.biomass = 27.5
	world.player.energy = 42.25
	world.player.add_organ("toxin",1,"graze",false)
	world.player.chemistry.emit("food",3,Vector2(4,2))
	var npc = Sim.Cell.new(78,Vector2(200,100))
	npc.biomass = 29
	world.cells.append(npc)
	var accounts := {"fixture-token-hash":{"root":world.player.lineage_id(),"selected":world.player.id,"current":world.player,"display_name":"Fixture","access_hash":"fixture-access-hash","sequence":17,"receipts":{17:{"ok":true}}}}
	var saved := {"world_id":"0123456789abcdef0123456789abcdef","epoch":3,"tick":734,"build":"stable-fixture","gpu_tick":217,"stream_rng":PackedInt64Array([3,19]),"graph":Codec.new().capture({"world":world,"accounts":accounts})}
	check(source.save(saved) and source.save(saved),"Stable fixture publishes both generations")
	var source_bytes := FileAccess.get_file_as_bytes(source.directory.path_join("world-0.pworld"))
	var old := saved.duplicate(true)
	old.world_id = "old-experimental"
	old.epoch = 55
	target.sequence = 100
	check(target.save(old) and target.save(old),"Experimental predecessor has newer slot sequence")
	DirAccess.make_dir_recursive_absolute(target.directory.path_join("feedback"))
	var feedback := target.directory.path_join("feedback/report.json")
	var file := FileAccess.open(feedback,FileAccess.WRITE)
	file.store_string("private experimental fixture")
	file.close()
	var report := Fork.write(source.directory,target.directory,saved.world_id,"candidate-fixture")
	check(not report.has("error") and report.get("graph_unchanged",false),"Copy succeeds with the exact serialized graph")
	var forked := target.load_latest()
	check(forked.world_id != saved.world_id and forked.world_id != old.world_id,"Every update gets an independent experimental world")
	check(forked.epoch == 55 and target.sequence > 102,"Older source cannot lose to previous experimental slots")
	check(forked.tick == saved.tick and forked.gpu_tick == saved.gpu_tick and forked.stream_rng == saved.stream_rng,"Simulation/GPU clocks and random streams are retained")
	check(var_to_bytes(forked.graph) == var_to_bytes(saved.graph),"All cells, chemistry, resources, accounts and receipts copy exactly")
	check(report.cells == 2 and report.accounts == 1,"Every body and player account is retained")
	check(FileAccess.get_file_as_bytes(source.directory.path_join("world-0.pworld")) == source_bytes,"Stable checkpoint bytes remain untouched")
	check(FileAccess.get_file_as_string(feedback) == "private experimental fixture","Experimental feedback is not replaced")
	var first_id: String = forked.world_id
	var before := FileAccess.get_file_as_bytes(target.directory.path_join("world-0.pworld"))
	check(Fork.write(source.directory,target.directory,"wrong-world","candidate").has("error"),"A changed stable world fails closed")
	check(FileAccess.get_file_as_bytes(target.directory.path_join("world-0.pworld")) == before,"Rejected source does not replace experimental")
	world.player.energy += 5
	saved.tick += 1
	saved.graph = Codec.new().capture({"world":world,"accounts":accounts})
	check(source.save(saved),"Stable moves forward between updates")
	var next := Fork.write(source.directory,target.directory,saved.world_id,"next-candidate")
	check(not next.has("error") and next.source_tick == 735 and next.world_id != first_id,"Next update takes a fresh main snapshot with a new identity")
	check(var_to_bytes(target.load_latest().graph) == var_to_bytes(saved.graph),"Previous experimental progress is replaced by the new stable graph")
	# A corrupt newest generation must select the older valid published source.
	file = FileAccess.open(source.directory.path_join("world-1.pworld"),FileAccess.WRITE)
	file.store_string("corrupt newest")
	file.close()
	var fallback := Fork.write(source.directory,target.directory,saved.world_id,"fallback")
	check(not fallback.has("error") and fallback.source_tick == 734,"Older valid checkpoint is used when newest is corrupt")
	var restored = Codec.new().restore(target.load_latest().graph)
	check(restored.accounts["fixture-token-hash"].current == restored.world.player,"Account-to-body shared references survive the fork")
	check(restored.world.player.organs.size() == world.player.organs.size() and restored.world.cells.size() == 2,"Actual anatomy and NPC bodies survive decode")
	print("POND FORK: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
