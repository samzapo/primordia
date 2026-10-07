extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Compare = preload("res://tests/packed_particles.gd")
const Pool = preload("res://tests/particle_pool.gd")

static func run(check: Callable) -> void:
	var probe = Sim.new(32)
	if probe.kernels == null: return
	# Reuse versus reconstruction, in pool and scoped dictionary handoffs. Camera
	# jumps exercise fine/coarse transport, scratch shrink/growth and slot reuse.
	for pooled in [false,true]:
		for seed_value in [3201,3271]:
			var fast = Sim.new(seed_value)
			var reference = Sim.new(seed_value)
			fast.kernels.hotloop_configure(true)
			reference.kernels.hotloop_configure(false)
			for sim in [fast,reference]:
				sim.view_half = Sim.VIEW/0.8/2
				if pooled: sim.enable_particle_pool()
			for tick in 160:
				if tick in [30,60,90,120]:
					for sim in [fast,reference]:
						sim.camera_follows_player = false
						sim.camera_position = Vector2(4080 if tick==60 else 400,1280)
						sim.view_half = Vector2(40,40) if tick==90 else Sim.VIEW/0.8/2
				fast.step(1.0/60)
				reference.step(1.0/60)
				if tick%20!=0 and tick!=159: continue
				check.call(Compare.same_packets(fast.particle_snapshots(),reference.particle_snapshots()),"Hot-loop ablations preserve all packet fields through changing activity and compaction")
				check.call(Pool.same_cells(fast,reference) and fast.acidity.values==reference.acidity.values and fast.respiration_loss==reference.respiration_loss and fast.recycled==reference.recycled,"Hot-loop ablations preserve physiology, acid and finite material accounting")
				check.call([fast.rng.state,fast.background_rng.state,fast.ecology_rng.state,fast.chemistry_events]==[reference.rng.state,reference.background_rng.state,reference.ecology_rng.state,reference.chemistry_events],"Hot-loop ablations preserve chemistry events and every random stream")
