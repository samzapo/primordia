extends RefCounted
## Run-level decisions are event counters, not another per-particle simulation.
const Genes = preload("res://scripts/mutations.gd")
const TIDE_SECONDS := 120.0
const FINALE_START := 720.0
const FINISH := 810.0
const CRISES := ["Lean current","Chemical bloom","Long dusk"]
const CRISIS_STARTS := [120.0,360.0,600.0]
const CRISIS_ENDS := [360.0,600.0,810.0]
const TIDES := [
	{"title":"Emergence","light":1.0,"forecast":"Establish feeding, then fund a successor. Lean Current begins at 2:00."},
	{"title":"Lean current","light":0.70,"forecast":"Hunters arrive after 30 seconds; diminished light makes feeding and reserves matter."},
	{"title":"Lean current deepens","light":0.60,"forecast":"Keep feeding through scarcity. Chemical Bloom begins at 6:00."},
	{"title":"Chemical bloom","light":0.85,"forecast":"An incoming rival carries toxin vesicles. Neutralization, repair or avoidance can help."},
	{"title":"Chemical bloom persists","light":0.65,"forecast":"Prepare an independent successor. Long Dusk begins at 10:00."},
	{"title":"Long dusk","light":0.32,"forecast":"Stored food and efficient feeding matter; a descendant must sustain 60 viable seconds."},
	{"title":"Final dusk","light":0.25,"forecast":"Establish your descendant by 13:30. Inspect the nucleus for exact progress."}
]
var enabled := true
var clock := 0.0
var tide := 0
var points := 3
var offers: Array[String] = []
var learned: Array[String] = []
var chosen := false
var random := RandomNumberGenerator.new()
var status := "growing"
var ending := ""
var light_factor := 1.0
var exposures := {"toxin":0.0,"spike":0.0,"acid":0.0,"photo":0.0}
var resistance := ""
var resistance_clock := 0.0
var newcomer_count := 0
var arrival_budget := 0
var counter_budget := 0
var challenge := ""
var challenge_mass := 0.0
var challenge_intake := 0.0
var stable_seconds := 0.0
var challenge_result := ""
var viable_seconds := 0.0
var viability_window := 0.0
var viability_food := 0.0
var viability_carbon := 0.0
var metabolism_age := INF
var offspring_id := -1
var spending: Array = []
var crisis_seconds := [0.0,0.0,0.0]
var completed := [false,false,false]
var food_seconds := 0.0
var observed_id := -1
var challenge_fixed := 0.0
var challenge_cell := -1
var rivals: Dictionary = {}


func _init(seed_number: int = 0) -> void:
	random.seed = seed_number ^ 0x46ac71
	_draft()

func terminal() -> bool:
	return status in ["won","lost"]

func _draft() -> void:
	offers.clear()
	chosen = false
	var useful: Array = []
	var other: Array = []
	for key in Genes.DATA:
		if Genes.DATA[key].kind == "feeding": continue
		if key in learned: continue
		if Genes.DATA[key].kind in ["feeding","regenerative","protection","photosynthesis","neutralizing"]: useful.append(key)
		else: other.append(key)
	if not useful.is_empty():
		var index := random.randi_range(0,useful.size()-1)
		offers.append(useful.pop_at(index))
	var pool: Array = useful+other
	while offers.size() < 3 and not pool.is_empty():
		offers.append(pool.pop_at(random.randi_range(0,pool.size()-1)))

func choose(identity: String) -> bool:
	if terminal() or chosen or identity not in offers: return false
	learned.append(identity)
	chosen = true
	return true

static func install_price(size: float) -> int:
	return maxi(1,ceili(size*size-0.000001))

func spend(amount: int, action: String) -> bool:
	if amount < 0 or (enabled and (terminal() or points < amount)): return false
	if enabled:
		points -= amount
		spending.append({"time":clock,"action":action,"points":amount})
	return true

func accept_challenge(kind: String, cell) -> bool:
	if not enabled or terminal() or tide >= 6 or challenge != "" or clock-tide*TIDE_SECONDS >= 90: return false
	if kind not in ["growth","stability","metabolism"]: return false
	challenge = kind
	challenge_mass = cell.organic_mass()
	challenge_intake = cell.foreign_intake
	challenge_fixed = cell.fixed_carbon
	challenge_cell = cell.id
	stable_seconds = 0
	return true

