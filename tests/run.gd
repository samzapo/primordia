extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Cell = preload("res://scripts/cell.gd")
const Fluid = preload("res://scripts/medium.gd")
const Membrane = preload("res://scripts/membrane.gd")
var failures := 0
var assertions := 0
const DT := 1.0/60.0

func expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_metabolism()
	_test_anatomy()
	_test_receptors()
	_test_growth_and_anchors()
	_test_incremental_grid()
	_test_local_feeding()
	_test_preferences()
	_test_damage()
	_test_fluid()
	_test_propulsion_and_toxins()
	_test_membrane()
	_test_wrap_and_dormancy()
	_test_contacts()
	_test_chemistry()
	_test_feeding()
	_test_death()
	_test_closed_budget()
	_test_crowded_ecology()
	_test_autonomous_diets()
	_test_habitat_pressures()
	_test_replay()
	_test_ecosystem()
	await _test_interface()
	print("RESULT: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func isolated():
	var sim = Sim.new(41)
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.food_sources.clear()
	return sim

func organic(sim) -> float:
	var total := 0.0
	for cell in sim.cells:
		if not cell.dead: total += cell.organic_mass()
	for p in sim.particles:
		if p.alive and p.kind in [Sim.NUTRIENT,Sim.WASTE,Sim.TOXIN]: total += p.amount + p.get("product",0.0)
	return total

func _test_metabolism() -> void:
	var sim = isolated()
	var cell = sim.player
	cell.substrate = 1
	cell.oxygen = 0.25
	cell.energy = 10
	var mass: float = cell.organic_mass()
	var biomass: float = cell.biomass
	sim._metabolize(cell,1)
	expect(is_equal_approx(cell.substrate,0.75) and cell.oxygen == 0,"Oxygen limits respiration")
	expect(is_equal_approx(cell.biomass-biomass,0.2),"Food becomes 80 percent biomass")
	expect(is_equal_approx(cell.organic_mass(),mass),"Respiration accounts for biomass and waste")
	sim._metabolize(cell,1)
	expect(is_equal_approx(cell.substrate,0.75),"No oxygen means no respiration")

func _test_anatomy() -> void:
	var cell = Cell.new()
	cell.body = 1500
	cell.biomass = 500
	cell.update_geometry()
	cell.membrane = Membrane.new(cell.radius)
	var before: float = cell.organic_mass()
	for i in 12: expect(cell.add_organ("sensing",TAU*i/12),"Large membrane supports more than eight organs")
	expect(cell.organs.size() == 12,"No fixed socket count")
	expect(is_equal_approx(cell.organic_mass(),before),"Assembly transfers rather than duplicates mass")
	expect(not cell.add_organ("sensing",0),"Surface packing rejects overlap")
	expect(not cell.add_organ("unknown",0.5),"Unknown anatomy rejected")
	expect(not cell.add_organ("feeding",1.0,"unknown"),"Unknown feeding mode rejected")
	var debris: float = cell.recycle(0)
	expect(is_equal_approx(cell.organic_mass()+debris,before),"Recycle returns half and accounts for debris")
	var small = Cell.new()
	small.update_geometry()
	var radius: float = small.radius
	var mass: float = small.mass
	var inertia: float = small.inertia
	small.biomass *= 8
	small.update_geometry()
	expect(small.radius > radius and small.mass > mass and small.inertia > inertia,"Retained biomass increases volume, mass and inertia")
	small.biomass = 0
	small.update_geometry()
	expect(small.radius < radius,"Losing biomass shrinks the cell")
	var starting: float = cell.organs[0].a
	cell.membrane.step(DT,cell.radius,Vector2(20,10),1,cell.aspect)
	expect(cell.organs[0].a == starting,"Organs stay anchored under relative flow")

func _test_damage() -> void:
	var cell = Cell.new()
	cell.add_organ("protection",0,"graze",false)
	var mass: float = cell.organic_mass()
	var lost: float = cell.damage(20,0)
	expect(cell.health == 100 and cell.organs[0].hp == 50,"Local organelle absorbs damage first")
	expect(is_equal_approx(cell.organic_mass()+lost,mass),"Damaged organelle material is accounted for")
	cell.damage(18,PI)
	expect(cell.health == 82 and not cell.holes.is_empty(),"Exposed membrane punctures despite remote armor")
	var reserve: float = cell.biomass
	var leaked := 0.0
	for i in 120: leaked += cell.heal(DT)
	expect(leaked > 0 and cell.biomass < reserve,"Punctures leak biomass and repair consumes reserves")
	expect(cell.holes.is_empty() and cell.health > 95,"Membrane closes quickly")
	expect(cell.organs[0].hp > 50,"Organelles self-repair")
	var a = Cell.new()
	var b = Cell.new()
	b.add_organ("regenerative",1,"graze",false)
	a.damage(30,0)
	b.damage(30,0)
	a.heal(0.5)
	b.heal(0.5)
	expect(b.health > a.health,"Regenerative organelle accelerates healing")
	a.health = 0
	a.heal(1)
	expect(a.health == 0,"Lethal damage cannot heal back to life before death handling")

func _test_fluid() -> void:
	var medium = Fluid.new()
	medium.driven = false
	medium.velocity.fill(Vector2.ZERO)
	medium.activity.fill(1)
	var body = Cell.new(2,Vector2(2048,1280))
	body.update_geometry()
	body.velocity = Vector2(40,10)
	var momentum: Vector2 = body.velocity*body.mass+medium.momentum()
	var initial_energy: float = 0.5*body.mass*body.velocity.length_squared()
	for i in 80: medium.exchange(body,Vector2(25,15),DT)
	var after: Vector2 = body.velocity*body.mass+medium.momentum()
	expect(after.distance_to(momentum) < 0.1,"Two-way drag conserves linear momentum")
	expect(medium.sample(body.position).length() > 1 and body.velocity.x < 40,"Cell accelerates finite-mass fluid and is slowed by it")
	var energy: float = 0.5*body.mass*body.velocity.length_squared()+0.5*body.inertia*body.angular_velocity*body.angular_velocity
	for v in medium.velocity: energy += 0.5*Fluid.NODE_MASS*v.length_squared()
	expect(energy <= initial_energy+0.1,"Drag does not create kinetic energy")
	var before: Vector2 = medium.momentum()
	medium.step(DT)
	expect(medium.momentum().distance_to(before)<0.1,"Undriven viscosity conserves momentum")
	medium.velocity.fill(Vector2(30,0))
	body.velocity = Vector2.ZERO
	body.angular_velocity = 0
	medium.exchange(body,Vector2.ZERO,0.5)
	expect(body.velocity.x > 0,"Fluid currents accelerate passive cells")
	medium.activity.fill(0)
	before = medium.sample(body.position)
	medium.exchange(body,Vector2.ZERO,1)
	medium.step(1)
	expect(medium.sample(body.position) == before,"Dormant fluid neither couples nor advances")

func _test_propulsion_and_toxins() -> void:
	var light = isolated()
	var heavy = isolated()
	for sim in [light,heavy]:
		sim.fluid.velocity.fill(Vector2.ZERO)
		sim.fluid.activity.fill(1)
		sim.player.organs.clear()
		sim.player.add_organ("propulsion",PI,"graze",false)
	heavy.player.biomass += 200
	heavy.player.update_geometry()
	light._motion(DT)
	heavy._motion(DT)
	expect(light.player.velocity.x > heavy.player.velocity.x and heavy.player.velocity.x > 0,"Added biomass reduces acceleration from equal propulsion")
	var sum: Vector2 = light.player.velocity*light.player.mass+light.fluid.momentum()
	expect(sum.length() < 0.1,"Propulsion deposits equal opposite momentum in the liquid")
	var sim = isolated()
	sim.player.add_organ("offensive",2.1,"graze",false)
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(80,0))
	sim.grid.rebuild(sim.particles)
	for i in 45: sim._sense(sim.player,DT)
	sim._emit_and_attack(sim.player,DT)
	var toxins := 0
	for p in sim.particles:
		if p.kind == Sim.TOXIN: toxins += 1
	expect(toxins == 0,"Food sensing alone does not trigger wasteful attacks")
	var threat = sim._make_cell(sim.player.position+Vector2(100,0),"hunter")
	sim.player.organs[1].mode = "flee"
	sim.spawn_particle(Sim.DANGER,threat.position,Vector2.ZERO,1,threat.id,90)
	sim.grid.rebuild(sim.particles)
	for i in 45: sim._sense(sim.player,DT)
	var energy: float = sim.player.energy
	sim.player.attack_clock = 0
	sim._emit_and_attack(sim.player,DT)
	expect(sim.player.energy < energy and sim.particles[-1].kind == Sim.TOXIN,"An arriving threat signal triggers an ATP-funded toxin")
	sim.cells.erase(threat)
	var prey = sim._make_cell(sim.player.position+Vector2(150,0),"hunter")
	prey.organs.clear()
	prey.activity = 1
	sim.particles[-1].p = prey.position
	sim._toxin_contacts()
	expect(prey.health == 82 and not sim.particles[-1].alive,"Toxin contact damages a cell once")
	sim._toxin_contacts()
	expect(prey.health == 82,"Consumed toxin cannot apply damage twice")

