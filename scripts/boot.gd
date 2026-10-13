extends Node
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := "res://scenes/pond.tscn"
	if "--server" in args: scene="res://scenes/world_server.tscn"
	elif OS.has_feature("web") or Array(args).any(func(a):return a.begins_with("--connect=")):
		scene="res://scenes/network_client.tscn"
	get_tree().change_scene_to_file.call_deferred(scene)
