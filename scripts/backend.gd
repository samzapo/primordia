extends RefCounted
## Batched native kernels are optional for editor/headless portability.
static var attempted := false
static var loaded := false
static func native_available() -> bool:
	if not attempted:
		attempted = true
		var path := "res://build/native/primordia.gdextension"
		if FileAccess.file_exists(path):
			var status := GDExtensionManager.load_extension(path)
			loaded = status in [GDExtensionManager.LOAD_STATUS_OK,GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]
	return loaded and ClassDB.class_exists("PrimordiaKernels")
static func create():
	if OS.get_environment("PRIMORDIA_BACKEND") == "script" or not native_available(): return null
	return ClassDB.instantiate("PrimordiaKernels")
