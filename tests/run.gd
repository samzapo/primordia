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
	preload("res://tests/acceleration.gd").run(expect)
	preload("res://tests/performance.gd").run(expect)
	preload("res://tests/fluid_options.gd").run(expect)
	preload("res://tests/packed_particles.gd").run(expect)
	preload("res://tests/particle_pool.gd").run(expect)
	preload("res://tests/hotloop.gd").run(expect)
	preload("res://tests/threading.gd").run(expect)
	preload("res://tests/resident_particles.gd").run(expect)
	preload("res://tests/chemical_neighbors.gd").run(expect)
	preload("res://tests/liquid_particles.gd").run(expect)
	preload("res://tests/parcel_transport.gd").run(expect)
	preload("res://tests/particle_collisions.gd").run(expect)
	preload("res://tests/habitat.gd").run(expect)
	preload("res://tests/porous_habitat.gd").run(expect)
	preload("res://tests/art.gd").run(expect)
	_test_metabolism()
	_test_anatomy()
	_test_receptors()
	preload("res://tests/pheromones.gd").run(expect)
	preload("res://tests/steering.gd").run(expect)
	preload("res://tests/foraging.gd").run(expect)
	preload("res://tests/anatomy_geometry.gd").run(expect)
	preload("res://tests/reaction_feedback.gd").run(expect)
	_test_packing_and_size()
	_test_pump_and_facing()
	_test_coverage_and_pulses()
	_test_particle_exclusion()
	_test_gel_polygons()
	_test_microtubules()
	preload("res://tests/music.gd").new().run(self)
	_test_resource_animation()
	preload("res://tests/energy_budget.gd").run(expect)
	preload("res://tests/atp_balance.gd").run(expect)
	preload("res://tests/cilia.gd").run(expect)
	preload("res://tests/size_drag.gd").run(expect)
	_test_growth_and_anchors()
	_test_incremental_grid()
	_test_local_feeding()
	_test_preferences()
	_test_damage()
	_test_fluid()
	_test_propulsion_and_toxins()
	_test_membrane()
	_test_wrap_and_dormancy()
	preload("res://tests/visibility.gd").run(expect)
	preload("res://tests/offscreen_transport.gd").run(expect)
	preload("res://tests/offscreen_ecology.gd").run(expect)
	_test_contacts()
	preload("res://tests/contacts.gd").run(expect)
	_test_chemistry()
	_test_receptor_competition()
	_test_feeding()
	_test_death()
	_test_closed_budget()
	_test_crowded_ecology()
	_test_autonomous_diets()
	_test_autonomous_hunting()
	_test_habitat_pressures()
	_test_replay()
	_test_ecosystem()
	preload("res://tests/evolution.gd").new().run(self)
	preload("res://tests/lineage.gd").run(expect)
	await preload("res://tests/interface.gd").new().run(self)
	print("RESULT: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func isolated():
	var sim = Sim.new(41)
	sim.cells = [sim.player]
	sim.pending_replacements.clear()
	sim.particles.clear()
	return sim

func organic(sim) -> float:
	var total: float = sim.lineage.stored_material()
	for cell in sim.cells:
		if not cell.dead: total += cell.organic_mass()
	for p in sim.particles:
		if p.alive and p.kind not in [Sim.OXYGEN,Sim.PHEROMONE]: total += p.amount + p.get("product",0.0)
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
	expect(cell.substrate == 0 and cell.oxygen == 0 and is_equal_approx(cell.processed-cell.fermented,0.25),"Available oxygen bounds the aerobic share; fermentation processes remaining food")
	expect(is_equal_approx(cell.biomass-biomass,0.4),"Mixed metabolism uses the appropriate biomass yields")
	expect(is_equal_approx(cell.organic_mass()+sim.respiration_loss,mass),"Metabolism accounts for biomass, waste and lost end products")
	var processed: float = cell.processed
	cell.biomass = 8
	sim._metabolize(cell,1)
	expect(cell.processed == processed,"No food or mobilizable reserves means no metabolism")

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
	expect(cell.add_organ("sensing",0),"Insertion moves existing organs to make room")
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
	sim.player.add_organ("toxin",2.1,"graze",false)
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(80,0))
	sim.grid.rebuild(sim.particles)
	for i in 45: sim._sense(sim.player,DT)
	sim._emit_and_attack(sim.player,DT)
	var toxins := 0
	for p in sim.particles:
		if p.kind == Sim.TOXIN: toxins += 1
	expect(toxins == 0,"Food sensing alone does not trigger wasteful attacks")
	var threat = sim._make_cell(sim.player.position+Vector2(100,0),"hunter")
	sim.player.add_organ("sensing",1.2,"flee",false)
	preload("res://tests/pheromones.gd").deliver(sim,threat)
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
	expect(is_equal_approx(prey.health,88.75) and not sim.particles[-1].alive,"Toxin contact damages a cell once")
	sim._toxin_contacts()
	expect(is_equal_approx(prey.health,88.75),"Consumed toxin cannot apply damage twice")

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
	expect(absf(membrane.points[0].length()-membrane.points[7].length()) > 2,"Gel cortex supports a noncircular cell")
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
	sim.spawn_particle(Sim.WASTE,distant.position,Vector2(25,0),2)
	var dormant_packet: Dictionary = sim.particles[-1]
	var stored = dormant_packet.duplicate(true)
	for i in 120: sim.step(DT)
	expect(distant.position != location and distant.biomass != reserve and distant.age > 0,"Offscreen organisms move and metabolize on their coarse clock")
	expect(absf(distant.age+distant.coarse_elapsed-sim.time) < 0.0001,"Coarse scheduling retains all elapsed biology time")
	expect(dormant_packet.p != stored.p and dormant_packet.age > 0,"Offscreen resources continue coarse transport")
	expect(dormant_packet.get("chemical_at",0) > 0,"Chemistry near a hidden cell advances on its coarse clock")
	var corner: Vector2 = sim.screen_position(Vector2(4093,1200))
	expect(absf(corner.x-(Sim.VIEW.x*0.5-7))<20,"Camera projects seam neighbors continuously")
	expect(Fluid.visibility(Vector2(0,0),Vector2(0,0)) == 1,"Microscope center is fully active")
	expect(Fluid.visibility(Vector2(470,300),Vector2.ZERO) == 1,"Visible corners run at full speed despite peripheral blur")

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
	sim.spawn_particle(Sim.WASTE,sim.player.position,Vector2.ZERO,0.3,0)
	sim.spawn_particle(Sim.OXYGEN,sim.player.position+Vector2(5,0),Vector2.ZERO,0.3,0)
	var a: Dictionary = sim.particles[0]
	var b: Dictionary = sim.particles[1]
	a.direction = Vector2.LEFT
	b.direction = Vector2.LEFT
	sim._chemistry(0.0000001)
	expect(a.kind == Sim.WASTE,"Wrong binding orientation prevents recycling despite contact")
	a.direction = Vector2.RIGHT
	var before: float = organic(sim)
	sim._chemistry(0.0000001)
	expect(a.kind == Sim.NUTRIENT and b.kind == Sim.CARBON,"Aligned contact deterministically recycles waste into food and carbon")
	expect(absf(organic(sim)-before) < 0.001,"Pair reaction conserves organic material")
	expect(sim.particles.size() == 2,"Reaction transforms existing packets without ambient creation")
	sim = isolated()
	sim.spawn_particle(Sim.ENZYME,sim.player.position,Vector2.ZERO,0.1,0)
	sim.spawn_particle(Sim.WASTE,sim.player.position+Vector2(5,0),Vector2.ZERO,0.3,0)
	a = sim.particles[0]; b = sim.particles[1]
	expect(sim._react_pair(a,b,0.3) and a.kind == Sim.ENZYME and b.kind == Sim.NUTRIENT,"Digestive enzyme remains reusable after conversion")
	sim.spawn_particle(Sim.ANTITOXIN,sim.player.position,Vector2.ZERO,0.1,0)
	sim.spawn_particle(Sim.TOXIN,sim.player.position,Vector2.ZERO,0.2,1)
	a = sim.particles[-2]; b = sim.particles[-1]
	before = organic(sim)
	expect(sim._react_pair(a,b) and a.kind == Sim.WASTE and not b.alive,"Neutralizer binds toxin into harmless material")
	expect(absf(organic(sim)-before) < 0.001,"Neutralization retains both reactants' material")
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position,Vector2.ZERO,0.3,0)
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position,Vector2.ZERO,0.4,0)
	a = sim.particles[-2]; b = sim.particles[-1]
	expect(sim._react_pair(a,b) and is_equal_approx(a.amount,0.7) and not b.alive,"Nutrient assembly makes a larger edible packet with combined value")
	expect(Sim.binding_threshold(Sim.ENZYME,Sim.WASTE,0.4) < Sim.binding_threshold(Sim.ENZYME,Sim.WASTE,0),"Modeled acid hydrolase binds more readily at its acidic optimum")
	expect(Sim.binding_threshold(Sim.NUTRIENT,Sim.NUTRIENT,0.4) == Sim.binding_threshold(Sim.NUTRIENT,Sim.NUTRIENT,0),"Acidity does not magically favor nutrient synthesis")
	var stressed = isolated()
	stressed.acidity.values.fill(0.9)
	var energy: float = stressed.player.energy
	stressed._acid_stress(stressed.player,1)
	expect(stressed.player.energy < energy and stressed.player.health == 100,"Short acidic exposure costs ATP before causing health loss")
	for i in 20: stressed._acid_stress(stressed.player,1)
	expect(stressed.player.acid_stress > 0.6 and stressed.player.health < 100,"Sustained overwhelming acidity causes accumulated stress and damage")
	stressed.acidity.values.fill(0)
	for i in 20: stressed._acid_stress(stressed.player,1)
	expect(stressed.player.acid_stress == 0,"Acid stress recovers after leaving corrosive conditions")
	var hits := 0
	for i in 10000: if sim.chance(1,0.1): hits += 1
	expect(hits > 800 and hits < 1100,"Decay hazard samples expected continuous-time probability")
	sim.acidity.exchange(sim.player.position,0.8)
	var initial: float = sim.acidity.sample(sim.player.position)
	sim.spawn_particle(Sim.BUFFER,sim.player.position,Vector2.ZERO,0.2,0)
	sim.particles[-1].capacity = 0.3
	for i in 60:
		sim.revision += 1
		sim._chemistry(DT)
	expect(sim.acidity.sample(sim.player.position) < initial,"Finite buffer particles reduce environmental acidity")

