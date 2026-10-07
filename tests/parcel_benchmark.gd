extends SceneTree
## Coarse transport kernel only; this is not rendered FPS or full ecology.
const Sim = preload("res://scripts/simulation.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var rows: Array = []
	for count in [5000,20000,50000]:
		for flow_kind in ["constant","eddies"]:
			for enabled in [false,true,true,false]:
				var sim = Sim.new(831)
				if sim.kernels == null: push_error("Parcel benchmark requires native pool"); quit(1); return
				sim.particles.clear(); sim.pheromones.clear(); sim.grid.rebuild(sim.particles)
				if flow_kind=="constant": sim.fluid.velocity.fill(Vector2(24,-9))
				var ids: Array[int] = []
				for i in count:
					sim.spawn_particle(Sim.WASTE,Vector2(fposmod(i*53.7,4096),fposmod(i*73.9,2560)),Vector2(3,1),0.3,7)
					ids.append(i)
				sim.enable_particle_pool()
				sim.kernels.parcel_configure(enabled)
				sim.kernels.parcel_protect(PackedVector2Array(),PackedFloat32Array())
				sim.kernels.packet_begin([])
				var samples: Array[float] = []
				for tick in 15:
					var mark := Time.get_ticks_usec()
					sim.kernels.transport([],ids,sim.fluid.velocity,Vector2.ZERO,Vector2.ZERO,0.5,tick+1,sim.background_rng,(tick+1)*0.5,true)
					if tick>=3: samples.append((Time.get_ticks_usec()-mark)/1000.0)
				var total := 0.0
				for sample in samples: total+=sample
				samples.sort()
				rows.append({"particles":count,"flow":flow_kind,"parcels":enabled,"mean_ms":total/samples.size(),"p95_ms":samples[-1],"metrics":sim.kernels.parcel_metrics(),"material":sim.kernels.pool_material(),"rng":str(sim.background_rng.state)})
	var output := "/tmp/primordia-parcel-benchmark.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: push_error("Cannot write parcel benchmark"); quit(1); return
	file.store_string(JSON.stringify({"note":"Coarse native transport only, half-second steps, no biology/draw/contact cost, equal finite material","rows":rows},"\t"))
	file.close()
	print("PARCEL_BENCHMARK ",output)
	quit()
