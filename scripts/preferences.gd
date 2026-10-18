extends RefCounted
const SCALES := [0.85, 1.0, 1.25, 1.5, 1.75]
var hud_scale := 1.0
var fullscreen := false
var bloom := true
var water_ripples := true
var current_style := "crests"
var music_volume := 0.65
var persist := true
var path := "user://preferences.cfg"

func load_settings() -> void:
	if not persist: return
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	hud_scale = clampf(float(config.get_value("display","hud_scale",1.0)),0.85,1.75)
	fullscreen = bool(config.get_value("display","fullscreen",false))
	bloom = bool(config.get_value("display","bloom",true))
	water_ripples = bool(config.get_value("display","water_ripples",true))
	current_style = str(config.get_value("display","current_style","crests"))
	if current_style not in ["crests","streamlines"]:current_style="crests"
	music_volume = clampf(float(config.get_value("audio","music_volume",0.65)),0,1)

func save_settings() -> void:
	if not persist: return
	var config := ConfigFile.new()
	config.set_value("display","hud_scale",hud_scale)
	config.set_value("display","fullscreen",fullscreen)
	config.set_value("display","bloom",bloom)
	config.set_value("display","water_ripples",water_ripples)
	config.set_value("display","current_style",current_style)
	config.set_value("audio","music_volume",music_volume)
	config.save(path)
