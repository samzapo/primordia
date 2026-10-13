extends SceneTree
var assertions := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)
func _run() -> void:
	preload("res://tests/chemical_particles.gd").run(expect)
	print("RESULT: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
