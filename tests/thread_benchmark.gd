extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Fixture = preload("res://tests/fluid_fixture.gd")
const Compare = preload("res://tests/packed_particles.gd")
const Pool = preload("res://tests/particle_pool.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var rows: Array = []
	var ticks := 120
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="): ticks=clampi(int(arg.trim_prefix("--ticks=")),8,120)
	for fixture in ["uniform","clustered","growth","small"]:
		var configs: Array = [[1,true,true,true],[8,true,true,true]]
		if fixture=="uniform": configs=[[1,true,true,true],[2,true,true,true],[4,true,true,true],[8,true,true,true],[8,true,true,false],[8,true,false,true],[8,false,true,true]]
		var sims: Array = []
		var samples: Array = []
		for config in configs:
			var sim = Sim.new(3307)
			if sim.kernels==null: push_error("Native benchmark required"); quit(1); return
			sim.view_half=Sim.VIEW/0.8/2
			if fixture=="growth":
				sim.player.biomass*=256
				sim.player.update_geometry()
				sim.player.membrane=sim.Cell.Membrane.new(sim.player.radius)
			Fixture.seed_packets(sim,5000 if fixture=="small" else 20000 if fixture=="growth" else 50000,"clustered" if fixture=="clustered" else "uniform","mixed" if fixture=="growth" else "equal")
			sim.enable_particle_pool()
			sim.kernels.thread_configure(config[0],config[1],config[2],config[3])
			sims.append(sim);samples.append([])
		for tick in ticks:
			# Rotate which backend runs first each tick to reduce load/order bias.
			for offset in sims.size():
				var index: int = (tick+offset)%sims.size()
				var mark := Time.get_ticks_usec()
				sims[index].step(1.0/60)
				samples[index].append((Time.get_ticks_usec()-mark)/1000.0)
		var reference: Array = sims[0].particle_snapshots()
		for i in sims.size():
			var sim = sims[i]
			if not Compare.same_packets(reference,sim.particle_snapshots()) or not Pool.same_cells(sims[0],sim) or [sim.rng.state,sim.background_rng.state,sim.ecology_rng.state,sim.chemistry_events,sim.acidity.values]!=[sims[0].rng.state,sims[0].background_rng.state,sims[0].ecology_rng.state,sims[0].chemistry_events,sims[0].acidity.values]:
				push_error("Thread benchmark outcomes diverged");quit(1);return
			var total := 0.0
			for value in samples[i]: total+=value
			samples[i].sort()
			rows.append({"fixture":fixture,"config":configs[i],"mean_ms":total/samples[i].size(),"p95_ms":samples[i][int(ticks*0.95)],"metrics":sim.kernels.thread_metrics(),"exact_outcomes":true})
	var output := "/tmp/primordia-thread-benchmark.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: push_error("Cannot write benchmark");quit(1);return
	file.store_string(JSON.stringify({"note":"CPU simulation ticks only, equal ticks per backend, rotating execution order, finite fixture inventory; not rendered FPS","ticks":ticks,"rows":rows},"\t"))
	file.close()
	print("THREAD_BENCHMARK ",output)
	quit()