func record(kind: String, amount: float) -> void:
	if enabled and exposures.has(kind): exposures[kind] += maxf(0,amount)

func fail(reason: String) -> void:
	if terminal(): return
	status = "lost"
	ending = reason

func crisis() -> int:
	for i in range(2,-1,-1):
		if clock >= CRISIS_STARTS[i]: return i
	return -1

func observe_successor(cell) -> void:
	observed_id = cell.id
	viability_food = cell.processed
	viability_carbon = cell.fixed_carbon
	viability_window = 0
	metabolism_age = INF
	viable_seconds = 0
	stable_seconds = 0

func _viability(dt: float, sim) -> void:
	var cell = sim.player
	if cell.dead or cell.health <= 0: return
	if observed_id != cell.id: observe_successor(cell)
	viability_window += dt
	if viability_window < 1.0-0.000001: return
	var elapsed := minf(1.0,viability_window) # Coarse jumps cannot invent observed survival.
	var metabolism: float = cell.processed-viability_food+cell.fixed_carbon-viability_carbon
	metabolism_age = 0.0 if metabolism > 0.001 else metabolism_age+viability_window
	var healthy: bool = is_viable(cell)
	if healthy:
		food_seconds += elapsed
		if cell.generation > 0: viable_seconds += elapsed
		var stage := crisis()
		if stage >= 0 and (stage < 2 or cell.generation > 0):
			crisis_seconds[stage] += elapsed
	viability_window = 0
	viability_food = cell.processed
	viability_carbon = cell.fixed_carbon

func is_viable(cell) -> bool:
	return not cell.dead and cell.activity > 0.5 and cell.health >= 50 and cell.energy >= 10 and metabolism_age <= 15

func advance(dt: float, sim) -> void:
	if not enabled or terminal(): return
	clock += dt
	light_factor = move_toward(light_factor,float(TIDES[tide].light),dt/24.0)
	_viability(dt,sim)
	if challenge == "stability":
		stable_seconds = stable_seconds+dt if sim.player.id == challenge_cell and not sim.player.dead and sim.player.activity > 0.5 and sim.player.energy >= 25 and sim.player.health >= 60 else 0.0
	var next_tide := mini(6,int(clock/TIDE_SECONDS))
	if next_tide > tide:
		var same: bool = sim.player.id == challenge_cell and not sim.player.dead and sim.player.health >= 60
		var passed: bool = same and challenge == "growth" and sim.player.organic_mass() >= challenge_mass+18 and sim.player.foreign_intake >= challenge_intake+18
		passed = passed or (same and challenge == "stability" and stable_seconds >= 30)
		passed = passed or (same and challenge == "metabolism" and sim.player.foreign_intake-challenge_intake+sim.player.fixed_carbon-challenge_fixed >= 12)
		challenge_result = "+2 adaptation: challenge complete" if passed else "Challenge ended" if challenge != "" else ""
		if passed: points += 2
		challenge = ""
		stable_seconds = 0
		tide = next_tide
		if tide < 6:
			points += 2
			_draft()
		else:
			offers.clear()
			chosen = true
		var best := 1.0
		resistance = ""
		for kind in exposures:
			var score: float = exposures[kind]/float({"toxin":50,"spike":80,"acid":3,"photo":12}[kind])
			if score > best: best = score; resistance = kind
			exposures[kind] = 0.0
		resistance_clock = clock+30
		arrival_budget = 2
		counter_budget = 2
		sim.events.append({"type":"tide","tide":tide,"time":sim.time,"resistance":resistance})
	for i in 3:
		if clock >= CRISIS_ENDS[i]: completed[i] = crisis_seconds[i] >= 60.0-0.00001
	if clock >= FINISH and not terminal():
		if completed.all(func(value): return value) and sim.player.generation > 0 and is_viable(sim.player) and viable_seconds >= 60:
			status = "won"
			ending = "LINEAGE ESTABLISHED · Three crises survived, with an independent descendant.\nYour history and discoveries carry into the next expedition."
		else:
			var reasons: Array[String] = []
			for i in 3:
				if not completed[i]: reasons.append("%s %.0f/60 s" % [CRISES[i],minf(60,crisis_seconds[i])])
			if sim.player.generation == 0: reasons.append("no independent descendant")
			elif viable_seconds < 60: reasons.append("current descendant %.0f/60 viable s" % viable_seconds)
			if sim.player.health < 50: reasons.append("health below 50%")
			if sim.player.energy < 10: reasons.append("ATP below 10")
			if metabolism_age > 15: reasons.append("no recent feeding or fixation")
			if sim.player.activity <= 0.5: reasons.append("current body is outside the observed area")
			fail("EXPEDITION ENDED · "+", ".join(reasons)+".\nFamily history and discovered blueprints are retained.")

