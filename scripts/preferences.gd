extends RefCounted
const SCALES := [0.85, 1.0, 1.25, 1.5, 1.75]
var hud_scale := 1.0
var fullscreen := false
var bloom := true
var music_volume := 0.65
var beat_pulse := 0.45
var persist := true
var path := "user://preferences.cfg"

func load_settings() -> void:
	if not persist: return
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	hud_scale = clampf(float(config.get_value("display","hud_scale",1.0)),0.85,1.75)
	fullscreen = bool(config.get_value("display","fullscreen",false))
	bloom = bool(config.get_value("display","bloom",true))
	music_volume = clampf(float(config.get_value("audio","music_volume",0.65)),0,1)
	beat_pulse = clampf(float(config.get_value("display","beat_pulse",0.45)),0,1)

func save_settings() -> void:
	if not persist: return
	var config := ConfigFile.new()
	config.set_value("display","hud_scale",hud_scale)
	config.set_value("display","fullscreen",fullscreen)
	config.set_value("display","bloom",bloom)
	config.set_value("audio","music_volume",music_volume)
	config.set_value("display","beat_pulse",beat_pulse)
	config.save(path)
