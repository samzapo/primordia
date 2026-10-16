extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool,text: String) -> void:
	assertions += 1
	if not ok: failures += 1; push_error(text)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512,320); viewport.disable_3d = true; viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var field = preload("res://scripts/acidity.gd").new()
	var at := Vector2(2080,1312)
	var texture := ImageTexture.create_from_image(Image.create_from_data(64,40,false,Image.FORMAT_RF,field.values.to_byte_array()))
	var lit := PackedFloat32Array(); lit.resize(2560); lit.fill(.35)
	var light := ImageTexture.create_from_image(Image.create_from_data(64,40,false,Image.FORMAT_RF,lit.to_byte_array()))
	var background := ColorRect.new(); background.size = viewport.size
	background.material = ShaderMaterial.new(); background.material.shader = preload("res://shaders/light.gdshader")
	var material: ShaderMaterial = background.material
	material.set_shader_parameter("camera",at)
	material.set_shader_parameter("view_size",Vector2(512,320))
	material.set_shader_parameter("screen_center",Vector2(.5,.5))
	material.set_shader_parameter("fractal_color",false); material.set_shader_parameter("water_ripples",false)
	material.set_shader_parameter("acidity_map",texture); material.set_shader_parameter("light_map",light)
	viewport.add_child(background)
	for i in 4: await process_frame
	RenderingServer.force_draw(false)
	var neutral: Image = viewport.get_texture().get_image()
	field.exchange(at,.15)
	texture.update(Image.create_from_data(64,40,false,Image.FORMAT_RF,field.values.to_byte_array()))
	for i in 4: await process_frame
	RenderingServer.force_draw(false)
	var acid: Image = viewport.get_texture().get_image()
	for dx in [0,80,-80]:
		var n := neutral.get_pixel(256+dx,160)
		var a := acid.get_pixel(256+dx,160)
		check(a.r-n.r > .04,"Low-dose acid visibly tints water at the source and beyond the old single-node footprint")
	var removed: float = field.exchange(at,-.15)
	check(absf(removed+.15)<.000001,"The buffer removes the same finite acid-equivalent quantity")
	texture.update(Image.create_from_data(64,40,false,Image.FORMAT_RF,field.values.to_byte_array()))
	for i in 4: await process_frame
	RenderingServer.force_draw(false)
	var buffered: Image = viewport.get_texture().get_image()
	for dx in [0,80,-80]:
		check(buffered.get_pixel(256+dx,160).is_equal_approx(neutral.get_pixel(256+dx,160)),"Buffer neutralization restores the original blue over the full tint footprint")
	if OS.has_environment("PRIMORDIA_WATER_CAPTURE"): acid.save_png(OS.get_environment("PRIMORDIA_WATER_CAPTURE"))
	viewport.queue_free(); await process_frame
	print("WATER TINT GPU: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
