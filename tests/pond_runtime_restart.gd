extends SceneTree
## Exercise the actual authority exit/restart contract in isolated storage.
const Host=preload("res://scripts/network/world_host.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var directory:=OS.get_environment("PRIMORDIA_RUNTIME_RESTART_STATE")
	if directory=="":quit(1);return
	var host=Host.new();host.cpu=true;host.port=22000+OS.get_process_id()%20000;host.store.directory=directory
	root.add_child(host)
	if not host.running:quit(1);return
	if "--die" in OS.get_cmdline_user_args():
		var marker:=FileAccess.open(directory.path_join("fixture-predecessor.txt"),FileAccess.WRITE)
		marker.store_string(host.world_id);marker.close()
		for cell in host.world.cells.duplicate():host.world._die(cell)
		print("POND_RUNTIME_EXIT waiting for durable automatic restart")
		# The next real authority physics callback must checkpoint and quit 75.
	else:
		var marker:=FileAccess.open(directory.path_join("fixture-predecessor.txt"),FileAccess.READ)
		var prior: String=marker.get_as_text();marker.close()
		assert(host.world_id!=prior and host.previous_world_id==prior and host.pond_restarts==1,"Automatic relaunch must archive and replace the empty world")
		assert(DirAccess.dir_exists_absolute(directory.path_join(host.pond_archive)),"Relaunch must retain the predecessor archive")
		assert(host.world.revision<10 and host.epoch==2,"Relaunch must start fresh time while advancing the authority epoch")
		print("POND_RUNTIME_RESUMED independent archive and new identity verified")
		host.stop()
