extends SceneTree
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,320);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var sim=preload("res://scripts/simulation.gd").new(58,0,false)
	sim._die(sim.player)
	var view=preload("res://scripts/death_view.gd").new();viewport.add_child(view);view.position=Vector2(160,160)
	view.sync(sim,sim.death_bursts[0].at,1,0)
	for frame in 4:await process_frame
	var image:=viewport.get_texture().get_image();var pixels:=0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a>.05:pixels+=1
	check(pixels>100,"Actual membrane rupture fragments produce visible pixels")
	check(image.get_pixel(160,160).a<.01,"Rupture remains an outline effect rather than a filled substitute cell")
	if OS.has_environment("PRIMORDIA_DEATH_CAPTURE"):image.save_png(OS.get_environment("PRIMORDIA_DEATH_CAPTURE"))
	view.sync(sim,sim.death_bursts[0].at,1,2)
	for frame in 3:await process_frame
	image=viewport.get_texture().get_image();pixels=0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a>.01:pixels+=1
	check(pixels==0 and view.bursts.is_empty(),"Expired fragments clear completely and cannot replay the retained fact")
	viewport.queue_free();await process_frame
	print("DEATH RENDER GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
