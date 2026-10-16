extends SceneTree
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(text)
func _initialize() -> void:
 preload("res://tests/plant_flow.gd").run(check)
 print("PLANT FLOW: %d assertions, %d failures" % [assertions,failures])
 quit(0 if failures==0 else 1)
