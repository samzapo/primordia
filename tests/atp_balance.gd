extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Cell = Sim.Cell
const DT := 1.0/60

static func run(check: Callable) -> void:
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
	# A finite external stock fed at 0.3 units/s for four minutes, no photo input.
	var stock := 72.0
	var before: float = cell.organic_mass()+stock
	for i in 14400:
		var amount: float = minf(stock,0.3*DT)
		stock -= amount
		cell.substrate += amount
		cell.age += DT
		sim._metabolize(cell,DT)
		for organ in cell.organs:
			if organ.kind == "propulsion": cell.spend_energy(Cell.MOTION_UPKEEP*DT,organ,"movement")
			elif organ.kind == "feeding": cell.spend_energy((Cell.PUMP_UPKEEP+0.35*Cell.SECRETION_COST)*DT,organ,"pumping")
	check.call(cell.energy > 40 and cell.health == 100 and cell.reserve_used == 0,"A finite steady food supply supports two flagella and a pore without burning construction tissue")
	check.call(cell.biomass > 30 and cell.add_organ("photosynthesis",1.2),"Ordinary fermentation growth leaves tissue for another paid organ")
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
	check.call(cell.energy == 0 and cell.health < 100 and cell.processed == processed,"Without real fuel the revised economy still exhausts ATP")
	# Both oxygen-limited and aerobic branches use the same shared parameters.
	cell.energy = 0
	cell.substrate = 1
	cell.oxygen = 0.25
	cell.health = 100
	sim._metabolize(cell,1)
	var yield_atp: float = 0.25*Cell.AEROBIC_ATP+0.75*Cell.FERMENT_ATP
	var expected: float = yield_atp/(1+Cell.ATP_TURNOVER*yield_atp/cell.energy_reference())-Cell.BASAL_UPKEEP*cell.growth_scale()
	check.call(is_equal_approx(cell.energy,expected),"Mixed respiration and fermentation pay exact revised yields and basal cost")
