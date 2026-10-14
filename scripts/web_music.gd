extends RefCounted
## Web Audio presentation only. The authoritative world never reads this clock.
var cached: Dictionary={}
func initialize(volume: float) -> void:
	JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/music.js"))
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/music_bank_manifest.json"))
	if not manifest is Dictionary:return
	JavaScriptBridge.eval("window.primordiaMusic.init("+JSON.stringify(manifest)+","+str(volume)+")")
func status() -> Dictionary:
	var value=JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.primordiaMusic.status())")))
	if value is Dictionary:cached=value
	return cached
func reset() -> void:JavaScriptBridge.eval("window.primordiaMusic.reset()")
func schedule(start: int,events: Array,channels: Array,volume: float) -> void:
	JavaScriptBridge.eval("window.primordiaMusic.schedule("+str(start)+","+JSON.stringify(events)+","+JSON.stringify(channels)+","+str(volume)+")")
func volume(value: float) -> void:JavaScriptBridge.eval("window.primordiaMusic.setVolume("+str(value)+")")