func _test_feeding() -> void:
	var sim = isolated()
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(90,0))
	sim._sense(sim.player,0.01)
	expect(not sim.player.signals.is_empty(),"Chemical sensing emits internal signal particles")
	for i in 60: sim._sense(sim.player,DT)
	expect(sim.player.target.x > 0,"Arriving internal signals drive innate motion preference")

func _test_death() -> void:
	var sim = isolated()
	var hunter = sim._make_cell(sim.player.position+Vector2(180,0),"hunter")
	var id: int = hunter.id
	var mass: float = hunter.organic_mass()
	var oxygen: float = hunter.oxygen
	sim._die(hunter)
	var released := 0.0
	var oxygen_released := 0.0
	for p in sim.particles:
		if p.kind == Sim.NUTRIENT: released += p.amount
		elif p.kind == Sim.OXYGEN: oxygen_released += p.amount
	expect(hunter.dead and hunter.health == 0 and not sim.cells.has(hunter),"Hunter dies and is removed, never reset")
	expect(is_equal_approx(released,mass),"Dead hunter releases its retained biomass")
	expect(is_equal_approx(oxygen_released,oxygen) and hunter.oxygen == 0,"Death transfers retained oxygen exactly")
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
	sim = isolated()
	sim.camera_follows_player = false
	var saved_rng: int = sim.rng.state
	# Put the free camera exactly over the first candidate: it must be rejected.
	sim.camera_position = Fluid.wrap_position(sim.player.position+Vector2.from_angle(sim.rng.randf()*TAU)*1100)
	sim.rng.state = saved_rng
	sim.pending_replacements.append({"role":"hunter","id":999})
	sim._replace_population()
	expect(sim.pending_replacements.is_empty() and sim.cells.size() == 2 and sim.activity_at(sim.cells[-1].position) == 0,"Replacement respects the unlocked camera instead of the player position")


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
	var largest_step := 0.0
	for i in 360:
		var before: Vector2 = sim.player.position
		sim.step(DT)
		largest_step = maxf(largest_step,Fluid.offset(before,sim.player.position).length())
	var elapsed := (Time.get_ticks_usec()-started)/1000.0
	print("CROWDED: 13 initial cells, 360 ticks, mean %.2f ms, active %d" % [elapsed/360,sim.active_cells])
	for cell in sim.cells:
		expect(cell.position.is_finite() and cell.angular_velocity == cell.angular_velocity,"Crowded coupled ecosystem stays finite")
	print("CROWDED movement: net=%.1f largest_tick=%.2f" % [Fluid.offset(origin,sim.player.position).length(),largest_step])
	expect(largest_step < 15,"Crowded lower-inertia motion stays continuous without teleporting")

