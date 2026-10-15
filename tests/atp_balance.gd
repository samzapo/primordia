extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Cell = Sim.Cell
const DT := 1.0/60

static func run(check: Callable) -> void:
	if not preload("res://tests/test_policy.gd").GAMEPLAY_BALANCE_ENABLED:
		preload("res://tests/test_policy.gd").skip("ATP economy tuning")
		return
	var sim = preload("res://tests/pheromones.gd").isolated()
	var cell = sim.player
	cell.organs.clear()
	cell.add_organ("feeding",0,"graze",false)
	cell.add_organ("propulsion",PI,"graze",false)
	cell.add_organ("propulsion",2.2,"graze",false)
	cell.biomass = 18
	cell.substrate = 0
	cell.oxygen = 0
	cell.energy = 60
	# A finite external stock fed at 0.5 units/s for four minutes, no photo input.
	var stock := 120.0
	var before: float = cell.organic_mass()+stock
	for i in 14400:
		var amount: float = minf(stock,0.5*DT)
		stock -= amount
		cell.substrate += amount
		cell.oxygen += amount # Finite oxygen accompanies this fixture's finite food stock.
		cell.age += DT
		sim._metabolize(cell,DT)
		for organ in cell.organs:
			if organ.kind == "propulsion": cell.spend_energy(Cell.MOTION_UPKEEP*DT,organ,"movement")
			elif organ.kind == "feeding": cell.spend_energy((Cell.PUMP_UPKEEP+0.35*Cell.SECRETION_COST)*DT,organ,"pumping")
	check.call(cell.energy > 12 and cell.health == 100 and cell.reserve_used == 0,"A finite steady food and oxygen supply supports two flagella and a pore without burning construction tissue")
	check.call(cell.biomass > 30 and cell.add_organ("photosynthesis",1.2),"Ordinary digestive growth leaves tissue for another paid organ")
	check.call(absf(cell.organic_mass()+stock+sim.respiration_loss-before) < 0.00001,"Easier ATP yields still conserve finite food and ordinary material losses")
	# Empty reserves still impose scarcity; there is no passive free ATP.
	cell.substrate = 0
	cell.oxygen = 0
	cell.biomass = 8
	cell.energy = 1
	var processed: float = cell.processed
	for i in 1200:
		cell.age += DT
		sim._metabolize(cell,DT)
	check.call(cell.energy == 0 and cell.starvation_seconds>10 and cell.health==100 and cell.processed == processed,"Without fuel ATP exhausts, but a short shortage cannot kill a cell")
	# One unit of fueled food retains .7 tissue and credits 2.25 numeric ATP.
	var fresh=Cell.new();fresh.energy=0;fresh.substrate=1;fresh.oxygen=1
	var initial_biomass: float=fresh.biomass
	fresh.chemistry.advance(fresh,10)
	check.call(is_equal_approx(fresh.energy,2.25) and is_equal_approx(fresh.biomass-initial_biomass,.7),"Respiration pays the conservative tissue/ATP yield with local oxygen")
