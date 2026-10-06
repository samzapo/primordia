extends SceneTree
func _initialize() -> void: run.call_deferred()
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func run() -> void:
	var frames_text := option("--frames","120")
	var ticks_text := option("--ticks","480")
	var steps_text := option("--max-steps","8")
	var seconds_text := option("--seconds","0")
	if not frames_text.is_valid_int() or int(frames_text) < 2 or int(frames_text) > 5900 or not ticks_text.is_valid_int() or int(ticks_text) < 1 or int(ticks_text) > 6000 or not steps_text.is_valid_int() or int(steps_text) < 1 or int(steps_text) > 8 or not seconds_text.is_valid_float() or not is_finite(float(seconds_text)) or float(seconds_text) < 0 or float(seconds_text) > 120:
		push_error("Profile requires 2..5900 frames, 1..6000 ticks, 1..8 catch-up steps and 0..120 seconds")
		quit(1)
		return
	if option("--fixture","dense") not in ["normal","dense","growth","encounters"] or option("--mode","live") not in ["live","frozen","ticks"]:
		push_error("Unknown profile fixture or mode")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_physics_steps_per_frame = int(option("--max-steps","8"))
	var scene = load("res://scenes/pond.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.music.enabled = option("--music","on") == "on"
	scene.manual_zoom = 0.8
	scene.show_reaction_sparks = option("--sparks","on") == "on"
	var sim = scene.world
	var switches := option("--hotpaths","all").split(",")
	if "legacy" in switches or "geometry" in switches: scene.native_geometry = false
	if "legacy" in switches or "compact" in switches: sim.native_particle_compaction = false
	if "legacy" in switches or "bookkeeping" in switches: sim.native_transport_bookkeeping = false
	if "legacy" in switches or "writes" in switches: sim.native_chemistry_writes = false
	if "legacy" in switches or "grid" in switches: sim.grid.incremental = false
	if "legacy" in switches or "kinds" in switches: sim.grid.kind_queries = false
	if "legacy" in switches or "chemistry" in switches:
		sim.native_background_chemistry = false
		sim.native_chemical_timestamps = false
	if "legacy" in switches or "obstacles" in switches: sim.habitat_geometry.native_bounds = false
	if "legacy" in switches or "feeding" in switches: sim.native_feeding = false
	if "legacy" in switches or "contacts" in switches: sim.native_contacts = false
	for cell in sim.cells:
		if "legacy" in switches or "surface" in switches: cell.fast_support = false
		if "legacy" in switches or "dents" in switches: cell.membrane.native_compression = false
	if option("--fixture","dense") in ["dense","encounters"]:
		var initial: Array = sim.particles.duplicate(true)
		for copy in range(1,4):
			for packet in initial:
				var item: Dictionary = packet.duplicate(true)
				item.p = sim.Medium.wrap_position(item.p+Vector2(copy*17,copy*31))
				item.previous = item.p
				sim.particles.append(item)
		sim.grid.rebuild(sim.particles)
	elif option("--fixture","dense") == "growth":
		sim.player.biomass *= 256
		sim.player.update_geometry()
		sim.player.membrane = sim.Cell.Membrane.new(sim.player.radius)
	if option("--fixture","dense") == "encounters":
		for i in 3:
			var hunter = sim._make_cell(sim.player.position+Vector2(95+i*92,30-i*25),"hunter")
			hunter.previous_position = hunter.position
			hunter.fast_support = not ("legacy" in switches or "surface" in switches)
			hunter.membrane.native_compression = not ("legacy" in switches or "dents" in switches)
		sim.cells[1].position = sim.player.position+Vector2(45,0)
		sim.cells[1].previous_position = sim.cells[1].position
	scene._update_world(1)
	for i in 60: sim.step(1.0/60)
	# Frozen biology keeps identical initial conditions while bank generation
	# completes. Startup work must not seed the measured catch-up spiral.
	if scene.music.enabled:
		var bank_deadline := Time.get_ticks_usec()+10000000
		while not scene.music.ready_bank and Time.get_ticks_usec() < bank_deadline:
			await process_frame
		if not scene.music.ready_bank:
			push_error("Music bank was not ready before profiling")
			scene.queue_free()
			quit(1)
			return
	for i in 30: await process_frame
	if option("--mode","live") == "ticks":
		var tick_rows: Array[float] = []
		var phases := {}
		sim.profiling = true
		for i in int(option("--ticks","480")):
			var started := Time.get_ticks_usec()
			sim.step(1.0/60)
			tick_rows.append((Time.get_ticks_usec()-started)/1000.0)
			for key in sim.profile_usec: phases[key] = phases.get(key,0)+sim.profile_usec[key]/1000.0
		var total := 0.0
		for value in tick_rows: total += value
		for key in phases: phases[key] /= tick_rows.size()
		tick_rows.sort()
		var tick_result := {"mode":"ticks","fixture":option("--fixture","dense"),"hotpaths":option("--hotpaths","all"),
			"ticks":tick_rows.size(),"mean_ms":total/tick_rows.size(),"p95_ms":tick_rows[mini(tick_rows.size()-1,int(tick_rows.size()*0.95))],
			"phases_ms":phases,"particles":sim.particles.size(),"simulation_seconds":sim.time-1.0,
			"rng":str(sim.rng.state),"background_rng":str(sim.background_rng.state),"ecology_rng":str(sim.ecology_rng.state)}
		if not save_result(tick_result,option("--output","")):
			scene.queue_free()
			quit(1)
			return
		scene.queue_free()
		quit()
		return
	scene.begin_frame_trace()
	scene.set_physics_process(option("--mode","live") != "frozen")
	var seconds := float(option("--seconds","0"))
	var deadline := Time.get_ticks_usec()+int(seconds*1000000)
	for i in 5900 if seconds > 0 else int(option("--frames","120")):
		await RenderingServer.frame_post_draw
		if seconds > 0 and Time.get_ticks_usec() >= deadline: break
	var rows: Array = scene.end_frame_trace()
	var output := option("--output","")
	var result := {"rows":rows,"seconds":seconds,"hotpaths":option("--hotpaths","all"),"mode":option("--mode","live"),"fixture":option("--fixture","dense"),"music":scene.music.enabled,
		"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),
		"display":DisplayServer.get_name(),"viewport":str(root.size),"zoom":scene.manual_zoom,"max_steps":Engine.max_physics_steps_per_frame,
		"sparks":scene.show_reaction_sparks,"bloom":scene.preferences.bloom,"music_volume":scene.preferences.music_volume,"tick_rate":Engine.physics_ticks_per_second}
	if not save_result(result,output):
		scene.queue_free()
		quit(1)
		return
	print("FRAME_PROFILE rows=",rows.size()," output=",output)
	# Use the same immediate shutdown as the game's Quit action. Waiting for
	# another compositor frame after capture can stall a headless display.
	scene.music.enabled = false
	scene.music.player.stop()
	scene.queue_free()
	quit()

func save_result(result: Dictionary, output: String) -> bool:
	if output == "": return true
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		push_error("Could not write frame profile to "+output)
		return false
	file.store_string(JSON.stringify(result))
	return true