func _test_autonomous_diets() -> void:
	var sim = isolated()
	var cell = sim.player
	cell.organs.clear()
	cell.add_organ("photosynthesis",0,"graze",false)
	cell.carbon = 20
	var before: float = organic(sim)
	for i in 600: sim._photosynthesize(cell,DT)
	expect(cell.fixed_carbon > 0 and cell.oxygen_produced > 0,"Photosynthesis fixes carbon and releases oxygen under light")
	expect(absf(organic(sim)-before) < 0.001,"Photosynthesis transfers carbon to food and biomass without inventing organic material")
	for particle in sim.particles: expect(particle.owner == cell.id,"Photosynthetic particles retain their source cell")
	sim._sense(cell,1)
	for i in 60: sim._sense(cell,DT)
	expect(cell.target_mode == "light" and cell.target.dot(sim.light_direction(cell.position)) > 0.9,"Photosynthetic organelle steers toward brighter habitat")
	cell.carbon = 0
	var count: int = sim.particles.size()
	for i in 60: sim._photosynthesize(cell,DT)
	expect(sim.particles.size() == count,"Photosynthesis needs carbon as well as light")

func _test_habitat_pressures() -> void:
	var lean = Sim.new(4,1)
	var rich = Sim.new(4,2)
	expect(lean.particles.size() < rich.particles.size(),"Lean habitat begins with fewer cell-derived nutrients")
	expect(lean.light_at(lean.player.position) < rich.light_at(rich.player.position),"Lean habitat offers less photosynthetic energy")
	for cell in rich.cells:
		if cell.role == "hunter": expect(cell.count("offensive") == 1 and cell.count("protection") >= 4,"Rich hunters share spike and armor anatomy")
	for particle in rich.particles: if particle.owner < 0: expect(false,"Every starting particle must originate from a cell")
	var empty = isolated()
	empty.player.organs.clear()
	empty.player.substrate = 0
	empty.player.carbon = 0
	empty.player.waste = 0
	for i in 120: empty.step(DT)
	var food := 0
	for particle in empty.particles: if particle.kind == Sim.NUTRIENT or particle.kind == Sim.OXYGEN: food += 1
	expect(food == 0,"Empty habitat never replenishes food or oxygen without a source cell process")