func _test_membrane() -> void:
	var membrane = Membrane.new(47)
	membrane.points[0] *= 0.5
	for i in 240: membrane.step(DT,55,Vector2(20,0),i*DT,1.23)
	var area := 0.0
	for i in membrane.COUNT:
		expect(membrane.points[i].is_finite(),"Pressure/tension ring remains finite")
		area += membrane.points[i].cross(membrane.points[(i+1)%membrane.COUNT])*0.5
	var target: float = membrane.COUNT*55.0*55.0*sin(TAU/membrane.COUNT)*0.5
	expect(absf(area-target)/target < 0.03,"Pressure recovers volume under internal tension")
	expect(membrane.points[0].length()>membrane.points[7].length()*1.25,"Tension supports a noncircular cell")
	var cell = Cell.new()
	cell.membrane = membrane
	for a in [0.3,1.1,2.3,4.7]:
		var point: Vector2 = cell.local_point(cell.surface_parameter(a))
		expect(absf(wrapf(point.angle()-a,-PI,PI)) < 0.001,"Contact and placement follow the deformed boundary ray")

func _test_wrap_and_dormancy() -> void:
	expect(Fluid.offset(Vector2(3,500),Vector2(4093,500)) == Vector2(-6,0),"Nearest-image distance crosses seam")
	var sim = isolated()
	sim.player.position = Vector2(4,1200)
	sim.player.organs.clear()
	sim.player.add_organ("feeding",PI,"graze",false)
	var mouth: Vector2 = sim.player.organ_position(sim.player.organs[0])
	sim.spawn_particle(Sim.NUTRIENT,mouth)
	sim.grid.rebuild(sim.particles)
	sim._feed(sim.player)
	expect(sim.player.eaten == 1,"Feeding uses wrapped spatial queries")
	var distant = sim._make_cell(Vector2(1900,1200),"grazer")
	var location: Vector2 = distant.position
	var reserve: float = distant.biomass
	var shape = distant.membrane.points.duplicate()
	sim.spawn_particle(Sim.WASTE,distant.position,Vector2(25,0),2)
	var stored = sim.particles[-1].duplicate(true)
	for i in 30: sim.step(DT)
	expect(distant.position == location and distant.biomass == reserve and distant.age == 0,"Offscreen organisms remain dormant")
	expect(distant.membrane.points == shape,"Offscreen membrane is frozen")
	expect(sim.particles[-1] == stored,"Offscreen resource position, age and chemistry freeze")
	var corner: Vector2 = sim.screen_position(Vector2(4093,1200))
	expect(absf(corner.x-(Sim.VIEW.x*0.5-7))<20,"Camera projects seam neighbors continuously")
	expect(Fluid.visibility(Vector2(0,0),Vector2(0,0)) == 1,"Microscope center is fully active")
	expect(Fluid.visibility(Vector2(470,0),Vector2(0,0)) > 0 and Fluid.visibility(Vector2(470,0),Vector2(0,0)) < 0.3,"Dark fringe slows activity")

