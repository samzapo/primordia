extends SceneTree
const Fixture = preload("res://tests/fluid_fixture.gd")
func _initialize() -> void: run.call_deferred()
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func run() -> void:
	var fluid_name := option("--fluid","current")
	var packet_text := option("--chemicals","0")
	var distribution := option("--distribution","uniform")
	var frame_step := option("--frame-step","live")
	var feedback := option("--fluid-feedback","on")
	var dx_text := option("--fluid-dx","16")
	var iterations_text := option("--fluid-iterations","0")
	if fluid_name not in ["current","grid","pbf"] or not packet_text.is_valid_int() or int(packet_text) < 0 or int(packet_text) > 100000 or distribution not in ["uniform","clustered"] or frame_step not in ["live","fixed"]:
		push_error("Invalid fluid/chemical comparison parameters")
		quit(1)
		return
	if feedback not in ["on","off"] or not dx_text.is_valid_float() or float(dx_text) not in [16.0,32.0] or not iterations_text.is_valid_int() or (int(iterations_text) != 0 and not preload("res://scripts/fluid_compare.gd").valid_options("grid",float(dx_text),int(iterations_text))):
		push_error("Invalid fluid resolution, iteration count or feedback diagnostic")
		quit(1)
		return
	var locomotion := option("--locomotion","none")
	if locomotion not in ["none","flagellum","cilia","mixed"]:
		push_error("Unknown locomotion fixture")
		quit(1)
		return
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
	var initial_player_biomass: float = sim.player.biomass
	# Exercise real paid opening anatomy, not a free propulsion endowment.
	for kind in (["propulsion","cilia"] if locomotion == "mixed" else ["propulsion"] if locomotion == "flagellum" else ["cilia"] if locomotion == "cilia" else []):
		if not sim.install(kind,PI if kind == "propulsion" else PI/2):
			push_error("Profile locomotion purchase failed")
			finish_scene(scene,1)
			return
	var switches := option("--hotpaths","all").split(",")
	if "legacy" in switches or "packets" in switches: sim.native_particle_pipeline = false
	if "legacy" in switches or "render_cache" in switches: sim.native_particle_render_cache = false
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
		sim.player.biomass = initial_player_biomass*256
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
	if int(packet_text)>0:
		var material_before := Fixture.packet_material(sim)
		if not Fixture.seed_packets(sim,int(packet_text),distribution):
			push_error("Chemical count must cover the initial inventory")
			finish_scene(scene,1)
			return
		if absf(Fixture.packet_material(sim)-material_before)>0.00001:
			push_error("Chemical fixture duplicated material")
			finish_scene(scene,1)
			return
	if fluid_name != "current":
		var backend = preload("res://scripts/fluid_compare.gd").new()
		if not backend.initialize(fluid_name,sim.fluid.velocity,sim.cells,sim.habitat_geometry,float(dx_text),int(iterations_text)):
			finish_scene(scene,1)
			return
		backend.body_feedback_enabled = feedback == "on"
		sim.experimental_fluid = backend
	# Ordinary profiles retain their old warmup. Chemical comparison measures
	# initial finite clouds immediately after presentation/audio warmup.
	if int(packet_text)==0:
		for i in 60: sim.step(1.0/60)
	var sim_started: float = sim.time
	# Frozen biology keeps identical initial conditions while bank generation
	# completes. Startup work must not seed the measured catch-up spiral.
	if scene.music.enabled:
		var bank_deadline := Time.get_ticks_usec()+10000000
		while not scene.music.ready_bank and Time.get_ticks_usec() < bank_deadline:
			await process_frame
		if not scene.music.ready_bank:
			push_error("Music bank was not ready before profiling")
			finish_scene(scene,1)
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
		var tick_result := {"mode":"ticks","fluid":fluid_name,"locomotion":locomotion,"fixture":option("--fixture","dense"),"hotpaths":option("--hotpaths","all"),
			"ticks":tick_rows.size(),"mean_ms":total/tick_rows.size(),"p95_ms":tick_rows[mini(tick_rows.size()-1,int(tick_rows.size()*0.95))],
			"phases_ms":phases,"particles":sim.particles.size(),"simulation_seconds":sim.time-sim_started,
			"rng":str(sim.rng.state),"background_rng":str(sim.background_rng.state),"ecology_rng":str(sim.ecology_rng.state)}
		if not save_result(tick_result,option("--output","")):
			finish_scene(scene,1)
			return
		finish_scene(scene)
		return
	scene.begin_frame_trace()
	scene.set_physics_process(option("--mode","live") != "frozen" and frame_step == "live")
	var seconds := float(option("--seconds","0"))
	var deadline := Time.get_ticks_usec()+int(seconds*1000000)
	for i in 5900 if seconds > 0 else int(option("--frames","120")):
		if frame_step == "fixed" and option("--mode","live") != "frozen": scene._physics_process(1.0/60)
		await RenderingServer.frame_post_draw
		if seconds > 0 and Time.get_ticks_usec() >= deadline: break
	var rows: Array = scene.end_frame_trace()
	var output := option("--output","")
	var result := {"rows":rows,"fluid":fluid_name,"fluid_settings":sim.experimental_fluid.metrics if sim.experimental_fluid != null else {},
		"fluid_feedback":feedback,
		"fluid_quality":preload("res://tests/fluid_compare_gpu.gd").summary(sim.experimental_fluid) if sim.experimental_fluid != null else {},
		"requested_chemicals":int(packet_text),"distribution":distribution,"frame_step":frame_step,
		"chemistry_events":sim.chemistry_events.duplicate(),"material_remaining":Fixture.packet_material(sim),
		"packed_particles":sim.native_particle_pipeline,"particle_render_cache":sim.native_particle_render_cache,
		"simulation_seconds":sim.time-sim_started,"rng":str(sim.rng.state),"background_rng":str(sim.background_rng.state),"ecology_rng":str(sim.ecology_rng.state),
		"locomotion":locomotion,"player_radius":sim.player.radius,"player_biomass":sim.player.biomass,"seconds":seconds,"hotpaths":option("--hotpaths","all"),"mode":option("--mode","live"),"fixture":option("--fixture","dense"),"music":scene.music.enabled,
		"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),
		"display":DisplayServer.get_name(),"viewport":str(root.size),"zoom":scene.manual_zoom,"max_steps":Engine.max_physics_steps_per_frame,
		"sparks":scene.show_reaction_sparks,"bloom":scene.preferences.bloom,"music_volume":scene.preferences.music_volume,"tick_rate":Engine.physics_ticks_per_second}
	if not save_result(result,output):
		finish_scene(scene,1)
		return
	print("FRAME_PROFILE rows=",rows.size()," output=",output)
	# Use the same immediate shutdown as the game's Quit action. Waiting for
	# another compositor frame after capture can stall a headless display.
	finish_scene(scene)

func finish_scene(scene, code: int = 0) -> void:
	if scene.world.experimental_fluid != null: scene.world.experimental_fluid.close()
	scene.music.enabled = false
	scene.music.player.stop()
	scene.queue_free()
	quit(code)

func save_result(result: Dictionary, output: String) -> bool:
	if output == "": return true
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		push_error("Could not write frame profile to "+output)
		return false
	file.store_string(JSON.stringify(result))
	return true