func _test_replay() -> void:
	var a = Sim.new(12)
	var b = Sim.new(12)
	for i in 90:
		a.step(DT)
		b.step(DT)
	expect(a.player.position == b.player.position and a.particles == b.particles,"Same-seed replay matches on the same engine/platform")

func _test_ecosystem() -> void:
	var sim = Sim.new()
	expect(sim.install("propulsion",PI),"Opening ecosystem pays for a chosen flagellum")
	sim.view_half = Sim.VIEW # Normal half-zoom play includes the local producer community.
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
	expect(sim.player.processed >= 10,"A paid opening flagellum and pore autonomously feed and metabolize")
	expect(not sim.won,"Early food processing is not lineage victory")
	expect(sim.time >= 60,"Default anatomy leaves time to adapt")
	expect(sim.player.energy >= 0 and sim.player.biomass >= 0 and sim.player.oxygen >= 0,"Resources remain nonnegative")
	expect(sim.recycled > 0,"Waste participates in the running ecosystem")
	for cell in sim.cells:
		expect(cell.position.is_finite() and cell.velocity.is_finite(),"Organisms remain finite over sustained play")


func _test_receptors() -> void:
	var sim = isolated()
	var prey = sim._make_cell(sim.player.position+Vector2(150,0),"hunter")
	prey.organs.clear()
	preload("res://tests/pheromones.gd").deliver(sim,prey)
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(90,0))
	for i in 60: sim._sense(sim.player,DT)
	expect(sim.player.count("sensing") == 0 and sim.player.target_mode == "graze" and sim.player.target.x > 0,"Grazing pore owns nutrient sensing without automatic flight")
	expect(not sim.player.add_organ("sensing",1.2,"hunt",false),"Flight receptors cannot silently switch to pursuit")
	sim.player.add_organ("sensing",1.2,"flee",false)
	sim.particles[0].p = sim.player.organ_position(sim.player.organs[-1])+Vector2(20,0)
	sim.grid.rebuild(sim.particles)
	for i in 60: sim._sense(sim.player,DT)
	expect(sim.player.target_mode == "flee" and sim.player.target.x < 0 and sim.player.facing.x > 0,"Flight faces the threat and requests movement away")
	sim.player.recycle(sim.player.organs.size()-1)
	sim._sense(sim.player,DT)
	expect(sim.player.state != "FLEEING","Removing flight organ cancels its memory and pending signals")
	sim = isolated()
	sim.player.organs.clear()
	sim.player.add_organ("hunting",1.2,"hunt",false)
	prey = sim._make_cell(sim.player.position+Vector2(600,0),"grazer")
	preload("res://tests/pheromones.gd").deliver(sim,prey)
	for i in 60: sim._sense(sim.player,DT)
	expect(sim.player.target_id == prey.id and sim.player.target.x > 0,"Hunting receptor learns about distant lower-biomass prey from a locally delivered pheromone")
	expect(absf(sim.player.target_mouth-1.2) < 0.01,"Pursuit faces the hunting receptor toward the reported prey")
	prey.body = 500
	prey.add_organ("protection",0,"graze",false)
	sim.time += 0.1
	preload("res://tests/pheromones.gd").deliver(sim,prey)
	for i in 100: sim._sense(sim.player,DT)
	expect(sim.player.target_id == -1,"Hunting receptor ignores a larger defended report")
	expect(not sim.player.add_organ("feeding",0,"engulf",false) and not sim.player.add_organ("feeding",0,"parasite",false),"Removed feeding specializations cannot be installed")

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
	eater.add_organ("offensive",0,"graze",false)
	var prey = sim._make_cell(eater.position+Vector2(108,0),"grazer")
	prey.organs.clear()
	prey.angle = 0
	prey.activity = 1
	prey.add_organ("protection",PI,"graze",false)
	var armor: float = prey.organs[0].hp
	var before: float = organic(sim)
	sim._spike_contacts(0.1)
	expect(prey.health == 100 and prey.organs[0].hp < armor,"Spike hits local armor before membrane")
	expect(eater.feeding_feedback == "SPIKE CONTACT","Physical spike contact is visible")
	expect(absf(organic(sim)-before) < 0.001,"Spike damage accounts for released material")
	prey.position = eater.position-Vector2(108,0)
	var health: float = prey.health
	sim._spike_contacts(0.1)
	expect(prey.health == health,"Spike cannot hit a cell behind its tip")