func _test_contacts() -> void:
	var sim = isolated()
	var a = sim.player
	a.organs.clear()
	a.velocity = Vector2(1000,0)
	var b = sim._make_cell(a.position+Vector2(150,0),"hunter")
	b.organs.clear()
	b.velocity = Vector2(-1000,0)
	b.activity = 1
	var c = sim._make_cell(a.position+Vector2(-80,0),"grazer")
	c.organs.clear()
	c.activity = 1
	for i in 60:
		sim._motion(DT/3)
		sim._contacts(DT/3)
	expect(Fluid.offset(a.position,b.position).x > 0,"Swept contacts do not teleport through an approaching hunter")
	expect(Fluid.offset(a.position,b.position).length() > (a.radius+b.radius)*0.8,"Compressed cells remain separated")
	expect(a.position.is_finite() and b.position.is_finite(),"Compressed three-body contact stays finite")

func _test_chemistry() -> void:
	var sim = isolated()
	sim.spawn_particle(Sim.WASTE,sim.player.position,Vector2.ZERO,2)
	sim.particles[0].age = 1
	sim.grid.rebuild(sim.particles)
	sim._chemistry(1)
	expect(sim.particles[0].amount == 2,"Waste cannot recycle without local oxygen")
	sim.spawn_particle(Sim.OXYGEN,sim.player.position,Vector2.ZERO,1)
	sim.grid.rebuild(sim.particles)
	var before: float = organic(sim)
	sim._chemistry(1)
	expect(is_equal_approx(sim.recycled,0.6) and is_equal_approx(sim.respiration_loss,0.4),"Decomposition yields food with explicit conversion loss")
	expect(is_equal_approx(organic(sim)+sim.respiration_loss,before),"Recycling cannot create organic material")
	expect(not sim.particles[1].alive,"Decomposition consumes local oxygen")

