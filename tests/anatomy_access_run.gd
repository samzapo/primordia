extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool,text: String) -> void:
	assertions += 1
	if not ok: failures += 1; push_error(text)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1170,2100)
	var game = load("res://scenes/pond.tscn").instantiate()
	game.use_particle_pool = false
	root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	game.music.enabled = false; game.music.player.stop()
	game.touch_zoom.enabled = true; game.touch_zoom.pixels = 3
	var cell = game.world.player
	var family = game.Simulation.Cell.clone_state(cell)
	family.id = 901; family.lineage = cell.lineage_id()
	family.position += Vector2(160,0); family.previous_position = family.position
	var foreign = game.Simulation.Cell.clone_state(cell)
	foreign.id = 902; foreign.lineage = 902
	foreign.position = cell.position; foreign.previous_position = foreign.position
	game.world.cells = [cell,family,foreign]
	game.manual_zoom = 3; game._update_world(1)
	for mode in ["exteroception","interoception"]:
		game.perception = mode; game._update_world(1)
		check(game.views[cell.id].z_index > game.views[foreign.id].z_index+game.views[foreign.id].appendages.z_index,"Controlled body covers unrelated bodies and appendages in either perception")
		check(game.views[family.id].z_index > game.views[foreign.id].z_index+1,"Owned family draws over uncontrolled lineages")
		check(game.cell_ui.interior.z_index > game.views[cell.id].z_index+1,"Factories remain above the controlled cell's appendages")
	game.perception = "exteroception"; game._update_world(1)
	game._toggle_build()
	cell = game.world.player
	var ui = game.cell_ui
	var anchors: Dictionary = ui.interior.anchors.duplicate()
	ui.interior.anchors.chemistry = ui.interior.anchors.assembly
	var target: Dictionary = ui.pick(ui.screen_at({"kind":"chemistry"}))
	check(target.kind == "overlap" and target.targets.any(func(t):return t.kind == "chemistry") and target.targets.any(func(t):return t.kind == "assembly"),"An overlapping factory cannot be lost to the nearest drawn control")
	ui.open_context(target)
	var chemical_choices: Array = ui.choices.filter(func(choice):return choice.caption == "Chemistry factory")
	check(chemical_choices.size() == 1 and chemical_choices[0].get_parent() == ui.mobile_flow,"Overlapping mobile structures have separate top-tray choices")
	chemical_choices[0].pressed.emit()
	check(ui.context.kind == "chemistry" and ui.choices.any(func(choice):return choice.kind == "acidifying"),"The obscured factory still opens its functional gland actions")
	ui.interior.anchors = anchors
	ui.close_context()
	cell.biomass = 100
	cell.add_organ("photosynthesis",2,"graze",false)
	var leaf: Dictionary = cell.organs[-1]
	game.world.evolution.learned.clear()
	var stock: Array = [cell.biomass,cell.energy,game.world.player.ap,leaf.material,leaf.hp,leaf.max_hp]
	for gene in ["shade_leaf","sun_leaf","shade_leaf"]:
		check(game.world.edit("mutate",{"id":leaf.id,"gene":gene}) and leaf.mutation == gene,"Sun/shade changes are accepted without random blueprint discovery")
	check(stock == [cell.biomass,cell.energy,game.world.player.ap,leaf.material,leaf.hp,leaf.max_hp],"Changing light adaptation never creates resources or compounds organ health")
	ui.open_context({"kind":"organ","id":leaf.id})
	# Mobile has no desktop page limit.
	check(ui.choices.any(func(choice):return choice.caption == "Sun specialist") and ui.choices.any(func(choice):return choice.caption == "Shade specialist (active)" and choice.disabled),"Both light adaptations stay visible with the active choice marked")
	check(not game.world.edit("mutate",{"id":leaf.id,"gene":"pulse_vesicle"}),"Photosynthesis availability never authorizes a mismatched mutation")
	game._toggle_build()
	game.manual_zoom = 2; game.camera_locked = false; game.free_camera = cell.position
	game._update_world(1)
	var at: Vector2 = game.views[family.id].get_global_transform_with_canvas().origin
	var clock: float = game.world.time
	var random: int = game.world.rng.state
	game.touch_zoom._tap(at)
	check(game.world.player == cell,"A single tap does not transfer control")
	game.touch_zoom._tap(at)
	check(game.world.player == family and game.camera_locked,"Double tap adopts the existing living family member and follows it")
	check(game.world.time == clock and game.world.rng.state == random and game.world.cells.size() == 3,"Family switching advances no world time and creates no cell")
	check(not game._switch_family(foreign.id),"Family gestures cannot select another player's or uncontrolled lineage")
	family.dead = true
	game.world.player = cell
	check(not game._switch_family(family.id),"A dead family member cannot be adopted")
	game.queue_free(); await process_frame
	print("ANATOMY ACCESS: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
