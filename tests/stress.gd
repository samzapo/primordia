extends SceneTree
## Long, fully active habitat: detects numerical failures short benchmarks miss.
const Sim = preload("res://scripts/simulation.gd")
func _initialize() -> void:
	var sim = Sim.new()
	sim.view_half = Sim.VIEW*0.5/0.15
	for tick in 3600:
		sim.step(1.0/60)
		if sim.player.dead:
			push_error("Stress fixture stopped early because the player died")
			quit(1)
			return
		for cell in sim.cells:
			if not cell.position.is_finite() or not cell.velocity.is_finite() or not is_finite(cell.angular_velocity):
				push_error("Non-finite cell at tick %d" % tick)
				quit(1)
				return
		for velocity in sim.fluid.velocity:
			if not velocity.is_finite():
				push_error("Non-finite fluid at tick %d" % tick)
				quit(1)
				return
		for particle in sim.particles:
			if not particle.p.is_finite() or not particle.v.is_finite() or not is_finite(particle.angle):
				push_error("Non-finite particle at tick %d" % tick)
				quit(1)
				return
	print("STRESS: 3600 ticks, whole habitat, all motion finite")
	quit()