func _test_feeding() -> void:
	var sim = isolated()
	var eater = sim.player
	eater.organs.clear()
	eater.add_organ("feeding",0,"parasite",false)
	var prey = sim._make_cell(eater.position+Vector2(100,0),"hunter")
	prey.organs.clear()
	prey.activity = 1
	var before: float = organic(sim)
	sim._intercell_feeding(1)
	expect(eater.stolen > 0 and eater.substrate > 4,"Proboscis transfers biomass from a larger living host")
	expect(not prey.dead and prey.health < 100,"Parasitism does not require killing its host")
	expect(is_equal_approx(organic(sim),before),"Parasitism transfers rather than creates resources")
	eater.organs[0].mode = "engulf"
	sim.cells.erase(prey)
	prey = sim._make_cell(eater.position+Vector2(62,0),"grazer")
	prey.body = 8
	prey.biomass = 0
	prey.organs.clear()
	prey.update_geometry()
	prey.membrane = Membrane.new(prey.radius)
	prey.health = 5
	prey.activity = 1
	sim._intercell_feeding(1)
	expect(prey.dead and eater.engulfed == 1,"A sufficiently larger cell engulfs smaller prey")
	expect(eater.substrate <= 24,"Engulfment respects gut capacity")
	# A receptor's chemical particle becomes an internal signaling particle.
	sim = isolated()
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(90,0))
	sim.grid.rebuild(sim.particles)
	sim._sense(sim.player,0.01)
	expect(not sim.player.signals.is_empty(),"Chemical sensing emits internal signal particles")
	for i in 60: sim._sense(sim.player,DT)
	expect(sim.player.target.x > 0,"Arriving internal signals drive innate motion preference")

func _test_death() -> void:
	var sim = isolated()
	var hunter = sim._make_cell(sim.player.position+Vector2(180,0),"hunter")
	var id: int = hunter.id
	var mass: float = hunter.organic_mass()
	sim._die(hunter)
	var released := 0.0
	for p in sim.particles:
		if p.kind == Sim.NUTRIENT: released += p.amount
	expect(hunter.dead and hunter.health == 0 and not sim.cells.has(hunter),"Hunter dies and is removed, never reset")
	expect(is_equal_approx(released,mass),"Dead hunter releases its retained biomass")
	var count: int = sim.particles.size()
	sim._die(hunter)
	expect(sim.particles.size() == count,"Death emits resources exactly once")
	expect(sim.cells[-1].id != id and Fluid.visibility(sim.cells[-1].position,sim.player.position) == 0,"Replacement is a distinct individual beyond view")
	expect(sim.events.size() == 2,"Death and population replacement are explicit triggers")
	sim = isolated()
	sim.view_half = Fluid.WORLD
	hunter = sim._make_cell(sim.player.position+Vector2(180,0),"hunter")
	sim._die(hunter)
	expect(sim.cells.size() == 1 and sim.pending_replacements.size() == 1,"Population replacement waits when zoom exposes the entire world")
	sim.view_half = Sim.VIEW*0.5
	sim._replace_population()
	expect(sim.pending_replacements.is_empty() and sim.activity_at(sim.cells[-1].position) == 0,"Deferred population returns only beyond the current view")

