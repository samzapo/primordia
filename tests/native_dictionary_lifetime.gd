extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var path:="res://build/native/dictionary_probe.gdextension"
 if GDExtensionManager.load_extension(path)!=GDExtensionManager.LOAD_STATUS_OK:
  push_error("Cannot load native Dictionary lifetime fixture");quit(1);return
 var probe=ClassDB.instantiate("PrimordiaDictionaryLifetime")
 var failures:=0
 probe.exercise(100,true);probe.exercise(100,false)
 for copy in [true,false,true,false]:
  var before:=OS.get_static_memory_usage()
  var last: int=probe.exercise(10000,copy)
  var retained:=OS.get_static_memory_usage()-before
  print("DICTIONARY_LIFETIME ",JSON.stringify({"copy":copy,"iterations":10000,"retained_bytes":retained}))
  if last!=9999 or retained>4096:
   failures+=1;push_error("Dictionary replacement retained old owners or changed values")
 probe=null
 print("DICTIONARY_RESULT: 8 assertions, %d failures" % failures)
 quit(0 if failures==0 else 1)
