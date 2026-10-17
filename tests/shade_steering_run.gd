extends SceneTree
var assertions:=0
var failures:=0
func check(ok: bool,why: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(why)
func _initialize() -> void:
 preload("res://tests/shade_steering.gd").run(check)
 print("SHADE STEERING: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
