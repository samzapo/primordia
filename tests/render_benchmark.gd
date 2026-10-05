extends SceneTree
var scene
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for text in option("--zooms","0.5,0.25,0.15").split(","):
		var zoom := float(text)
		scene = load("res://scenes/pond.tscn").instantiate()
		root.add_child(scene)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		scene.preferences.persist = false
		scene.manual_zoom = zoom
		for i in 60: await process_frame
		var timings: Array[int] = []
		var prior := Time.get_ticks_usec()
		for i in 180:
			await process_frame
			var now := Time.get_ticks_usec()
			timings.append(now-prior)
			prior = now
		timings.sort()
		print("RENDER_BENCHMARK ",JSON.stringify({"zoom":zoom,"frames":timings.size(),"median_ms":timings[90]/1000.0,"p95_ms":timings[171]/1000.0,"p99_ms":timings[178]/1000.0,"prepare_ema_ms":scene.render_ms,"simulation_ema_ms":scene.simulation_ms,"active_cells":scene.world.active_cells,"active_particles":scene.world.active_particles,"renderer":RenderingServer.get_video_adapter_name(),"vsync_mode":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"backend":"native" if scene.world.kernels!=null else "script","bloom":scene.preferences.bloom,"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}))
		# Drawing-only ablation on the exact same frozen state, with/without LOD.
		scene.set_physics_process(false)
		for cell in scene.world.cells:
			cell.previous_position = cell.position
			cell.previous_angle = cell.angle
		for particle in scene.world.particles:
			particle.previous = particle.p
			particle.previous_angle = particle.angle
		if zoom == 0.15:
			for native in [false,true,false,true]:
				scene.world.native_render = native
				var prepare: Array[int] = []
				for i in 100:
					var begin := Time.get_ticks_usec()
					scene._sync_particles(1.0)
					if i>=20: prepare.append(Time.get_ticks_usec()-begin)
				prepare.sort()
				print("PREPARE_BENCHMARK ",JSON.stringify({"native":native,"zoom":zoom,"median_ms":prepare[40]/1000.0,"p95_ms":prepare[76]/1000.0,"note":"Frozen particle-buffer preparation, including render interpolation exclusion and buffer submission"}))
			scene.world.native_render = true
			for lod in [false,true,false,true]:
				for view in scene.views.values(): view.detail_lod=lod
				timings.clear()
				for i in 100:
					scene.world.revision += 1
					for cell in scene.world.cells: cell.render_revision+=1
					var begin := Time.get_ticks_usec()
					await process_frame
					if i>=20: timings.append(Time.get_ticks_usec()-begin)
				timings.sort()
				print("LOD_BENCHMARK ",JSON.stringify({"enabled":lod,"zoom":zoom,"median_ms":timings[40]/1000.0,"p95_ms":timings[76]/1000.0}))
		scene.queue_free()
		await process_frame
	quit()
