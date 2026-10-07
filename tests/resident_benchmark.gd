extends SceneTree
func _initialize() -> void: run.call_deferred()
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func run() -> void:
	var runner=load("res://scripts/resident_benchmark.gd").new()
	for key in ["count","threads","frames","fps_limit"]:
		var text := option("--"+key.replace("_","-"),str(runner.get(key)))
		if not text.is_valid_int():
			push_error("Invalid integer: "+key);quit(1);return
		runner.set(key,int(text))
	var seconds := option("--seconds","0")
	if not seconds.is_valid_float():
		push_error("Invalid seconds");quit(1);return
	runner.seconds=float(seconds)
	runner.backend=option("--backend","gpu")
	runner.interactions=option("--interactions","off")
	runner.grid_backend=option("--grid","radix")
	runner.distribution=option("--distribution","uniform")
	runner.output=option("--output","user://resident-report.json")
	runner.image_output=option("--image-output","")
	root.add_child(runner)
	runner.finished.connect(func(report):
		if report.has("error"): push_error(report.error)
		quit(1 if report.has("error") or not report.get("finite",false) or (runner.interactions!="chemistry" and report.get("material_before",-1)!=report.get("material_after",-2)) else 0))
	runner.begin()
