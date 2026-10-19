extends RefCounted
## Copy the exact data graph; only the independent pond envelope changes.
const Store = preload("res://scripts/network/world_store.gd")
const Retention = preload("res://scripts/network/cell_retention.gd")

static func write(snapshot: String, destination: String, expected_world: String, build: String) -> Dictionary:
	var source := Store.new()
	source.directory = snapshot
	var saved: Dictionary = source.load_latest()
	if saved.is_empty() or not source.last_error.is_empty():
		return {"error":"Stable snapshot has no valid checkpoint"}
	if saved.get("world_id","") != expected_world or not saved.get("graph") is Dictionary:
		return {"error":"Stable snapshot identity does not match the running pond"}
	var graph: Dictionary = saved.graph
	if not graph.get("root",{}).get("accounts") is Dictionary or not graph.root.has("world"):
		return {"error":"Stable snapshot has no world/account graph"}
	var output := Store.new()
	output.directory = destination
	var prior: Dictionary = output.load_latest()
	if not output.last_error.is_empty():
		return {"error":"Experimental predecessor is invalid"}
	var fork: Dictionary = saved.duplicate(true)
	fork.world_id = Crypto.new().generate_random_bytes(16).hex_encode()
	fork.epoch = maxi(int(saved.get("epoch",0)),int(prior.get("epoch",0)))
	fork.build = build
	fork.previous_world_id = expected_world
	fork.pond_archive = ""
	output.sequence = maxi(output.sequence,source.sequence)
	if not output.save(fork) or not output.save(fork):
		return {"error":"Cannot durably publish experimental copy: "+output.last_error}
	var restored: Dictionary = output.load_latest()
	if var_to_bytes(restored) != var_to_bytes(fork):
		return {"error":"Experimental copy did not round-trip exactly"}
	var cells: Dictionary = Retention.manifest(saved)
	return {"source_world_id":expected_world,"source_build":saved.get("build",""),
		"source_tick":saved.get("tick",-1),"world_id":fork.world_id,
		"epoch":fork.epoch,"accounts":graph.root.accounts.size(),
		"cells":cells.cells.size(),"cells_digest":cells.digest,
		"graph_sha256":Retention.digest(graph),"graph_unchanged":var_to_bytes(graph)==var_to_bytes(restored.graph)}
