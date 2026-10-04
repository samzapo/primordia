extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Membrane = preload("res://scripts/membrane.gd")
var failures := 0
var assertions := 0
const DT := 1.0 / 60.0

func expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_metabolism()
	_test_organs()
	_test_particles()
	_test_defense()
	_test_membrane()
	_test_replay()
	_test_ecosystem()
	_test_survival_strategy()
	await _test_interface()
	print("RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _test_metabolism() -> void:
	var sim := Sim.new()
	sim.substrate = 1.0
	sim.oxygen = 0.25
	sim.energy = 10
	var mass := sim.biomass
	sim._metabolize(1.0)
	expect(is_equal_approx(sim.substrate, 0.75), "Reaction is limited by available oxygen")
	expect(is_zero_approx(sim.oxygen), "Reaction consumes oxygen without going negative")
	expect(is_equal_approx(sim.energy, 10.55), "ATP output minus maintenance is accounted for")
	expect(is_equal_approx(sim.biomass - mass, 0.2), "Biomass output follows reaction amount")
	sim._metabolize(1.0)
	expect(is_equal_approx(sim.substrate, 0.75), "No oxygen means no further reaction")

func _test_organs() -> void:
	var sim := Sim.new()
	var mass := sim.biomass
	expect(sim.install("protection", 3), "Can attach affordable organelle")
	expect(is_equal_approx(sim.biomass, mass - 10), "Installing spends biomass")
	expect(not sim.install("sensing", 3), "Cannot overwrite occupied socket")
	expect(not sim.install("offensive", 5), "Cannot overspend biomass")
	expect(not sim.install("unknown", 5), "Reject unknown organelle")
	expect(not sim.install("sensing", -1), "Reject invalid socket")
	expect(sim.remove(3) and is_equal_approx(sim.biomass, mass - 5), "Recycling refunds half")
	sim.organs.fill("")
	var origin := sim.position
	for i in 120: sim._move(DT)
	expect(sim.position.distance_to(origin) < 0.01, "No propulsion means no active thrust")
	sim.organs[4] = "propulsion"
	sim.target_vector = Vector2.from_angle(sim.angle)
	for i in 120: sim._move(DT)
	expect(sim.position.distance_to(origin) > 40, "Flagellum produces movement")

func _test_particles() -> void:
	var sim := Sim.new()
	sim.particles.clear()
	sim.spawn_particle(Sim.NUTRIENT, sim.slot_position(0))
	sim.grid.rebuild(sim.particles)
	sim.organs[0] = ""
	sim._feed()
	expect(sim.eaten == 0, "Contact alone cannot feed without a feeding pore")
	sim.organs[0] = "feeding"
	sim.substrate = 23.5
	sim._feed()
	expect(sim.eaten == 0, "A full nutrient packet cannot overfill substrate storage")
	sim.substrate = 4.0
	sim._feed()
	expect(sim.eaten == 1 and not sim.particles[0].alive, "Mouth contact consumes a nutrient")
	sim._feed()
	expect(sim.eaten == 1, "Particle cannot be consumed twice")
	sim.particles.clear()
	sim.spawn_particle(Sim.NUTRIENT, sim.position + Vector2(80, 0))
	sim.grid.rebuild(sim.particles)
	sim._sense()
	expect(sim.sensor_active and sim.target_vector.x > 0, "Receptor detects nearby food particles")
	sim.organs[2] = ""
	sim._sense()
	expect(not sim.sensor_active, "Removing receptor removes food detection")
	sim.organs[2] = "sensing"
	sim.spawn_particle(Sim.DANGER, sim.position + Vector2(90, 0))
	sim.grid.rebuild(sim.particles)
	sim._sense()
	expect(sim.threat_detected and sim.target_vector.x < 0, "Predator trace reverses sensor preference")

func _test_defense() -> void:
	var bare := Sim.new()
	bare.predator = bare.position + Vector2(75, 0)
	bare._predate(DT)
	var armored := Sim.new()
	armored.organs[3] = "protection"
	armored.predator = armored.position + Vector2(75, 0)
	armored._predate(DT)
	expect(armored.health > bare.health and armored.health < 100, "Cortex reduces rather than eliminates bite damage")
	armored.organs[5] = "regenerative"
	var energy := armored.energy
	armored.substrate = 0
	armored._metabolize(1.0)
	expect(armored.health > 91 and armored.energy < energy, "Repair consumes energy to restore health")
	var armed := Sim.new()
	armed.particles.clear()
	armed.spawn_particle(Sim.TOXIN, armed.predator)
	armed._defend(DT)
	expect(armed.predator_health == 88 and armed.predator_stun > 0, "Toxin contact damages and repels predator")
	var depleted := Sim.new()
	depleted.organs.fill("offensive")
	depleted.energy = 5.0
	depleted.threat_detected = true
	depleted.threat_direction = Vector2.RIGHT
	depleted._defend(DT)
	expect(depleted.energy >= 0, "Multiple toxin vesicles cannot overspend ATP")
	armed.health = 0
	var old_time := armed.time
	armed.step(DT)
	expect(armed.time == old_time, "Dead world no longer advances")

func _test_membrane() -> void:
	var membrane := Membrane.new(47)
	membrane.points[0] *= 0.5
	for i in 360: membrane.step(DT, 55, Vector2(50, 0), i * DT)
	var area := 0.0
	for i in membrane.COUNT:
		expect(membrane.points[i].is_finite(), "Membrane position remains finite")
		area += membrane.points[i].cross(membrane.points[(i + 1) % membrane.COUNT]) * 0.5
	var target := membrane.COUNT * 55.0 * 55.0 * sin(TAU / membrane.COUNT) * 0.5
	expect(absf(area - target) / target < 0.02, "XPBD recovers target area after deformation and growth")

func _test_replay() -> void:
	var a := Sim.new(41)
	var b := Sim.new(41)
	for i in 120:
		a.step(DT)
		b.step(DT)
	expect(a.position == b.position and a.energy == b.energy, "Same seed and steps reproduce organism state")
	expect(a.particles == b.particles, "Same seed and steps reproduce particle state")

func _test_ecosystem() -> void:
	var sim := Sim.new()
	var started := Time.get_ticks_usec()
	for i in 5400:
		sim.step(DT)
		if not sim.position.is_finite():
			expect(false, "Ecosystem position remains finite")
			break
	var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
	print("ECOSYSTEM: time=%.1f eaten=%d processed=%.1f health=%.1f energy=%.1f particles=%d wall=%.2fs" % [sim.time, sim.eaten, sim.processed, sim.health, sim.energy, sim.particles.size(), elapsed])
	expect(sim.eaten >= 5, "Default anatomy autonomously finds and consumes food")
	expect(sim.processed >= 5, "Autonomous feeding drives metabolism and growth")
	expect(sim.time >= 30, "Default anatomy gives the player time to adapt")
	expect(sim.particles.size() <= 900, "Particle population stays within renderer capacity")
	expect(sim.energy >= 0 and sim.health >= 0 and sim.oxygen >= 0 and sim.substrate >= 0, "Resources remain nonnegative")

func _test_survival_strategy() -> void:
	var sim := Sim.new()
	expect(sim.install("offensive", 7), "Starting biomass supports an offensive adaptation")
	for i in 7200:
		sim.step(DT)
		if sim.biomass >= 10 and sim.organs[3] == "": sim.install("regenerative", 3)
		if sim.biomass >= 10 and sim.organs[5] == "": sim.install("protection", 5)
	print("ADAPTED: time=%.1f eaten=%d health=%.1f processed=%.1f" % [sim.time, sim.eaten, sim.health, sim.processed])
	expect(sim.time >= 90, "A viable organelle strategy survives the adaptation milestone")
	expect(sim.won, "A viable organelle strategy completes both milestone conditions")

func _test_interface() -> void:
	var scene = load("res://scenes/pond.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	expect(scene.batches.size() == 5, "Renderer builds all five particle species")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_2
	scene._unhandled_input(key)
	expect(scene.selected == 1, "Keyboard selects protective organelle")
	var old_time: float = scene.world.time
	scene._physics_process(DT)
	expect(scene.world.time == old_time, "Assembly pauses simulation for socket placement")
	key.keycode = KEY_ESCAPE
	scene._unhandled_input(key)
	expect(scene.selected == -1, "Escape cancels assembly")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = scene._card(1).get_center()
	scene._unhandled_input(click)
	expect(scene.selected == 1, "Clicking organelle card enters assembly")
	click.position = scene.ORIGIN + scene.world.slot_position(3)
	var old_biomass: float = scene.world.biomass
	scene._unhandled_input(click)
	expect(scene.world.organs[3] == "protection" and scene.selected == -1, "Clicking empty socket attaches selected organelle and resumes")
	expect(is_equal_approx(scene.world.biomass, old_biomass - 10), "Interface installation spends biomass once")
	click.button_index = MOUSE_BUTTON_RIGHT
	scene._unhandled_input(click)
	expect(scene.world.organs[3] == "", "Right-clicking socket recycles its organelle")
	key.keycode = KEY_SPACE
	scene._unhandled_input(key)
	expect(scene.paused, "Space toggles observation pause")
	scene.world.health = 0
	key.keycode = KEY_R
	scene._unhandled_input(key)
	expect(scene.world.health == 100 and not scene.paused, "Restart resets death and pause state")
	scene.queue_free()
	await process_frame