func _test_preferences() -> void:
	var preferences = preload("res://scripts/preferences.gd").new()
	preferences.path = "user://test-preferences-%d.cfg" % Time.get_ticks_usec()
	preferences.fullscreen = true
	preferences.bloom = false
	preferences.water_ripples = false
	preferences.hud_scale = 1.5
	preferences.save_settings()
	var restored = preload("res://scripts/preferences.gd").new()
	restored.path = preferences.path
	restored.load_settings()
	expect(restored.fullscreen and restored.hud_scale == 1.5 and not restored.bloom and not restored.water_ripples,"Water shimmer, fullscreen, bloom and HUD scale survive settings reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences.path))

func _test_packing_and_size() -> void:
	var cell = Cell.new()
	cell.biomass = 200
	cell.update_geometry()
	cell.membrane = Membrane.new(cell.radius)
	cell.add_organ("sensing",-0.25,"flee",false)
	cell.add_organ("sensing",0.25,"flee",false)
	var before_left: float = wrapf(cell.organs[0].a,-PI,PI)
	var before_right: float = wrapf(cell.organs[1].a,-PI,PI)
	var reserve: float = cell.biomass
	expect(cell.add_organ("protection",0,"graze",true,1.7),"A large organ can be inserted between neighbors")
	expect(wrapf(cell.organs[0].a,-PI,PI) < before_left and wrapf(cell.organs[1].a,-PI,PI) > before_right,"Insertion pushes neighbors to both sides")
	expect(is_equal_approx(reserve-cell.biomass,10*1.7*1.7),"Organelle biomass cost scales with its area")
	for i in cell.organs.size():
		for j in range(i+1,cell.organs.size()):
			expect(absf(cell.arc_gap(cell.organs[i].a,cell.organs[j].a)) >= (Cell.organ_width(cell.organs[i])+Cell.organ_width(cell.organs[j]))*0.5-0.01,"Packing leaves room for scaled footprints")
	var tiny = Cell.new()
	expect(not tiny.add_organ("feeding",0,"engulf",false,30),"Total surface area still bounds an oversized organ")

func _test_pump_and_facing() -> void:
	var sim = isolated()
	var cell = sim.player
	sim.fluid.velocity.fill(Vector2.ZERO)
	sim.fluid.activity.fill(1)
	var mouth: Vector2 = cell.pore_center(cell.organs[0])
	var before: Vector2 = cell.velocity*cell.mass+sim.fluid.momentum()
	sim._suction(0.2)
	expect(sim.fluid.sample(mouth+Vector2(70,0)).x < 0,"Feeding pump pulls real surrounding fluid toward the pore")
	expect((cell.velocity*cell.mass+sim.fluid.momentum()).distance_to(before) < 0.1,"Pore pumping returns equal opposite momentum to the cell")
	var receiver = Cell.new(99,mouth+Vector2(70,0))
	receiver.update_geometry()
	sim.fluid.exchange(receiver,Vector2.ZERO,0.5)
	expect(receiver.velocity.x < 0,"Pore-induced fluid flow entrains a nearby passive cell through drag")
	var light = isolated()
	var strong = isolated()
	for fixture in [light,strong]:
		fixture.player.organs.clear()
		fixture.fluid.velocity.fill(Vector2.ZERO)
		fixture.fluid.activity.fill(1)
		fixture.player.add_organ("propulsion",PI,"graze",false,2 if fixture == strong else 1)
		fixture.player.target = Vector2.RIGHT
		fixture.player.facing = Vector2.RIGHT
		fixture._motion(DT)
	expect(strong.player.velocity.x > light.player.velocity.x*1.5,"Larger flagellum gives stronger acceleration despite its added material")
	for fleeing in [false,true]:
		sim = isolated()
		cell = sim.player
		cell.organs.clear()
		cell.add_organ("sensing" if fleeing else "feeding",PI*0.5,"flee" if fleeing else "graze",false)
		cell.add_organ("propulsion",PI,"graze",false)
		cell.facing = Vector2.RIGHT
		cell.target = Vector2.LEFT if fleeing else Vector2.RIGHT
		cell.target_mouth = PI*0.5
		sim.fluid.velocity.fill(Vector2.ZERO)
		sim.fluid.activity.fill(1)
		var origin: Vector2 = cell.position
		for i in 240: sim._motion(DT)
		var facing: Vector2 = cell.local_point(cell.organs[0].a).rotated(cell.angle).normalized()
		var travel := Fluid.offset(origin,cell.position)
		expect(facing.x > 0.85,"The detecting surface organ turns toward its target, including during flight")
		expect(travel.x < -5 if fleeing else travel.x > 5,"Propulsion translates away during flight and toward food during pursuit")

func _test_coverage_and_pulses() -> void:
	var sim = isolated()
	var cell = sim.player
	cell.substrate = 0
	var organ: Dictionary = cell.organs[0]
	sim.spawn_particle(Sim.NUTRIENT,cell.pore_center(organ),Vector2.ZERO,0.4)
	sim._feed(cell)
	expect(is_equal_approx(cell.substrate,0.4) and organ.consume_flash > 0,"Grazing consumes nutrients and visibly pulses")

func _test_particle_exclusion() -> void:
	var sim = isolated()
	sim.player.position = Vector2(2,1200)
	for i in 20: sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2.from_angle(i)*float(i))
	var before: float = organic(sim)
	sim._exclude_particles()
	for p in sim.particles:
		var d := Fluid.offset(sim.player.position,p.p)
		expect(d.length() >= sim.player.support(d.angle())+6.9,"External particle is shunted beyond the membrane, including across a seam")
	expect(is_equal_approx(organic(sim),before),"Boundary shunting preserves material")

