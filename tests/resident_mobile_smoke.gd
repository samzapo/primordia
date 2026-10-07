extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/resident_mobile.tscn").instantiate()
	root.add_child(scene)
	scene.counts.select(0)
	scene._start()
	scene.runner.seconds=0
	scene.runner.frames=10
	var report: Dictionary=await scene.runner.finished
	if report.has("error"):
		push_error(report.error);quit(1);return
	if not report.finite or report.material_before!=report.material_after:
		push_error("Portable smoke lost material");quit(1);return
	await process_frame
	if not scene.modes.is_item_disabled(1): scene.modes.select(1)
	scene._start()
	scene.runner.seconds=0;scene.runner.frames=10
	report=await scene.runner.finished
	await process_frame
	if report.has("error"): push_error(report.error);quit(1);return
	scene._start()
	await process_frame
	scene.runner.cancel()
	report=await scene.runner.finished
	if not report.has("error"): push_error("Cancelled run must be invalid");quit(1);return
	print("MOBILE_SMOKE passed GPU/native repeated initialization and cancellation")
	quit()
