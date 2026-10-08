extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1;push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene = load("res://scenes/pond.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.set_process(false)
	await process_frame
	scene.music.enabled = true
	scene.preferences.music_volume = 0.65
	scene._toggle_build()
	scene.set_physics_process(false)
	scene.world.player.add_organ("propulsion",PI,"graze",false)
	scene.world.player.substrate = 12
	scene.world.evolution.points = 7
	scene._update_world(1)
	var world_clock: float = scene.world.time
	var energy: float = scene.world.player.energy
	var mass: float = scene.world.player.organic_mass()
	var notes := {}
	var waves_seen := 0
	var parcel_start: Array = scene.cell_ui.interior.ecology.parcels.map(func(p):return p.p)
	var first_image: Image
	for i in 180:
		scene._process(1.0/60)
		scene._physics_process(1.0/60)
		await process_frame
		if i == 35: first_image = root.get_texture().get_image()
		for wave in scene.music.waves:
			notes[wave.kind] = true
			waves_seen += 1
			check(wave.at <= scene.music.audible_frame,"No wave precedes its buffered audio onset")
		await create_timer(1.0/60).timeout
	check(scene.world.time == world_clock and scene.world.player.energy == energy and scene.world.player.organic_mass() == mass,"Build mode freezes external physiology and conserves resources")
	check(scene.cell_ui.interior.ecology.parcels.map(func(p):return p.p) != parcel_start,"Inside parcels still move during the outside pause")
	check(scene.cell_ui.interior.ecology.amount("ap") == 7,"Seven AP render as seven internal gold vacuoles")
	check(notes.has("nucleus") and notes.has("propulsion") and notes.has("feeding") and waves_seen > 0,"Real generator playback produces nucleus, flagellar and digestive sound waves")
	check(scene.music.visual_notes.size() <= 128 and scene.music.waves.size() <= 64,"Audio visualization stays bounded")
	check(first_image != null and not first_image.is_empty() and root.get_texture().get_image().get_data() != first_image.get_data(),"The rendered interior changes while the external clock stays frozen")
	scene.cell_ui.open_context({"kind":"assembly"})
	check(scene.cell_ui.choices.size() <= 5 and scene.cell_ui.choices.all(func(c):return c.kind != "feeding"),"Factory is compact and offers no membrane pore purchase")
	scene.cell_ui._tooltip("Factory\nLong explanation",Vector2(400,300))
	check(scene.cell_ui.tip.text == "Factory","Ordinary tooltip hides the explanation")
	var old_sac: float = scene.cell_ui.interior.atp_size
	scene.world.player.gain_energy(600)
	scene.cell_ui.interior.sync()
	check(scene.cell_ui.interior.atp_size > old_sac,"More ATP enlarges the whole sac beyond its former capacity")
	scene.preferences.music_volume = 0
	scene._process(1.0/60)
	check(scene.music.waves.is_empty() and scene.music.visual_notes.is_empty(),"Mute clears sound-wave cues")
	scene.settings_panel.show()
	var interior_clock: float = scene.cell_ui.interior.ecology.clock
	scene._process(1.0/60)
	check(scene.cell_ui.interior.ecology.clock == interior_clock,"Settings pauses intracellular animation")
	scene.queue_free()
	await process_frame
	# Allow the audio thread to retire its stopped playback before process exit.
	await create_timer(0.15).timeout
	print("ANATOMY_UI: ",assertions," assertions, ",failures," failures")
	quit.call_deferred(1 if failures else 0)
