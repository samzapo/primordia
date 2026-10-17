extends SceneTree
## Offline tool, invoked by explicit experimental CD input after service stop.
func _initialize() -> void:
	var state:=""
	var confirmation:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--state-dir="):state=arg.trim_prefix("--state-dir=")
		if arg.begins_with("--confirm-sha="):confirmation=arg.trim_prefix("--confirm-sha=")
	var expected: String=OS.get_environment("HOME").path_join(".local/share/primordia-experimental/state")
	if OS.get_environment("RUNNER_NAME")!="samzapo-desktop" or OS.get_environment("PRIMORDIA_INSTANCE")!="experimental" or state.simplify_path()!=expected or confirmation.length()!=40 or confirmation!=OS.get_environment("PRIMORDIA_BUILD_SHA"):
		push_error("Reset requires the owned experimental state and explicit build confirmation");quit(1);return
	var host=preload("res://scripts/network/world_host.gd").new()
	host.store.directory=state
	var saved: Dictionary=host.store.load_latest()
	if saved.is_empty() or not host.store.last_error.is_empty():push_error("Reset requires a validated previous checkpoint");host.free();quit(1);return
	var fresh: Dictionary=preload("res://scripts/network/pond_reset.gd").prepare(saved)
	if fresh.has("error"):push_error(fresh.error);host.free();quit(1);return
	host.world=fresh.world;host.accounts=fresh.accounts
	host.previous_world_id=saved.world_id;host.world_id=Crypto.new().generate_random_bytes(16).hex_encode()
	host.epoch=int(saved.get("epoch",0));host.pond_restarts=int(saved.get("pond_restarts",0))+1
	# Replace both active generations only after the caller retains the stopped pair.
	if not host.checkpoint() or not host.checkpoint():
		push_error("Fresh pond checkpoint failed: "+host.store.last_error);host.free();quit(1);return
	print("POND_RESET "+JSON.stringify({"previous_world_id":host.previous_world_id,"world_id":host.world_id,"accounts":host.accounts.size(),"accounts_before":fresh.accounts_before,"cells":host.world.cells.size(),"build":confirmation}))
	host.free();quit()
