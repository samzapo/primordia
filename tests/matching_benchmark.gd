extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Fixture=preload("res://tests/fluid_fixture.gd")
const Compare=preload("res://tests/packed_particles.gd")
const Pool=preload("res://tests/particle_pool.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var rows: Array=[]
	for fixture in ["uniform","clustered","growth","small"]:
		var sims: Array=[]
		var timings: Array=[[],[],[]]
		for mode in 3:
			var sim=Sim.new(3307)
			sim.view_half=Sim.VIEW/0.8/2
			if fixture=="growth":
				sim.player.biomass*=256;sim.player.update_geometry()
				sim.player.membrane=sim.Cell.Membrane.new(sim.player.radius)
			Fixture.seed_packets(sim,5000 if fixture=="small" else 20000 if fixture=="growth" else 50000,"clustered" if fixture=="clustered" else "uniform","mixed" if fixture=="growth" else "equal")
			sim.enable_particle_pool()
			sim.kernels.thread_configure(1 if mode==1 else 8,true,true,false)
			sim.kernels.pair_matching_configure(mode>0)
			sims.append(sim)
		for tick in 60:
			for offset in 3:
				var i: int=(tick+offset)%3
				var start:=Time.get_ticks_usec()
				sims[i].step(1.0/60)
				timings[i].append((Time.get_ticks_usec()-start)/1000.0)
		if not Compare.same_packets(sims[1].particle_snapshots(),sims[2].particle_snapshots()) or not Pool.same_cells(sims[1],sims[2]) or sims[1].acidity.values!=sims[2].acidity.values or sims[1].chemistry_events!=sims[2].chemistry_events:
			push_error("Matching lane outcomes diverged");quit(1);return
		for i in 3:
			var sim=sims[i]
			var total:=0.0
			for t in timings[i]: total+=t
			timings[i].sort()
			var mass:=0.0
			for p in sim.particle_snapshots():
				if p.alive and p.kind not in [1,3]: mass+=p.amount
			rows.append({"fixture":fixture,"mode":["ordered8","matching1","matching8"][i],"mean_ms":total/60,"p95_ms":timings[i][57],"count":sim.particle_count(),"material":mass,"biomass":sim.player.biomass,"events":sim.chemistry_events})
			print("MATCHING_CPU ",JSON.stringify(rows[-1]))
	var file:=FileAccess.open(OS.get_cmdline_user_args()[-1],FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"));file.close()
	quit()