func _test_gel_polygons() -> void:
	var membrane = Membrane.new(55)
	var smallest := INF
	var largest := 0.0
	for i in 600:
		if i%7 == 0: membrane.points[i%membrane.COUNT] *= 0.15
		membrane.step(DT,55,Vector2(240*sin(i),100*cos(i)),i*DT)
		if i%30 == 0:
			var outline: PackedVector2Array = membrane.outline()
			expect(Geometry2D.triangulate_polygon(outline).size() == (outline.size()-2)*3,"Compressed gelatinous membrane remains valid for polygon rendering")
	for point in membrane.points:
		smallest = minf(smallest,point.length())
		largest = maxf(largest,point.length())
	expect(largest-smallest > 7,"Gel membrane has visible lobes rather than an ellipse template")
	var cell = Cell.new()
	cell.membrane = membrane
	var outline: PackedVector2Array = membrane.outline()
	for i in 80:
		var a := TAU*i/80
		var inside := Vector2.from_angle(a)*(cell.visible_support(a)-0.1)
		var outside := Vector2.from_angle(a)*(cell.visible_support(a)+0.1)
		expect(Geometry2D.is_point_in_polygon(inside,outline) and not Geometry2D.is_point_in_polygon(outside,outline),"Fast visible-boundary sampling matches the actual rendered polygon")

