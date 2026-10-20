extends SceneTree
## Live wide-view fixtures. Added tissue/particles are benchmark inputs, not playthroughs.
func _initialize() -> void: run.call_deferred()
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for fixture in option("--fixtures","normal,dense,deaths,growth,offspring").split(","):
		for zoom in [0.5,0.25,0.15]:
			var scene = load("res://scenes/pond.tscn").instantiate()
			root.add_child(scene)
			scene.preferences.persist = false
			scene.diagnostic_zoom = true # Preserve the original wider stress workload.
			scene.manual_zoom = zoom
			var sim = scene.world
			if fixture == "dense":
				var initial: Array = sim.particles.duplicate(true)
				for copy in range(1,4):
					for packet in initial:
						var item: Dictionary = packet.duplicate(true)
						item.p = sim.Medium.wrap_position(item.p+Vector2(copy*17,copy*31))
						item.previous = item.p
						sim.particles.append(item)
				sim.grid.rebuild(sim.particles)
			elif fixture == "growth":
				sim.player.biomass *= 256
				sim.player.update_geometry()
				sim.player.membrane = sim.Cell.Membrane.new(sim.player.radius)
			elif fixture == "offspring":
				var quote: Dictionary = sim.offspring_quote()
				sim.player.biomass += quote.material
				sim.player.energy = 100
				sim.player.oxygen = 24
				sim.player.biomass=200;sim.player.energy=100;sim.player.reproduction_retry_at=0
				if not sim.divide_lineage():
					push_error("Offspring render fixture could not divide")
					quit(1)
					return
			for i in 20: await process_frame
			var elapsed: Array[int] = []
			var prior := Time.get_ticks_usec()
			var death_emission_us := 0
			if fixture == "deaths":
				for cell in sim.cells.slice(1,4): sim._die(cell)
				death_emission_us = Time.get_ticks_usec()-prior
			for i in 60:
				await process_frame
				var now := Time.get_ticks_usec()
				elapsed.append(now-prior)
				prior = now
			elapsed.sort()
			print("ECONOMY_RENDER ",JSON.stringify({"fixture":fixture,"zoom":zoom,"frames":60,"death_emission_ms":death_emission_us/1000.0,"max_ms":elapsed[-1]/1000.0,"median_ms":elapsed[30]/1000.0,"p95_ms":elapsed[57]/1000.0,"simulation_ms":scene.simulation_ms,"prepare_ms":scene.render_ms,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"active_cells":sim.active_cells,"particles":sim.active_particles,"renderer":RenderingServer.get_video_adapter_name(),"simulated_seconds":sim.time}))
			scene.queue_free()
			await process_frame
	quit()
