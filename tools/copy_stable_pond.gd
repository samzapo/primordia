extends SceneTree
## Deployment-only: reads an isolated stable snapshot, writes experimental only.
func _initialize() -> void:
	var values: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var pair := arg.trim_prefix("--").split("=",true,1)
			values[pair[0]] = pair[1]
	var root: String = OS.get_environment("HOME").path_join(".local/share/primordia-experimental")
	var state: String = str(values.get("state-dir","")).simplify_path()
	var snapshot: String = str(values.get("snapshot-dir","")).simplify_path()
	var confirmation: String = str(values.get("confirm-sha",""))
	if OS.get_environment("RUNNER_NAME")!="samzapo-desktop" or OS.get_environment("PRIMORDIA_INSTANCE")!="experimental" or state!=root.path_join("state") or snapshot.get_base_dir()!=root or not snapshot.get_file().begins_with("stable-pond-snapshot-") or confirmation.length()!=40 or confirmation!=OS.get_environment("PRIMORDIA_BUILD_SHA"):
		push_error("Pond copy requires the owned experimental destination and build confirmation")
		quit(1)
		return
	var report: Dictionary = preload("res://scripts/network/pond_fork.gd").write(snapshot,state,str(values.get("source-world","")),confirmation)
	if report.has("error"):
		push_error(report.error)
		quit(1)
		return
	print("POND_COPY "+JSON.stringify(report))
	quit()
