extends SceneTree
## Transport-only ablation at the widest playable footprint, not whole-game FPS.
const Sim = preload("res://scripts/simulation.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for count in [4096,16384]:
		for mode in ["frozen","coarse","fine"]:
			var world = Sim.new(682)
			world.camera_follows_player = false
			world.camera_position = world.player.position
			world.view_half = Sim.VIEW*0.5/0.8
			world.particles.clear()
			world.pheromones.clear()
			world.grid.rebuild(world.particles)
			# Uniform test workload isolates transport cost from evolving ecology.
			for i in count:
				world.spawn_particle(Sim.WASTE,Vector2(fposmod(i*53.7,4096),fposmod(i*73.9,2560)),Vector2(3,1),0.3)
			world.background_transport = mode != "frozen"
			world.background_period = 1.0/60 if mode == "fine" else 0.5
			world.fluid.set_camera(world.camera_position,world.view_half)
			var samples: Array[int] = []
			var moved := 0
			for frame in 240:
				world.revision += 1
				var start := Time.get_ticks_usec()
				world._move_particles(1.0/60)
				world._step_background_fluid(1.0/60)
				if frame >= 60:
					samples.append(Time.get_ticks_usec()-start)
					moved += world.background_particles
			samples.sort()
			var total := 0
			for value in samples: total += value
			print("TRANSPORT_BENCHMARK ",JSON.stringify({"mode":mode,"backend":"native" if world.native_particles else "script","particles":count,"median_ms":samples[90]/1000.0,"p95_ms":samples[171]/1000.0,"mean_ms":total/180000.0,"background_updates_per_tick":moved/180.0,"note":"Transport, grid rebuild and distant stems/field only; 80% view; fine = 60 Hz background"}))
	quit()
