extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Cell = preload("res://scripts/cell.gd")
const Ledger = preload("res://scripts/energy_budget.gd")

static func run(check: Callable) -> void:
	var cell = Cell.new()
	cell.add_organ("propulsion",PI,"graze",false)
	var organ: Dictionary = cell.organs[0]
	cell.energy_budget.record(0,0,0,0,-1,"upkeep")
	cell.age = 1
	cell.energy = cell.energy_capacity()-1
	cell.gain_energy(4)
	cell.spend_energy(0.5,organ,"movement")
	var rates: Dictionary = cell.energy_budget.rates(cell.age)
	check.call(is_equal_approx(rates.production,4) and is_equal_approx(rates.stored,1) and is_equal_approx(rates.overflow,3),"ATP accounting separates gross production, accepted reserve income and capacity overflow")
	check.call(is_equal_approx(rates.spent,0.5) and is_equal_approx(rates.net,3.5) and is_equal_approx(rates.reserve_net,0.5),"Production surplus and actual reserve change differ honestly at capacity")
	check.call(is_equal_approx(rates.organs[organ.id],0.5) and is_equal_approx(rates.categories.movement,0.5),"Actual organ spending is attributed to its identity and purpose")
	var energy: float = cell.energy
	var material: float = cell.organic_mass()
	for i in 30: cell.energy_budget.rates(cell.age)
	check.call(cell.energy == energy and cell.organic_mass() == material and cell.energy_budget.rates(cell.age) == rates,"Reading paused ATP rates neither decays them nor changes resources")
	cell.reserve(1)
	check.call(cell.energy_budget.rates(cell.age) == rates,"Moving ATP into a paid offspring reserve is not operating expenditure")

	var empty = Cell.new()
	empty.energy = 0.4
	empty.age = 1
	empty.spend_energy(10,{},"combat",{2:1.0,3:3.0})
	var limited: Dictionary = empty.energy_budget.rates(1)
	check.call(empty.energy == 0 and is_equal_approx(limited.spent*limited.seconds,0.4),"Energy-starved costs record only ATP actually paid")
	check.call(is_equal_approx(limited.organs[2]*limited.seconds,0.1) and is_equal_approx(limited.organs[3]*limited.seconds,0.3),"Coarse spike costs share the actual limited payment without double-counting it")
	check.call(is_equal_approx(limited.categories.combat,limited.spent),"Aggregate coarse cost agrees with per-organ attribution")

	var ledger = Ledger.new()
	for i in 400:
		ledger.record(i*0.05,0.1,0.1,0.05,7,"pumping")
		check.call(ledger.samples.size() <= 12,"Recent ATP history remains bounded regardless of expedition length")
	check.call(not ledger.rates(25).sampled and ledger.rates(25).spent == 0,"An idle period expires older ATP events")
	var other = Cell.new()
	check.call(other.energy_budget.samples.is_empty(),"Another body starts with independent ATP history, rather than inheriting its parent drain")

	check.call(is_equal_approx(Cell.organ_upkeep({"kind":"propulsion","scale":1.0}),0.2),"Default flagellum steady estimate matches its actual stroke cost")
	check.call(is_equal_approx(Cell.organ_upkeep({"kind":"propulsion","scale":1.0,"mutation":"economical_flagellum"}),0.1),"Economical stroke preview halves the operational ATP estimate")
	check.call(is_equal_approx(Cell.organ_upkeep({"kind":"feeding","scale":1.0,"mutation":"wide_pore"}),0.235),"Wide-pore estimate includes pumping, secretion and trait upkeep")
	check.call(is_equal_approx(Cell.organ_upkeep({"kind":"feeding","scale":1.0,"mutation":"enzyme_pore"}),0.212),"Enzyme-pore estimate includes both secretion-rate and per-packet cost changes")

	var observed = Sim.new(846)
	var unobserved = Sim.new(846)
	for body in unobserved.cells: body.energy_budget.enabled = false
	for i in 120:
		observed.step(1.0/60)
		unobserved.step(1.0/60)
	check.call(observed.particles == unobserved.particles and observed.rng.state == unobserved.rng.state and observed.background_rng.state == unobserved.background_rng.state and observed.ecology_rng.state == unobserved.ecology_rng.state,"ATP accounting leaves packet events and all biological random streams unchanged")
	var same: bool = observed.cells.size() == unobserved.cells.size()
	for i in observed.cells.size():
		var a = observed.cells[i]
		var b = unobserved.cells[i]
		same = same and a.position == b.position and a.velocity == b.velocity and a.energy == b.energy and a.organic_mass() == b.organic_mass() and a.health == b.health
	check.call(same,"Enabling ATP observation changes no body trajectory, resources or health")
