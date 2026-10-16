extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool,text: String) -> void:
	assertions += 1
	if not ok: failures += 1; push_error(text)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(840,1400)
	var game = load("res://scenes/pond.tscn").instantiate(); game.use_particle_pool = false
	root.add_child(game); game.set_process(false); game.set_physics_process(false)
	game.music.enabled = false; game.music.player.stop()
	game.touch_zoom.enabled = true; game.touch_zoom.pixels = 2
	var cell = game.world.player
	var mouth: Dictionary = cell.organs.filter(func(o):return cell.inherent(o))[0].duplicate(true)
	cell.organs = [mouth]; mouth.a = 0.0
	cell.biomass = 5; cell.body = 16; cell.brood_mass = 0; cell.brood_energy = 0
	cell.update_geometry()
	cell.membrane = preload("res://scripts/membrane.gd").new(cell.radius)
	cell.update_geometry()
	for frame in 24: cell.membrane.step(1.0/60,cell.radius,Vector2.ZERO,frame/60.0)
	cell.angle = -PI/2; cell.previous_angle = cell.angle; cell.render_revision += 1
	var other = game.Simulation.Cell.clone_state(cell)
	other.id = 990; other.lineage = 990; other.position += Vector2(18,8); other.previous_position = other.position
	game.world.cells = [cell,other]; game.manual_zoom = 12
	game._update_world(1); game.touch_zoom.layout(); game.cell_ui.sync(0)
	for frame in 8: await process_frame
	var image := root.get_texture().get_image()
	for i in 3:
		var factory = game.cell_ui.interior
		var local: Vector2 = factory.anchors.chemistry+Vector2((i-1)*.10,abs(i-1)*.07)*factory.anchors.radius
		var at: Vector2 = root.get_final_transform()*(factory.get_global_transform_with_canvas()*local)
		var color := image.get_pixelv(Vector2i(at))
		check(color.g > color.r+.18 and color.b > color.r+.15,"Small-cell chemical chambers remain visible above every appendage and uncontrolled body")
	check(game.views[cell.id].z_index > game.views[other.id].z_index+1,"Controlled foreground ordering is used by the actual rendered scene")
	if OS.has_environment("PRIMORDIA_ANATOMY_CAPTURE"): image.save_png(OS.get_environment("PRIMORDIA_ANATOMY_CAPTURE"))
	game.queue_free(); await process_frame
	print("ANATOMY RENDER GPU: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
