extends SceneTree
var assertions:=0
var failures:=0
func expect(ok: bool,text: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 await preload("res://tests/interface.gd").new().run(self)
 print("SHARED INTERFACE: %d assertions, %d failures" % [assertions,failures])
 quit(0 if failures==0 else 1)