func _test_resource_animation() -> void:
	var cell = Cell.new()
	cell.add_organ("propulsion",PI,"graze",false)
	var before: float = cell.energy
	cell.spend_energy(1,cell.organs[0])
	expect(is_equal_approx(before-cell.energy,1) and not cell.resource_packets.is_empty(),"Real ATP spending launches nucleus-to-organelle packets")
	for i in 20: cell.animate_resources(DT)
	expect(cell.resource_packets.is_empty() or cell.resource_packets[0].p.distance_to(Vector2(-0.15,-0.15)*cell.radius) > 5,"ATP particles travel outward from the nucleus")
	cell.damage(25,0)
	var reserve: float = cell.biomass
	cell.heal(1)
	var repairs := 0
	for packet in cell.resource_packets:
		if packet.kind == "repair": repairs += 1
	expect(cell.biomass < reserve and repairs > 0,"Actual membrane repair spends biomass and launches repair particles")

func _test_microtubules() -> void:
	var membrane = Membrane.new(60)
	var network = membrane.skeleton
	network.links.clear()
	var group: int = network.connect_points({"kind":"membrane","a":0.2},{"kind":"membrane","a":3.3},0.1,membrane,60)
	expect(group >= 0 and network.links.size() == 1,"Microtubule joins arbitrary fractional membrane points")
	var original: int = network.links[0].id
	var branch: int = network.connect_points({"kind":"link","id":original,"t":0.43},{"kind":"membrane","a":1.7},0.5,membrane,60)
	expect(branch >= 0 and network.links.size() == 3 and network.junctions.size() == 1,"Branching splits a microtubule into linked segments at a movable junction")
	var first: int = network.links[0].id
	var second: int = network.links[-1].id
	expect(network.connect_points({"kind":"link","id":first,"t":0.5},{"kind":"link","id":second,"t":0.5},0.4,membrane,60) >= 0,"Microtubules can connect a point on one link to a point on another")
	network.set_tension(group,0.8)
	for link in network.links:
		if link.group == group: expect(link.tension == 0.8,"Split segments retain the parent's adjustable tension")
	for i in 240: membrane.step(DT,60,Vector2.ZERO,2)
	expect(Geometry2D.triangulate_polygon(membrane.outline()).size() > 0,"Branched tension network leaves a renderable membrane")
	for junction in network.junctions.values(): expect(junction.p.is_finite(),"Internal branch junction stays finite")
	var slack = Membrane.new(60)
	var taut = Membrane.new(60)
	for ring in [slack,taut]:
		ring.skeleton.links.clear()
		ring.skeleton.connect_points({"kind":"membrane","a":0},{"kind":"membrane","a":PI},0 if ring == slack else 0.9,ring,60)
	for i in 240:
		slack.step(DT,60,Vector2.ZERO,0)
		taut.step(DT,60,Vector2.ZERO,0)
	var slack_span: float = slack.points[0].distance_to(slack.points[14])
	var taut_span: float = taut.points[0].distance_to(taut.points[14])
	expect(taut_span < slack_span*0.9,"Increasing microtubule tension visibly pulls its membrane anchors together")
	network.remove_group(group)
	for link in network.links: expect(link.group != group,"Removing a microtubule removes all of its split segments")

