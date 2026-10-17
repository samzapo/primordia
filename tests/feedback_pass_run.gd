extends SceneTree
var assertions:=0
var failures:=0
func expect(ok: bool,why: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(why)
func _initialize() -> void:
 preload("res://tests/feedback_pass_two.gd").run(expect)
 print("FEEDBACK PASS: %d assertions, %d failures" % [assertions,failures])
 quit(0 if failures==0 else 1)