func _test_closed_budget() -> void:
	var sim = isolated()
	var cell = sim.player
	cell.add_organ("regenerative",2.1,"graze",false)
	cell.waste += cell.damage(25,-PI*0.5)
	for i in 20:
		sim.spawn_particle(Sim.OXYGEN,cell.position+Vector2.from_angle(i)*30)
		sim.spawn_particle(Sim.NUTRIENT,cell.position+Vector2.from_angle(i)*70)
	sim.grid.rebuild(sim.particles)
	var before: float = organic(sim)
	for i in 180: sim.step(DT)
	expect(absf(organic(sim)+sim.respiration_loss-before) < 0.01,"Closed ecology accounts for feeding, leakage, repair and recycling")
	# A small nutrient packet just outside the camera cannot be merged into by active leakage.
	sim.particles.clear()
	var at: Vector2 = cell.position+Vector2(510,0)
	sim.spawn_particle(Sim.NUTRIENT,at)
	sim.grid.rebuild(sim.particles)
	sim._emit_material(Sim.NUTRIENT,at-Vector2(10,0),0.2)
	expect(sim.particles[0].amount == 1,"Local emissions do not mutate dormant neighbors")

func _test_crowded_ecology() -> void:
	var sim = isolated()
	for i in 12:
		var location: Vector2 = sim.player.position+Vector2.from_angle(i*TAU/12)*170
		sim._make_cell(location,"grazer")
	var origin: Vector2 = sim.player.position
	var started := Time.get_ticks_usec()
	for i in 360:
		sim.step(DT)
	var elapsed := (Time.get_ticks_usec()-started)/1000.0
	print("CROWDED: 13 initial cells, 360 ticks, mean %.2f ms, active %d" % [elapsed/360,sim.active_cells])
	for cell in sim.cells:
		expect(cell.position.is_finite() and cell.angular_velocity == cell.angular_velocity,"Crowded coupled ecosystem stays finite")
	expect(Fluid.offset(origin,sim.player.position).length() < 250,"Crowding does not eject player across the world")
	# Both living-host and whole-cell food enter the same metabolic victory path.
	for mode in ["parasite","engulf"]:
		var fixture = isolated()
		var eater = fixture.player
		eater.organs.clear()
		eater.add_organ("feeding",0,mode,false)
		var prey = fixture._make_cell(eater.position+Vector2(80,0),"hunter" if mode == "parasite" else "grazer")
		prey.organs.clear()
		prey.activity = 1
		if mode == "engulf":
			prey.body = 8
			prey.biomass = 0
			prey.update_geometry()
			prey.membrane = Membrane.new(prey.radius)
			prey.health = 2
		eater.substrate = 0
		fixture._intercell_feeding(1)
		var acquired: float = eater.substrate
		fixture._metabolize(eater,1)
		expect(acquired > 0 and eater.processed > 0,"Living-host and whole-cell diets both earn the common growth objective: "+mode)

func _test_autonomous_diets() -> void:
	# Controlled habitats with no steering or intervention after initial anatomy.
	# These demonstrate usable diets, not equal balance across every habitat.
	for mode in ["parasite","engulf"]:
		var sim = Sim.new(41,1)
		sim.cells = [sim.player]
		sim.particles.clear()
		sim.player.organs[0].mode = mode
		sim.player.substrate = 0
		sim.player.biomass = 16
		sim.food_sources.clear()
		sim.food_sources.append(sim.player.position+Vector2(160,0))
		if mode == "engulf":
			sim.player.body = 280
			sim.player.update_geometry()
			sim.player.membrane = Membrane.new(sim.player.radius)
		for i in (1 if mode == "parasite" else 6):
			var at: Vector2 = sim.player.position+Vector2.from_angle(i*0.8)*(150+i*30)
			var prey = sim._make_cell(at,"grazer")
			prey.organs = prey.organs.filter(func(o): return o.kind != "propulsion")
			if mode == "parasite":
				prey.body = 500
				prey.biomass = 90
			prey.update_geometry()
			prey.membrane = Membrane.new(prey.radius)
		for i in 1800: sim.step(DT)
		print("DIET %s: processed=%.1f stolen=%.1f engulfed=%d health=%.1f" % [mode,sim.player.processed,sim.player.stolen,sim.player.engulfed,sim.player.health])
		expect(sim.player.processed > 20 and sim.player.health > 0,"Autonomous "+mode+" feeding sustains metabolism for 30 seconds")
		expect(sim.player.stolen > 0 if mode == "parasite" else sim.player.engulfed >= 1,"Autonomous diet uses its specialized interaction: "+mode)

