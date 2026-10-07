extends SceneTree
const Fluid = preload("res://scripts/fluid_compare.gd")
const Medium = preload("res://scripts/medium.gd")
var failures := 0
var assertions := 0
var results: Array = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)
static func summary(solver) -> Dictionary:
	var snap: Dictionary = solver.snapshot()
	var values: PackedFloat32Array = snap.state
	var walls: PackedFloat32Array = snap.wall
	var momentum := Vector2.ZERO
	var speed := 0.0
	var finite := true
	var divergence := 0.0
	var fluid_nodes := 0
	var density_error := 0.0
	var density_peak := 0.0
	var compression := 0.0
	var penetration := 0.0
	if snap.model == "grid":
		for i in snap.count:
			var v := Vector2(values[i*4],values[i*4+1])
			finite = finite and v.is_finite()
			speed = maxf(speed,v.length())
			if walls[i*4] < 0: continue
			fluid_nodes += 1
			momentum += v*snap.mass_per_sample
			var x: int = i%snap.cols
			var y: int = i/snap.cols
			var l: int = y*snap.cols+posmod(x-1,snap.cols)
			var down: int = posmod(y-1,snap.rows)*snap.cols+x
			var d: float = (v.x-values[l*4]+v.y-values[down*4+1])/snap.dx
			divergence += d*d
	else:
		for i in snap.count:
			var at := Vector2(values[i*4],values[i*4+1])
			var rho: float = snap.constraints[i*4+1]
			var v := Vector2(values[i*4+2],values[i*4+3])
			if not at.is_finite() or not v.is_finite() or not is_finite(rho) or at.x<0 or at.y<0 or at.x>=Medium.WORLD.x or at.y>=Medium.WORLD.y:
				finite = false
				continue
			density_error += pow(rho-1,2)
			compression += pow(maxf(0,rho-1),2)
			density_peak = maxf(density_peak,rho)
			var grid_index: int = int(at.y/snap.dx)*snap.cols+int(at.x/snap.dx)
			penetration = maxf(penetration,-walls[grid_index*4])

			momentum += v*snap.mass_per_sample
			speed = maxf(speed,v.length())
		divergence = -1
	return {"finite":finite,"max_speed":speed,"momentum": [momentum.x,momentum.y],
		"divergence_rms":sqrt(divergence/maxi(1,fluid_nodes)) if divergence>=0 else null,
		"fluid_nodes":fluid_nodes,"solvent_count":snap.count if snap.model=="pbf" else 0,
		"density_error_rms":sqrt(density_error/maxi(1,snap.count)) if snap.model=="pbf" else null,
		"compression_rms":sqrt(compression/maxi(1,snap.count)) if snap.model=="pbf" else null,
		"peak_density_ratio":density_peak if snap.model=="pbf" else null,
		"nearest_node_penetration":penetration if snap.model=="pbf" else null}

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for model in ["grid","pbf"]:
		var uniform := PackedVector2Array()
		uniform.resize(2560)
		uniform.fill(Vector2(180,7))
		var fluid = Fluid.new()
		if not fluid.initialize(model,uniform):
			quit(1)
			return
		fluid.driven = false
		fluid.viscosity = 0
		var before: Dictionary = summary(fluid)
		fluid.resident_batch(1.0/60,12)
		var after: Dictionary = summary(fluid)
		check(after.finite,model+" uniform transport stays finite")
		var prior := Vector2(before.momentum[0],before.momentum[1])
		var next := Vector2(after.momentum[0],after.momentum[1])
		var relative := prior.distance_to(next)/maxf(1,prior.length())
		check(relative < 0.003,model+" periodic translation conserves momentum within float tolerance")
		check(absf(after.max_speed-Vector2(180,7).length()) < 0.3,model+" does not damp uniform translation")
		results.append({"model":model,"fixture":"periodic_uniform","before":before,"after":after,"relative_momentum_drift":relative})
		fluid.close()
		# Long-wave divergence plus solenoidal eddy tests pressure correction.
		var flow := PackedVector2Array()
		for y in 40:
			for x in 64:
				var px := TAU*(x+0.5)/64
				var py := TAU*(y+0.5)/40
				flow.append(Vector2(20*cos(px)*sin(py)+10*sin(px),-12.5*sin(px)*cos(py)))
		fluid = Fluid.new()
		if not fluid.initialize(model,flow):
			quit(1)
			return
		fluid.driven = false
		before = summary(fluid)
		fluid.resident_batch(1.0/60,24)
		after = summary(fluid)
		check(after.finite and after.max_speed < 100,model+" smooth vortex remains stable")
		if model == "grid": check(after.divergence_rms < before.divergence_rms, "Grid pressure reduces divergent flow")
		if model == "pbf": check(after.compression_rms < 0.02,"PBF smooth flow retains near-rest density")
		results.append({"model":model,"fixture":"vortex","before":before,"after":after})
		fluid.close()
	# Same deformed cell and real fractal stem geometry in both solvers.
	var sim = preload("res://scripts/simulation.gd").new(25171)
	sim.player.biomass *= 16
	sim.player.update_geometry()
	sim.player.membrane = sim.Cell.Membrane.new(sim.player.radius)
	for model in ["grid","pbf"]:
		var fluid = Fluid.new()
		if not fluid.initialize(model,sim.fluid.velocity,sim.cells,sim.habitat_geometry):
			quit(1)
			return
		var before: Dictionary = summary(fluid)
		fluid.resident_batch(1.0/60,12)
		var after: Dictionary = summary(fluid)
		check(after.finite and after.max_speed < 500,"Obstructed "+model+" remains bounded")
		if model=="pbf":
			check(after.peak_density_ratio < 1.5,"PBF obstacle compression stays bounded")
			# Grid-node SDF is a conservative, coarse penetration diagnostic.
			check(after.nearest_node_penetration <= fluid.dx,"PBF respects sampled obstacle exclusion")
		results.append({"model":model,"fixture":"deformed_cells_fractal_plants","before":before,"after":after})
		fluid.close()
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var report := {"assertions":assertions,"failures":failures,"results":results,"gpu":RenderingServer.get_video_adapter_name()}
	if output != "":
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file == null:
			push_error("Cannot write fluid validation")
			quit(1)
			return
		file.store_string(JSON.stringify(report))
	print("FLUID_VALIDATION ",JSON.stringify(report))
	quit(0 if failures==0 else 1)
