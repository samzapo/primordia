extends SceneTree
## CPU simulation throughput only; use F3 in the game for actual frame rate.
const Simulation = preload("res://scripts/simulation.gd")
func _initialize() -> void:
	var sim = Simulation.new()
	var ticks: Array[int] = []
	var phases: Dictionary = {}
	for i in 1320:
		var started := Time.get_ticks_usec()
		sim.step(1.0/60.0)
		if i < 120: continue
		ticks.append(Time.get_ticks_usec()-started)
		for phase in sim.profile_usec: phases[phase] = phases.get(phase,0.0)+sim.profile_usec[phase]/1200.0
	ticks.sort()
	print(JSON.stringify({"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"ticks":ticks.size(),"tick_p50_ms":ticks[600]/1000.0,"tick_p95_ms":ticks[1140]/1000.0,"phase_mean_us":phases,"active_cells":sim.active_cells,"stored_cells":sim.cells.size(),"active_particles":sim.active_particles,"stored_particles":sim.particles.size()},"  "))
	quit()
