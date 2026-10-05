extends SceneTree
## Frozen identical scene: cached plants + fractal water off/on. Frame times are not CPU tick times.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var scene = load("res://scenes/pond.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.preferences.persist = false
	scene.notice_timer = 0
	for zoom in [0.5,0.25,0.15]:
		scene.diagnostic_zoom = true # Preserve the original wider stress workload.
		scene.manual_zoom = zoom
		for enabled in [false,true,false,true]:
			scene.habitat_view.visible = enabled
			scene.light_layer.material.set_shader_parameter("fractal_color",enabled)
			var elapsed: Array[int] = []
			for i in 80:
				var begin := Time.get_ticks_usec()
				await process_frame
				if i >= 20: elapsed.append(Time.get_ticks_usec()-begin)
			elapsed.sort()
			print("HABITAT_RENDER ",JSON.stringify({"zoom":zoom,"plants_and_fractal_color":enabled,"median_ms":elapsed[30]/1000.0,"p95_ms":elapsed[57]/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"prepare_ms":scene.render_ms,"plants":scene.world.habitat_geometry.plants.size(),"textures":scene.habitat_view.textures.size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"renderer":RenderingServer.get_video_adapter_name()}))
			if enabled and zoom == 0.5:
				for arg in OS.get_cmdline_user_args():
					if arg.begins_with("--picture="):
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(arg.trim_prefix("--picture="))
	scene.queue_free()
	await process_frame
	quit()
