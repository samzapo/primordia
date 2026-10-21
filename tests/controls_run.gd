extends SceneTree
var assertions:=0
var failures:=0
func expect(value: bool,message: String) -> void:
	assertions+=1
	if not value:failures+=1;push_error("FAIL: "+message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	await preload("res://tests/controls.gd").new().run(self)
	print("TOUCH CONTROLS: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
