extends SceneTree
## Same-seed ablation; records CPU ticks, not rendered FPS. JSONL for comparison.
const Sim = preload("res://scripts/simulation.gd")
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var modes := option("--cases","reference,native,fluid,spatial,schedule,all").split(",")
	var gpu = null
	if "gpu" in modes:
		gpu = load("res://scripts/gpu_transport.gd").new()
		if not gpu.initialize():
			push_error("GPU benchmark requires a working RenderingDevice renderer and display")
			quit(1)
			return
	for zoom_string in option("--zooms","1,0.5,0.25,0.15").split(","):
		for mode in modes:
			var sim = Sim.new()
			sim.background_biology = option("--biology","coarse") != "off"
			sim.evolution.enabled = option("--economy","on") == "on"
			sim.habitat_geometry.enabled = option("--plants","on") == "on"
			if mode in ["native","fluid","all","gpu"] and sim.kernels == null:
				push_error("Native benchmark requested without compiled extension")
				quit(1)
				return
			sim.native_particles = mode in ["native","all","gpu"]
			sim.native_exclusion = mode in ["native","all","gpu"]
			sim.grid.native_enabled = mode in ["native","all","gpu"]
			sim.reaction_grid.native_enabled = mode in ["native","all","gpu"]
			sim.native_fluid = mode in ["fluid","all","gpu"]
			sim.fluid.local_suction = mode in ["fluid","all","gpu"]
			sim.spatial_queries = mode in ["spatial","all","gpu"]
			sim.gpu_transport = gpu if mode == "gpu" else null
			for cell in sim.cells:
				cell.sense_clock = (cell.id%9)/60.0 if mode in ["schedule","all","gpu"] else 0.0
				cell.membrane.native_constraints = mode in ["native","all","gpu"]
			var zoom := float(zoom_string)
			var growth := float(option("--growth","1"))
			sim.player.biomass *= growth
			sim.player.update_geometry()
			if growth != 1: sim.player.membrane = Sim.Cell.Membrane.new(sim.player.radius)
			var effective_zoom: float = zoom if option("--camera","diagnostic") == "play" else zoom*minf(1,150.0/sim.player.radius)
			sim.view_half = Sim.VIEW*0.5/effective_zoom
			var scale := int(option("--scale","1"))
			var offspring := option("--offspring","off") == "on"
			if offspring:
				var quote: Dictionary = sim.offspring_quote()
				sim.player.biomass += quote.material
				sim.player.energy = 100
				sim.player.oxygen = 24
				sim.player.reserve(maxf(quote.material,quote.energy),quote.material)
				if not sim.divide_lineage():
					push_error("Offspring benchmark fixture could not divide")
					quit(1)
					return
			var deaths := mini(int(option("--deaths","0")),sim.cells.size()-1)
			var initial: Array = sim.particles.duplicate(true)
			for copy in range(1,scale):
				for p in initial:
					var q: Dictionary = p.duplicate()
					q.p = Sim.Medium.wrap_position(p.p+Vector2(copy*17,copy*31))
					q.previous = q.p
					sim.particles.append(q)
			sim.grid.rebuild(sim.particles)
			var death_emission_us := 0
			var timings: Array[int] = []
			var phases: Dictionary = {}
			var totals := Vector2.ZERO
			var warmup := int(option("--warmup","30"))
			var count := int(option("--ticks","120"))
			for i in warmup+count:
				var begin := Time.get_ticks_usec()
				if i == warmup and deaths > 0:
					for cell in sim.cells.slice(1,1+deaths): sim._die(cell)
					death_emission_us = Time.get_ticks_usec()-begin
				sim.step(1.0/60)
				if sim.player.dead:
					push_error("Benchmark stopped: player died")
					quit(1)
					return
				if i < warmup: continue
				timings.append(Time.get_ticks_usec()-begin)
				totals += Vector2(sim.active_cells,sim.active_particles)
				for phase in sim.profile_usec: phases[phase] = phases.get(phase,0.0)+sim.profile_usec[phase]/float(count)
			timings.sort()
			print("BENCHMARK ",JSON.stringify({"case":mode,"biology":sim.background_biology,"effective_zoom":effective_zoom,"plants":sim.habitat_geometry.enabled,"economy":sim.evolution.enabled,"zoom":zoom,"scale":scale,"growth":growth,"offspring":offspring,"deaths":deaths,"samples":count,"death_emission_ms":death_emission_us/1000.0,"max_ms":timings[-1]/1000.0,"median_ms":timings[count/2]/1000.0,"p95_ms":timings[mini(count-1,int(count*.95))]/1000.0,"p99_ms":timings[mini(count-1,int(count*.99))]/1000.0,"mean_active_cells":totals.x/count,"mean_active_particles":totals.y/count,"phase_mean_us":phases,"cpu":OS.get_processor_name(),"gpu_bridge":gpu.metrics if mode=="gpu" else {}}))
	if gpu != null: gpu.close()
	quit()