func _test_receptor_competition() -> void:
	var sim = isolated()
	var cell = sim.player
	var receptor: Dictionary = cell.organs[0]
	var at: Vector2 = cell.organ_position(receptor)+Vector2(8,0)
	sim.spawn_particle(Sim.DECOY,at,Vector2.ZERO,0.03,99)
	var p: Dictionary = sim.particles[-1]
	p.direction = Vector2.RIGHT
	sim._receptor_contacts()
	expect(receptor.blocked == 0 and p.alive,"Decoy must align with the receptor binding face")
	p.direction = Vector2.LEFT
	var before: float = organic(sim)
	sim._receptor_contacts()
	expect(receptor.blocked > 0 and not p.alive,"Aligned decoy temporarily occupies the receptor")
	expect(absf(organic(sim)-before) < 0.001,"Bound decoy material is accounted in cellular waste")
	var block: float = receptor.blocked
	var energy: float = cell.energy
	sim._clear_receptors(cell,1)
	expect(receptor.blocked < block and cell.energy < energy,"Every receptor automatically spends ATP to clear competition")
	receptor.blocked = block
	cell.add_organ("regenerative",1.5,"graze",false)
	sim._clear_receptors(cell,1)
	expect(receptor.blocked < block-0.4,"Repair bodies accelerate clearing")
	receptor.blocked = 1
	cell.energy = 0
	for i in 25: sim._clear_receptors(cell,1)
	expect(receptor.blocked == 0,"Passive release restores a receptor even without ATP")
	cell.organs = [receptor]
	cell.energy = 72
	sim.spawn_particle(Sim.NUTRIENT,cell.position+Vector2(230,0),Vector2.ZERO,1,99)
	for i in 60: sim._sense(cell,DT)
	expect(cell.target_memory > 0,"Clean pore can sense distant nutrients")
	receptor.blocked = 1
	cell.signals.clear()
	cell.target_memory = 0
	for i in 120: sim._sense(cell,DT)
	expect(cell.target_memory == 0,"Occupied receptor has reduced chemical sensing range")

func _test_autonomous_hunting() -> void:
	var sim = isolated()
	var cell = sim.player
	cell.organs.clear()
	cell.body = 180
	cell.biomass = 60
	cell.substrate = 0
	cell.update_geometry()
	cell.membrane = Membrane.new(cell.radius)
	cell.add_organ("feeding",1.3,"graze",false)
	cell.add_organ("offensive",-0.45,"graze",false)
	cell.add_organ("offensive",0.45,"graze",false)
	cell.add_organ("hunting",0,"hunt",false)
	cell.add_organ("propulsion",PI,"graze",false)
	var prey = sim._make_cell(cell.position+Vector2(190,0),"grazer")
	prey.organs.clear()
	prey.body = 25
	prey.biomass = 3
	prey.update_geometry()
	prey.membrane = Membrane.new(prey.radius)
	for i in 160: sim.spawn_particle(Sim.OXYGEN,cell.position+Vector2.from_angle(i*2.4)*(70+i%40*5),Vector2.ZERO,0.4,prey.id)
	for i in 1800: sim.step(DT)
	print("HUNT: kills=%d eaten=%.2f processed=%.2f health=%.1f" % [sim.kills,cell.eaten,cell.processed,cell.health])
	expect(sim.kills >= 1 and cell.eaten > 0,"Autonomous spike pursuit kills prey and the grazing pore consumes released food")
	expect(cell.processed > 0 and cell.health > 0,"Hunting contributes to ordinary metabolism and survival")
