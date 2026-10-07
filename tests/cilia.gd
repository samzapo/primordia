extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Cell = Sim.Cell
const Medium = Sim.Medium

static func fixture():
	var sim = Sim.new(13013)
	sim.cells = [sim.player]
	sim.pending_replacements.clear()
	sim.particles.clear()
	sim.grid.rebuild(sim.particles)
	sim.habitat_geometry.enabled = false
	sim.player.organs.clear()
	sim.player.add_organ("cilia",0,"graze",false)
	sim.player.position = Vector2(2048,1280)
	sim.player.velocity = Vector2.ZERO
	sim.player.angle = 0
	sim.player.angular_velocity = 0
	sim.player.target = Vector2.RIGHT
	sim.player.facing = Vector2.RIGHT
	sim.player.target_mouth = 0
	sim.player.energy = 72
	sim.fluid.global_coupling = true
	sim.fluid.velocity.fill(Vector2.ZERO)
	return sim

static func run(check: Callable) -> void:
	var sim = Sim.new(77)
	check.call(sim.player.count("propulsion") == 0 and sim.player.count("cilia") == 0 and sim.player.count("feeding") == 1,"Starter has a pore and no free locomotion organ")
	check.call(sim.lineage.dormant[0].count("propulsion")+sim.lineage.dormant[0].count("cilia") == 0,"Founder reserve preserves the same bare starter anatomy")
	var material: float = sim.player.organic_mass()
	var tissue: float = sim.player.biomass
	var ap: int = sim.evolution.points
	check.call(sim.install("cilia",PI/2) and sim.install("propulsion",PI),"Cilia and flagellum are separate buildable purchases")
	check.call(sim.player.biomass == tissue-16 and sim.evolution.points == ap-2 and is_equal_approx(material,sim.player.organic_mass()),"Each propulsion choice transfers eight biomass and costs one AP")
	sim.begin_build()
	check.call(sim.player.count("cilia") == 1 and sim.player.count("propulsion") == 1,"Both purchases survive entering the cell editor")
	sim.commit_build()
	check.call(sim.player.count("cilia") == 1 and sim.player.count("propulsion") == 1,"Both purchases survive applying the cell editor")
	sim = fixture()
	var cell = sim.player
	var organ: Dictionary = cell.organs[0]
	var at: Vector2 = cell.organ_position(organ)+cell.organ_normal(organ).rotated(cell.angle)*8
	var before: Vector2 = sim.fluid.momentum()+cell.velocity*cell.mass
	var spin_before: float = cell.angular_velocity*cell.inertia
	var energy: float = cell.energy
	sim._suction_cell(cell,0.5)
	check.call((sim.fluid.momentum()+cell.velocity*cell.mass-before).length() < 0.01,"Ciliary current returns exact opposite linear momentum to its cell")
	var torque := 0.0
	for i in sim.fluid.velocity.size():
		var node := Vector2(i%Medium.COLS+0.5,int(i/Medium.COLS)+0.5)*Medium.SIZE
		torque += Medium.offset(cell.position,node).cross(sim.fluid.velocity[i]*Medium.NODE_MASS)
	check.call(absf(torque+cell.angular_velocity*cell.inertia-spin_before) < 0.05,"Ciliary current returns exact opposite angular momentum")
	check.call(is_equal_approx(energy-cell.energy,Cell.CILIA_PUMP*0.5),"Ciliary pumping pays the recorded ATP rate")
	var ahead: Vector2 = sim.fluid.sample(at+Vector2(80,0))
	var behind: Vector2 = sim.fluid.sample(at-Vector2(80,0))
	check.call(ahead.x < 0 and absf(ahead.x) > absf(behind.x)*2,"Cilia preferentially draw water from the current receptor/exploration direction")
	var drawn := ahead.length()
	sim.fluid.velocity.fill(Vector2.ZERO)
	cell.velocity = Vector2.ZERO
	cell.angular_velocity = 0
	cell.target = Vector2.LEFT
	sim._suction_cell(cell,0.5)
	check.call(sim.fluid.sample(at-Vector2(80,0)).x > 0 and absf(sim.fluid.sample(at+Vector2(80,0)).x) < drawn,"Changing receptor direction reverses the preferred feeding-current side")
	sim = fixture()
	cell = sim.player
	before = sim.fluid.momentum()+cell.velocity*cell.mass
	energy = cell.energy
	sim._motion_cell(cell,0.1)
	check.call(cell.velocity.length() > 0 and (sim.fluid.momentum()+cell.velocity*cell.mass-before).length() < 0.01,"Cilia propel the body through conservative fluid impulses")
	check.call(is_equal_approx(energy-cell.energy,Cell.CILIA_MOTION*0.1),"Ciliary motion pays its own ATP rate")
	check.call(Cell.organ_upkeep(cell.organs[0]) == Cell.CILIA_PUMP+Cell.CILIA_MOTION,"Cilia preview includes both motion and feeding-current upkeep")
	sim = fixture()
	cell = sim.player
	cell.energy = 0
	sim._suction_cell(cell,0.5)
	sim._motion_cell(cell,0.1)
	check.call(cell.velocity == Vector2.ZERO and sim.fluid.momentum() == Vector2.ZERO,"Empty ATP disables ciliary current and propulsion")
	cell.energy = 72
	cell.organs[0].hp = 0
	sim._suction_cell(cell,0.5)
	sim._motion_cell(cell,0.1)
	check.call(cell.velocity == Vector2.ZERO and sim.fluid.momentum() == Vector2.ZERO,"A destroyed ciliary band cannot pump or propel")
	sim = fixture()
	cell = sim.player
	var prey = sim._make_cell(cell.position+Vector2(100,0),"grazer")
	sim._emit_pheromone(prey)
	sim.grid.rebuild(sim.particles)
	for i in 60: sim._sense(cell,1.0/60)
	check.call(cell.target_id == -1 and not cell.sensed,"Cilia add neither prey nor nutrient sensing")
	sim.particles.clear()
	sim.grid.rebuild(sim.particles)
	sim.spawn_particle(sim.NUTRIENT,cell.position+Vector2(90,0),Vector2.ZERO,0.3,900)
	var eaten: float = cell.eaten
	for i in 20: sim.offscreen_ecology._feed(sim,cell,0.5)
	check.call(cell.eaten == eaten,"Cilia require a feeding pore to absorb nutrients")
	var old_material: float = cell.organic_mass()
	sim.camera_follows_player = false
	sim.camera_position = Vector2.ZERO
	sim.fluid.global_coupling = false
	sim.offscreen_ecology.advance(sim,cell,1)
	check.call(cell.age == 1 and cell.velocity.length() > 0 and not sim.fluid.global_coupling and not sim.coarse_mode,"Hidden cilia use the ordinary paid pumping and motion functions")
	check.call(cell.organic_mass() <= old_material+0.00001,"Hidden cilia grant no material or nutrient bonus")