func _test_habitat_pressures() -> void:
	var lean = Sim.new(4,1)
	var rich = Sim.new(4,2)
	for sim in [lean,rich]:
		sim.particles.clear()
		sim.food_sources.clear()
		sim.food_sources.append(sim.player.position)
		for i in 8:
			sim.time = (i+1)*0.5
			sim.grid.rebuild(sim.particles)
			sim._replenish()
	var lean_food := 0
	var rich_food := 0
	for p in lean.particles:
		if p.kind == Sim.NUTRIENT: lean_food += 1
	for p in rich.particles:
		if p.kind == Sim.NUTRIENT: rich_food += 1
	expect(lean_food == 1 and rich_food == 8,"Lean habitat renews food eight times less often")
	for cell in rich.cells:
		if cell.role == "hunter":
			expect(cell.count("protection") >= 4 and cell.count("regenerative") == 1,"Rich-habitat hunters fit both substantial local armor and a repair organ")

func _test_replay() -> void:
	var a = Sim.new(12)
	var b = Sim.new(12)
	for i in 90:
		a.step(DT)
		b.step(DT)
	expect(a.player.position == b.player.position and a.particles == b.particles,"Same-seed replay matches on the same engine/platform")

func _test_ecosystem() -> void:
	var sim = Sim.new()
	var started := Time.get_ticks_usec()
	var max_tick := 0
	for i in 5400:
		var tick := Time.get_ticks_usec()
		sim.step(DT)
		max_tick = maxi(max_tick,Time.get_ticks_usec()-tick)
		if not sim.player.position.is_finite():
			expect(false,"Ecosystem position remains finite")
			break
		if i%600 == 0: print("PROGRESS %.0fs | food %.1f | health %.1f | particles %d" % [sim.time,sim.player.processed,sim.player.health,sim.particles.size()])
	var elapsed := (Time.get_ticks_usec()-started)/1000000.0
	print("ECOSYSTEM: simulated=%.1f food=%.1f health=%.1f active=%d/%d particles=%d active_particles=%d wall=%.2fs max_tick=%.2fms" % [sim.time,sim.player.processed,sim.player.health,sim.active_cells,sim.cells.size(),sim.particles.size(),sim.active_particles,elapsed,max_tick/1000.0])
	expect(sim.player.processed >= 10,"Default anatomy autonomously feeds and metabolizes")
	expect(sim.won,"Default grazing run can reach the shared adaptation milestone")
	expect(sim.time >= 60,"Default anatomy leaves time to adapt")
	expect(sim.player.energy >= 0 and sim.player.biomass >= 0 and sim.player.oxygen >= 0,"Resources remain nonnegative")
	expect(sim.recycled > 0,"Waste participates in the running ecosystem")
	for cell in sim.cells:
		expect(cell.position.is_finite() and cell.velocity.is_finite(),"Organisms remain finite over sustained play")

