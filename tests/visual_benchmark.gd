extends SceneTree
## Same seeded scenes for each art pass; frozen isolates presentation, live includes physics.
func _initialize() -> void: run.call_deferred()
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var output := option("--output","")
	var mode := option("--mode","frozen")
	var stage := option("--stage","current")
	var count := int(option("--frames","36"))
	var camera := option("--camera","diagnostic")
	var zooms := option("--zooms","0.8" if camera == "play" else "0.5,0.25,0.15").split(",")
	for fixture in option("--fixtures","normal,dense,growth").split(","):
		for value in zooms:
			var zoom := float(value)
			if not value.is_valid_float() or not is_finite(zoom) or zoom <= 0:
				push_error("Benchmark zoom must be a finite positive number")
				quit(1)
				return
			for bloom in [false,true]:
				var scene = load("res://scenes/pond.tscn").instantiate()
				root.add_child(scene)
				scene.preferences.persist = false
				scene.music.enabled = option("--music","off") == "on"
				scene.set_physics_process(false)
				scene.diagnostic_zoom = camera != "play" # Historical stress views explicitly bypass play limits.
				scene.manual_zoom = zoom
				scene.preferences.bloom = bloom
				scene.microscope_layer.material.set_shader_parameter("bloom_enabled",bloom)
				var sim = scene.world
				sim.background_biology = option("--biology","coarse") != "off"
				sim.background_transport = option("--background","coarse") != "off"
				if fixture == "dense":
					var initial: Array = sim.particles.duplicate(true)
					for copy in range(1,4):
						for packet in initial:
							var item: Dictionary = packet.duplicate(true)
							item.p = sim.Medium.wrap_position(item.p+Vector2(copy*17,copy*31))
							item.previous = item.p
							sim.particles.append(item)
					sim.grid.rebuild(sim.particles)
				elif fixture == "family":
					# Explicit fixture endowments; each real birth still pays normal costs.
					for i in 3:
						var quote: Dictionary = sim.offspring_quote()
						sim.player.biomass += quote.material
						sim.player.energy = 100
						sim.player.reserve(maxf(60,quote.material),quote.material)
						if not sim.divide_lineage(false,false):
							push_error("Family benchmark could not place its paid successor")
							quit(1)
							return
				elif fixture == "growth":
					sim.player.biomass *= 256
					sim.player.update_geometry()
					sim.player.membrane = sim.Cell.Membrane.new(sim.player.radius)
				for i in 60: sim.step(1.0/60)
				scene._update_world(1.0)
				scene.ui.hide()
				scene.set_physics_process(mode == "live")
				for i in 12: await process_frame
				var elapsed: Array[int] = []
				var prior := Time.get_ticks_usec()
				for i in count:
					await process_frame
					var now := Time.get_ticks_usec()
					elapsed.append(now-prior)
					prior = now
				elapsed.sort()
				print("VISUAL_BENCHMARK ",JSON.stringify({"stage":stage,"mode":mode,"fixture":fixture,"zoom":zoom,"camera":camera,"effective_zoom":scene.zoom/minf(scene.get_viewport_rect().size.x/sim.VIEW.x,scene.get_viewport_rect().size.y/sim.VIEW.y),"bloom":bloom,"frames":count,"median_ms":elapsed[count/2]/1000.0,"p95_ms":elapsed[mini(count-1,int(count*0.95))]/1000.0,"prepare_ms":scene.render_ms,"tick_ms":scene.simulation_ms,"cells":sim.active_cells,"particles":sim.active_particles,"biology":sim.background_biology,"biology_us":sim.profile_usec.get("offscreen_biology",0),"background":sim.background_transport,"background_particles":sim.background_particles,"renderer":RenderingServer.get_video_adapter_name(),"music":scene.music.enabled,"music_ms":scene.music.render_usec/1000.0,"music_peak_ms":scene.music.peak_render_usec/1000.0,"audio_skips":scene.music.skips,"music_ready":scene.music.ready_bank}))
				if output != "" and fixture == "normal" and mode == "frozen":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output+"/"+stage+"-"+str(int(zoom*100))+"-"+("bloom" if bloom else "flat")+".png")
				scene.queue_free()
				await process_frame
	# Allow the audio mixer to release its last stopped playback before shutdown.
	await create_timer(0.15).timeout
	quit()
