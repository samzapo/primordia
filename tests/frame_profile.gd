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
	var sizes := option("--particle-sizes","equal")
	var collisions := option("--particle-collisions","on")
	if collisions not in ["on","off"]:
		push_error("Particle collisions must be on or off")
		quit(1)
		return
	var frame_step := option("--frame-step","live")
	var feedback := option("--fluid-feedback","on")
	var dx_text := option("--fluid-dx","16")
	var iterations_text := option("--fluid-iterations","0")
	if fluid_name not in ["current","grid","pbf"] or not packet_text.is_valid_int() or int(packet_text) < 0 or int(packet_text) > 100000 or distribution not in ["uniform","clustered","habitat"] or sizes not in ["equal","mixed"] or frame_step not in ["live","fixed"]:
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
	var steps_text := option("--max-steps","auto")
	var seconds_text := option("--seconds","0")
	if not frames_text.is_valid_int() or int(frames_text) < 2 or int(frames_text) > 5900 or not ticks_text.is_valid_int() or int(ticks_text) < 1 or int(ticks_text) > 6000 or (steps_text!="auto" and (not steps_text.is_valid_int() or int(steps_text) < 1 or int(steps_text) > 8)) or not seconds_text.is_valid_float() or not is_finite(float(seconds_text)) or float(seconds_text) < 0 or float(seconds_text) > 120:
		push_error("Profile requires 2..5900 frames, 1..6000 ticks, auto or 1..8 catch-up steps and 0..120 seconds")
		quit(1)
		return
	if option("--fixture","dense") not in ["normal","dense","growth","encounters"] or option("--mode","live") not in ["live","frozen","ticks"]:
		push_error("Unknown profile fixture or mode")
		quit(1)
		return
	var delay_text := option("--tick-delay-ms","0")
	var sync_mode := option("--vsync","off")
	var tick_audio := option("--tick-audio","on")
	if not delay_text.is_valid_float() or not is_finite(float(delay_text)) or float(delay_text)<0 or float(delay_text)>100 or sync_mode not in ["on","off"] or tick_audio not in ["on","off"]:
		push_error("Invalid diagnostic tick delay, VSync or audio-service mode");quit(1);return
	Engine.max_fps=int(option("--fps-limit","0"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if sync_mode=="on" else DisplayServer.VSYNC_DISABLED)
	Engine.max_physics_steps_per_frame = 2 if steps_text=="auto" else int(steps_text)
	var scene = load("res://scenes/pond.tscn").instantiate()
	scene.manage_catchup = steps_text=="auto"
	scene.diagnostic_tick_cost_ms = float(delay_text)
	scene.use_particle_pool = false # Import after fixture setup and ablation switches.
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.music.enabled = option("--music","on") == "on"
	scene.music.refill_between_ticks = tick_audio == "on"
	scene.manual_zoom = 0.8
	scene.show_reaction_sparks = option("--sparks","on") == "on"
	scene.set_particle_collisions(collisions == "on")
	var sim = scene.world
	var neighbors := option("--neighbors","legacy")
	var cache := option("--neighbor-cache","off")
	var metrics := option("--neighbor-metrics","on")
	if neighbors not in ["legacy","packed","bvh","quadtree"] or cache not in ["on","off"] or metrics not in ["on","off"]:
		push_error("Neighbor comparison requires legacy/packed/bvh/quadtree and on/off cache/metrics")
		finish_scene(scene,1)
		return
	if sim.kernels != null:
		sim.kernels.neighbor_configure(neighbors,cache == "on",metrics == "on")
	elif neighbors != "legacy" or cache == "on":
		push_error("Packed/BVH/quadtree/cache comparison requires native kernels")
		finish_scene(scene,1)
		return
	var matching := option("--pair-matching","off")
	if matching not in ["on","off"] or (matching=="on" and (sim.kernels==null or neighbors!="legacy" or cache!="off")):
		push_error("Pair matching requires native legacy-grid ownership and on/off");finish_scene(scene,1);return
	var thread_text := option("--threads","8")
	if not thread_text.is_valid_int() or int(thread_text)<1 or int(thread_text)>8:
		push_error("Simulation threads must be 1 through 8")
		finish_scene(scene,1)
		return
	if sim.kernels != null:
		sim.kernels.pair_matching_configure(matching=="on")
		sim.kernels.thread_configure(int(thread_text),option("--parallel-transport","on")=="on",option("--parallel-contacts","on")=="on",option("--compact-geometry","off")=="on")
	var initial_player_biomass: float = sim.player.biomass
	# Exercise real paid opening anatomy, not a free propulsion endowment.
	for kind in (["propulsion","cilia"] if locomotion == "mixed" else ["propulsion"] if locomotion == "flagellum" else ["cilia"] if locomotion == "cilia" else []):
		if not sim.install(kind,PI if kind == "propulsion" else PI/2):
			push_error("Profile locomotion purchase failed")
			finish_scene(scene,1)
			return
	var switches := option("--hotpaths","all").split(",")
	if sim.kernels != null:
		sim.kernels.hotloop_configure("scratch_reuse" not in switches)
	if "reaction_bounds" in switches: sim.native_chemistry_bounds = false
	if "reaction_acid" in switches: sim.native_chemistry_lazy_acid = false
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
	if "field_views" in switches: sim.fluid.native_views=false
	if "suction" in switches: sim.fluid.native_suction=false
	if "traction" in switches: sim.native_traction = false
	for cell in sim.cells:
		if "outline" in switches: cell.membrane.native_outline = false
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
		if not Fixture.seed_packets(sim,int(packet_text),distribution,sizes):
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
	var engine := option("--particle-engine","current")
	var radius_text := option("--physical-radius","4")
	var particle_iterations := option("--particle-iterations","1")
	if engine not in ["current","uniform","liquidfun"] or not radius_text.is_valid_float() or not particle_iterations.is_valid_int() or float(radius_text)<1 or float(radius_text)>8 or int(particle_iterations)<1 or int(particle_iterations)>4:
		push_error("Unknown particle engine or invalid radius/iterations")
		finish_scene(scene,1)
		return
	if engine != "current":
		if fluid_name != "current" or collisions != "on" or not sim.configure_particle_engine(engine,float(radius_text),int(particle_iterations)):
			push_error("Uniform/LiquidFun comparison requires current medium, collisions and supported native pool")
			finish_scene(scene,1)
			return
	elif "pool" not in switches and "legacy" not in switches: sim.enable_particle_pool()
	if matching=="on" and (not sim.particle_pool or engine=="liquidfun"):
		push_error("Matching comparison needs the native pool without LiquidFun");finish_scene(scene,1);return
	var parcel_option := option("--parcels","off")
	if parcel_option not in ["on","off"] or (parcel_option == "on" and not sim.configure_parcels(true)):
		push_error("Parcel transport requires supported native ownership")
		finish_scene(scene,1)
		return
	if option("--particle-backend","cpu")=="resident":
		var stream_option:=option("--resident-streaming","on")
		if stream_option not in ["on","off"]: push_error("Resident streaming must be on/off");finish_scene(scene,1);return
		scene.resident_streaming=stream_option=="on"
		scene._start_resident()
		while scene.resident_starting: await process_frame
		if sim.resident==null: push_error("Resident gameplay initialization failed");finish_scene(scene,1);return
	if option("--full-habitat","off")=="on":
		if sim.resident!=null: sim.resident.full_detail=true
		else: sim.integration_half=sim.WORLD*.5
	# Ordinary profiles retain their old warmup. Chemical comparison measures
	# initial finite clouds immediately after presentation/audio warmup.
	if int(packet_text)==0:
		for i in 60: sim.step(1.0/60)
	if option("--perception","exteroception")=="interoception":scene._toggle_perception()
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
		if sim.kernels != null: sim.kernels.neighbor_reset_metrics(); sim.kernels.particle_engine_reset_metrics()
		var tick_rows: Array[float] = []
		var phases := {}
		sim.profiling = true
		for i in int(option("--ticks","480")):
			var started := Time.get_ticks_usec()
			sim.step(1.0/60)
			tick_rows.append((Time.get_ticks_usec()-started)/1000.0)
			for key in sim.profile_usec: phases[key] = phases.get(key,0)+sim.profile_usec[key]/1000.0
		if option("--particle-backend","cpu")=="resident" and sim.resident==null:
			push_error("Resident tick benchmark fell back to CPU");finish_scene(scene,1);return
		var total := 0.0
		for value in tick_rows: total += value
		for key in phases: phases[key] /= tick_rows.size()
		tick_rows.sort()
		var tick_result := {"mode":"ticks","fluid":fluid_name,"locomotion":locomotion,"fixture":option("--fixture","dense"),"hotpaths":option("--hotpaths","all"),
			"pair_matching":matching,"threading":sim.kernels.thread_metrics() if sim.kernels != null else {}, "particle_engine":sim.kernels.particle_engine_metrics() if sim.kernels != null else {}, "parcels":sim.kernels.parcel_metrics() if sim.kernels != null else {}, "neighbors":neighbor_summary(sim),"particle_collisions":sim.particle_collisions,"ticks":tick_rows.size(),"mean_ms":total/tick_rows.size(),"p95_ms":tick_rows[mini(tick_rows.size()-1,int(tick_rows.size()*0.95))],
			"phases_ms":phases,"particles":sim.particle_count(),"simulation_seconds":sim.time-sim_started,
			"rng":str(sim.rng.state),"background_rng":str(sim.background_rng.state),"ecology_rng":str(sim.ecology_rng.state)}
		if not save_result(tick_result,option("--output","")):
			finish_scene(scene,1)
			return
		finish_scene(scene)
		return
	if sim.kernels != null: sim.kernels.neighbor_reset_metrics(); sim.kernels.particle_engine_reset_metrics()
	scene.begin_frame_trace()
	if float(delay_text)>0:
		physics_frame.connect(func():
			if not is_instance_valid(scene) or not scene.is_physics_processing(): return
			var begin := Time.get_ticks_usec()
			OS.delay_usec(int(float(delay_text)*1000))
			if scene.frame_trace != null: scene.frame_trace.work("injected_delay",Time.get_ticks_usec()-begin))
	scene.set_physics_process(option("--mode","live") != "frozen" and frame_step == "live")
	var seconds := float(option("--seconds","0"))
	var deadline := Time.get_ticks_usec()+int(seconds*1000000)
	for i in 5900 if seconds > 0 else int(option("--frames","120")):
		if frame_step == "fixed" and option("--mode","live") != "frozen": scene._physics_process(1.0/60)
		await RenderingServer.frame_post_draw
		if seconds > 0 and Time.get_ticks_usec() >= deadline: break
	var rows: Array = scene.end_frame_trace()
	if option("--particle-backend","cpu")=="resident" and sim.resident==null:
		push_error("Resident benchmark fell back to CPU; no GPU performance claim");finish_scene(scene,1);return
	var output := option("--output","")
	var result := {"rows":rows,"injected_tick_delay_ms":float(delay_text),"tick_audio":tick_audio,"vsync":sync_mode,"fluid":fluid_name,"fluid_settings":sim.experimental_fluid.metrics if sim.experimental_fluid != null else {},
		"fluid_feedback":feedback,
		"fluid_quality":preload("res://tests/fluid_compare_gpu.gd").summary(sim.experimental_fluid) if sim.experimental_fluid != null else {},
		"backend":option("--particle-backend","cpu"),"resident_streaming":option("--resident-streaming","on"),"cold_packets":sim.resident.stored_count() if sim.resident!=null else 0,"transfer_bytes":sim.resident.gpu.transfer_readback_bytes if sim.resident!=null else 0,"full_habitat":option("--full-habitat","off"),"resident_readbacks":sim.resident.gpu.readbacks if sim.resident!=null else 0,"requested_chemicals":int(packet_text),"distribution":distribution,"particle_sizes":sizes,"frame_step":frame_step,"particle_collisions":sim.particle_collisions,
		"pair_matching":matching,"threading":sim.kernels.thread_metrics() if sim.kernels != null else {}, "particle_engine":sim.kernels.particle_engine_metrics() if sim.kernels != null else {}, "parcels":sim.kernels.parcel_metrics() if sim.kernels != null else {}, "neighbors":neighbor_summary(sim),"chemistry_events":sim.chemistry_events.duplicate(),"material_remaining":Fixture.packet_material(sim),
		"packed_particles":sim.native_particle_pipeline,"particle_pool":sim.particle_pool,"pool_metrics":sim.kernels.pool_metrics() if sim.kernels != null else {},"particle_render_cache":sim.native_particle_render_cache,
		"simulation_seconds":sim.time-sim_started,"rng":str(sim.rng.state),"background_rng":str(sim.background_rng.state),"ecology_rng":str(sim.ecology_rng.state),
		"locomotion":locomotion,"player_radius":sim.player.radius,"player_biomass":sim.player.biomass,"seconds":seconds,"hotpaths":option("--hotpaths","all"),"mode":option("--mode","live"),"fixture":option("--fixture","dense"),"music":scene.music.enabled,
		"source_commit":OS.get_environment("PRIMORDIA_PROFILE_COMMIT"),"native_cells":sim.kernels != null,"native_suction":sim.fluid.native_suction,"native_views":sim.fluid.native_views,"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),
		"display":DisplayServer.get_name(),"viewport":str(root.size),"zoom":scene.manual_zoom,"max_steps":Engine.max_physics_steps_per_frame,"catchup_policy":steps_text,
		"sparks":scene.show_reaction_sparks,"bloom":scene.preferences.bloom,"music_volume":scene.preferences.music_volume,"tick_rate":Engine.physics_ticks_per_second}
	if option("--image-output","")!="": root.get_texture().get_image().save_png(option("--image-output",""))
	if not save_result(result,output):
		finish_scene(scene,1)
		return
	print("FRAME_PROFILE rows=",rows.size()," output=",output)
	# Use the same immediate shutdown as the game's Quit action. Waiting for
	# another compositor frame after capture can stall a headless display.
	finish_scene(scene)

func neighbor_summary(sim) -> Dictionary:
	return sim.kernels.neighbor_metrics() if sim.kernels != null else {"backend":"script","cache":false,"instrumented":false}

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