func _test_interface() -> void:
	var scene = load("res://scenes/pond.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	expect(scene.batches.size() == 5,"Renderer builds five chemical species")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_2
	scene._input(key)
	expect(scene.selected == 1,"Keyboard selects anatomy")
	var time: float = scene.world.time
	scene._physics_process(DT)
	expect(scene.world.time == time,"Assembly pauses biology")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	scene._update_world(1)
	# Sensing organ sits near 1.15 radians; use the free lower-left surface.
	click.position = scene.camera_screen+Vector2.from_angle(2.15+scene.world.player.angle)*scene.world.player.radius*scene.zoom
	scene._unhandled_input(click)
	expect(scene.build_open and scene.world.player.count("protection") == 1,"Clicking free membrane installs without sockets")
	click.button_index = MOUSE_BUTTON_RIGHT
	scene._unhandled_input(click)
	expect(scene.world.player.count("protection") == 0,"Right-click recycles a freely placed organ")
	key.keycode = KEY_F
	scene._input(key)
	expect(scene.feeding_mode == 1,"Feeding specialization changes within the same category")
	key.keycode = KEY_H
	scene._input(key)
	expect(scene.world.habitat == 1 and scene.selected == -1,"Habitat pressure selection starts a new run")
	scene.cards[0].grab_focus()
	key.keycode = KEY_TAB
	Input.parse_input_event(key.duplicate())
	await process_frame
	expect(scene.build_open and scene.is_paused(),"Tab reaches assembly even with a focused GUI control")
	key.pressed = false
	Input.parse_input_event(key.duplicate())
	key.pressed = true
	Input.parse_input_event(key.duplicate())
	await process_frame
	expect(not scene.build_open and not scene.is_paused(),"Tab closes assembly and resumes observation")
	scene.paused = true
	scene._toggle_build()
	scene._toggle_build()
	expect(scene.is_paused(),"Closing assembly preserves an existing manual pause")
	scene._apply_ui_scale(1.75)
	scene._toggle_build()
	await process_frame
	await process_frame
	scene._layout()
	expect(scene.ui.theme.default_font_size == 35,"HUD scale changes real interface font size")
	expect(scene.build_panel.position.x+scene.build_panel.size.x <= scene.get_viewport_rect().size.x,"Large assembly HUD stays within the viewport")
	expect(scene.vignette.size == scene.get_viewport_rect().size,"Microscope world covers the whole viewport")
	scene.set_fullscreen(true)
	expect(scene.preferences.fullscreen and scene.fullscreen_check.button_pressed,"Fullscreen checkbox reflects display preference")
	key.keycode = KEY_F11
	scene._input(key)
	expect(not scene.preferences.fullscreen,"F11 toggles fullscreen")
	scene.world.player.previous_position = Vector2(4094,1200)
	scene.world.player.position = Vector2(2,1200)
	scene._update_world(0.5)
	expect(scene.views[0].position.length() < 0.001,"Interpolated player stays centered while crossing a world seam")
	scene.queue_free()
	await process_frame

func _test_receptors() -> void:
	var sim = isolated()
	var prey = sim._make_cell(sim.player.position+Vector2(120,0),"hunter")
	prey.organs.clear()
	sim.spawn_particle(Sim.DANGER,prey.position,Vector2.ZERO,1,prey.id,prey.radius)
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(70,0))
	for i in 60: sim._sense(sim.player,DT)
	expect(sim.player.target_mode == "forage" and sim.player.target.x > 0,"Nutrient receptor never automatically flees a larger cell")
	sim.player.organs[1].mode = "flee"
	for i in 60: sim._sense(sim.player,DT)
	expect(sim.player.target_mode == "flee" and sim.player.target.x < 0,"Explicit flight receptor turns away from a detected cell")
	sim.player.recycle(1)
	sim._sense(sim.player,DT)
	expect(sim.player.target_memory == 0 and sim.player.state != "FLEEING","Removing the flight receptor cancels remembered and pending flight signals")
	for mode in ["engulf","parasite"]:
		sim = isolated()
		sim.player.organs.clear()
		if mode == "engulf": sim.player.body = 280
		sim.player.update_geometry()
		sim.player.membrane = Membrane.new(sim.player.radius)
		sim.player.add_organ("feeding",0,mode,false)
		sim.player.add_organ("propulsion",PI,"graze",false)
		prey = sim._make_cell(sim.player.position+Vector2(160,0),"grazer" if mode == "engulf" else "hunter")
		sim.spawn_particle(Sim.DANGER,prey.position,Vector2.ZERO,1,prey.id,prey.radius)
		for i in 60: sim._sense(sim.player,DT)
		expect(sim.player.target_id == prey.id and sim.player.target.x > 0,"Specialized mouth pursues nearby compatible cells without a receptor: "+mode)
		var receptor_mode := "hunt" if mode == "engulf" else "host"
		sim.player.add_organ("sensing",1.2,receptor_mode,false)
		prey.position += Vector2(150,0)
		sim.particles.clear()
		sim.grid.rebuild(sim.particles)
		sim.spawn_particle(Sim.DANGER,prey.position,Vector2.ZERO,1,prey.id,prey.radius)
		for i in 100: sim._sense(sim.player,DT)
		expect(sim.player.target_memory > 0 and sim.player.target_position == prey.position,"Dedicated receptor extends pursuit beyond the mouth's short range: "+mode)

