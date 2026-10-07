extends SceneTree
const Fluid = preload("res://scripts/fluid_compare.gd")
const Sim = preload("res://scripts/simulation.gd")
const Validator = preload("res://tests/fluid_compare_gpu.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var sim = Sim.new(25171)
	sim.player.biomass *= 16
	sim.player.update_geometry()
	sim.player.membrane = sim.Cell.Membrane.new(sim.player.radius)
	var results: Array = []
	var all_finite := true
	# Equal-world resolution and geometry; counts are solvent, not chemistry.
	for config in [["grid",40],["pbf",4],["grid",80],["pbf",8],["grid",160],["pbf",16]]:
		var fluid = Fluid.new()
		if not fluid.initialize(config[0],sim.fluid.velocity,sim.cells,sim.habitat_geometry,16,config[1]):
			quit(1)
			return
		fluid.resident_batch(1.0/60,6)
		var samples: Array[float] = []
		for j in 12:
			var result: Dictionary = fluid.resident_batch(1.0/60,4)
			samples.append(result.wall_ms/4)
		var total := 0.0
		for value in samples: total += value
		samples.sort()
		var snapshot: Dictionary = fluid.snapshot()
		all_finite = all_finite and finite(snapshot.state)
		results.append({"model":config[0],"iterations":config[1],"grid_nodes":fluid.cols*fluid.rows,
			"solvent_particles":fluid.count if fluid.model=="pbf" else 0,
			"mean_ms":total/samples.size(),"median_ms":samples[samples.size()/2],"p95_ms":samples[-1],
			"state_finite":finite(snapshot.state),"quality":Validator.summary(fluid),"note":"Resident solver wall time including command recording/fence, static geometry, no chemical transport/reactions, no rendering/readback in timed region"})
		fluid.close()
	var report := {"results":results,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),
		"engine":Engine.get_version_info().string,"large_cell_radius":sim.player.radius,"cells":sim.cells.size(),
		"plant_segments":sim.habitat_geometry.segments.size()}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file := FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE)
			if file == null:
				push_error("Cannot write fluid solver benchmark")
				quit(1)
				return
			file.store_string(JSON.stringify(report))
	print("FLUID_RESIDENT ",JSON.stringify(report))
	if not all_finite: push_error("Non-finite state in resident benchmark")
	quit(0 if all_finite else 1)
func finite(values: PackedFloat32Array) -> bool:
	for value in values:
		if not is_finite(value): return false
	return true