func objective(sim) -> String:
	if terminal(): return ending
	if sim.player.dead: return "A funded reserve is waiting for open water to hatch."
	if food_seconds < 15: return "Establish feeding · %.0f / 15 healthy, metabolically active seconds" % food_seconds
	if sim.lineage.births == 0:
		var quote: Dictionary = sim.offspring_quote()
		return "Prepare a successor · %.0f / %.0f tissue · %.0f / 60 ATP" % [sim.player.brood_mass,quote.material,sim.player.brood_energy]
	if sim.player.generation == 0: return "Family prepared · continue as a descendant before Long Dusk ends."
	var stage := crisis()
	if stage < 0: return "Successor prepared · keep feeding; Lean Current begins at 2:00."
	return "%s · %.0f / 60 viable seconds · %d / 3 crises secured" % [CRISES[stage],minf(60,crisis_seconds[stage]),completed.count(true)]

func goal_key(sim) -> String:
	return "%d:%d:%d:%d:%d" % [int(food_seconds >= 15),int(sim.lineage.births > 0),int(sim.player.generation > 0),crisis(),completed.count(true)]

func newcomer(cell, sim) -> void:
	if not enabled: return
	newcomer_count += 1
	var stage := crisis()
	if stage >= 0 and clock >= resistance_clock and not rivals.has(stage):
		var titles := ["Spindle","Cinder","Bastion"]
		cell.rival_name = titles[stage]
		rivals[stage] = cell.id
		var anatomy: Array = [["protection","cilia"],["toxin"],["protection","regenerative"]][stage]
		for organ_kind in anatomy:
			for i in 12:
				if cell.add_organ(organ_kind,TAU*i/12,"graze",true): break
		sim.events.append({"type":"rival","id":cell.id,"name":cell.rival_name,"time":sim.time})
		sim.lineage.notify("%s entered the habitat · its anatomy has ordinary costs and weaknesses." % cell.rival_name)
	var kind := ""
	if tide == 3 and newcomer_count%2 == 0 and cell.role == "hunter": kind = "toxin"
	elif tide >= 5 and newcomer_count%2 == 0 and cell.role == "hunter": kind = "protection"
	var adaptive := clock >= resistance_clock and newcomer_count%3 == 0 and counter_budget > 0 and resistance != ""
	if adaptive:
		kind = {"toxin":"neutralizing","spike":"protection","acid":"regenerative","photo":"cilia"}.get(resistance,kind)
	if kind != "":
		for i in 12:
			if cell.biomass < cell.organ_cost(kind)+2: break
			if cell.add_organ(kind,TAU*i/12,"graze",true):
				if adaptive: counter_budget -= 1
				sim.events.append({"type":"adapted_arrival","id":cell.id,"organ":kind,"time":sim.time})
				break

func forecast() -> String:
	if terminal(): return ending
	var stage := crisis()
	var note := "Goal: establish a lineage through three crises.\n"
	if stage >= 0:
		note += "%s · %.0f / 60 viable seconds · %ds remain\n" % [CRISES[stage],minf(60,crisis_seconds[stage]),maxi(0,ceili(CRISIS_ENDS[stage]-clock))]
	for i in 3:
		note += "%s: %s\n" % [CRISES[i],"secured" if completed[i] else "%.0f / 60 s" % minf(60,crisis_seconds[i])]
	note += "Viable: ≥50% health, ≥10 ATP, recent feeding or carbon fixation.\n"
	note += TIDES[tide].forecast
	if tide < 6: note += "\nNext tide: %s in %ds." % [TIDES[tide+1].title,maxi(0,ceili((tide+1)*TIDE_SECONDS-clock))]
	if resistance != "":
		note += "\nEmerging response: "+{"toxin":"toxin neutralizers","spike":"protective cortex","acid":"buffer-producing repair bodies","photo":"competing grazers"}[resistance]
	return note