func _test_growth_and_anchors() -> void:
	var sim = isolated()
	var cell = sim.player
	var anchors: Array = cell.organs.map(func(o): return o.a)
	var original: Vector2 = cell.local_point(anchors[0])
	var last_radius: float = cell.radius
	var last_capacity: float = cell.gut_capacity()
	for reserve in [100.0,1000.0,10000.0,1000000.0]:
		cell.biomass = reserve
		cell.update_geometry()
		expect(cell.radius > last_radius and cell.gut_capacity() > last_capacity,"Additional biomass keeps increasing radius and metabolic storage")
		last_radius = cell.radius
		last_capacity = cell.gut_capacity()
		cell.substrate = cell.gut_capacity()
		cell.oxygen = cell.oxygen_capacity()
		cell.energy = 1
		sim._metabolize(cell,1)
		expect(cell.biomass > reserve and cell.energy > 1,"A fed large cell can still gain biomass and ATP")
	for i in 120: cell.membrane.step(DT,cell.radius,Vector2(80,-40),i*DT,1.2)
	cell.angle = 1.4
	cell.position += Vector2(50,25)
	expect(cell.organs.map(func(o): return o.a) == anchors,"Growth and deformation preserve every attachment coordinate")
	expect(cell.local_point(anchors[0]).distance_to(original) > 100,"Anchored organs follow the expanding membrane")

func _test_incremental_grid() -> void:
	var grid = Sim.Grid.new()
	var particles: Array = []
	for i in 120:
		var at := Fluid.wrap_position(Vector2(i*97,i*131))
		particles.append({"p":at,"alive":true})
	grid.rebuild(particles)
	for i in particles.size():
		var old: Vector2 = particles[i].p
		particles[i].p = Fluid.wrap_position(old+Vector2(130,-240))
		grid.move(i,old,particles[i].p)
	var rebuilt = Sim.Grid.new()
	rebuilt.rebuild(particles)
	for at in [Vector2.ZERO,Vector2(4090,2550),Vector2(2000,1000)]:
		var a: Array = grid.query(at,350)
		var b: Array = rebuilt.query(at,350)
		a.sort()
		b.sort()
		expect(a == b,"Incremental spatial movement agrees with a full rebuild, including seams")
	var all: Array = grid.query_rect(Vector2.ZERO,Fluid.WORLD)
	expect(all.size() == particles.size(),"A zoomed-out query returns each wrapped bucket once")

func _test_local_feeding() -> void:
	var sim = isolated()
	var eater = sim.player
	eater.organs.clear()
	eater.add_organ("feeding",0,"parasite",false)
	var prey = sim._make_cell(eater.position+Vector2(110,0),"hunter")
	prey.organs.clear()
	prey.angle = 0
	prey.activity = 1
	prey.add_organ("protection",PI,"graze",false)
	prey.damage(10,0)
	var reserve: float = prey.biomass
	eater.velocity = Vector2(12,0)
	prey.velocity = Vector2(-4,0)
	var momentum: Vector2 = eater.velocity*eater.mass+prey.velocity*prey.mass
	sim._intercell_feeding(0.1)
	expect(prey.biomass == reserve and eater.stolen == 0,"A remote puncture does not bypass armor at the proboscis contact")
	expect(eater.feeding_feedback == "Piercing local armor" and eater.organs[0].feeding,"Proboscis reports and renders its armor contact")
	expect((eater.velocity*eater.mass+prey.velocity*prey.mass).distance_to(momentum) < 0.001,"Feeding grip preserves the pair's momentum")
	for i in 300: sim._intercell_feeding(DT)
	expect(eater.stolen > 0 and eater.feeding_feedback == "Draining biomass","Proboscis drains after piercing its own contact point")

func _test_preferences() -> void:
	var preferences = preload("res://scripts/preferences.gd").new()
	preferences.path = "user://test-preferences-%d.cfg" % Time.get_ticks_usec()
	preferences.fullscreen = true
	preferences.hud_scale = 1.5
	preferences.save_settings()
	var restored = preload("res://scripts/preferences.gd").new()
	restored.path = preferences.path
	restored.load_settings()
	expect(restored.fullscreen and restored.hud_scale == 1.5,"Fullscreen and HUD scale survive settings reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences.path))
