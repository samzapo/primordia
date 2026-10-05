extends RefCounted
## Run-level decisions are event counters, not another per-particle simulation.
const Genes = preload("res://scripts/mutations.gd")
const TIDE_SECONDS := 120.0
const FINALE_START := 720.0
const FINISH := 810.0
const TIDES := [
	{"title":"Emergence","light":1.0,"forecast":"Set up a feeding economy and keep a repair reserve."},
	{"title":"Carbon bloom","light":1.15,"forecast":"New arrivals favor productive grazers."},
	{"title":"Lean current","light":0.8,"forecast":"New arrivals include more hunters; protect your food income."},
	{"title":"Toxin drift","light":0.95,"forecast":"Some incoming hunters carry toxin vesicles."},
	{"title":"Overcast","light":0.55,"forecast":"Photosynthesis weakens. Stored food and shade traits help."},
	{"title":"Armored migration","light":0.85,"forecast":"Some incoming hunters carry additional cortex."},
	{"title":"Long dusk","light":0.55,"forecast":"Your offspring must stay healthy and metabolically active."}
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
	if kind not in ["growth","stability"]: return false
	challenge = kind
	challenge_mass = cell.organic_mass()
	challenge_intake = cell.foreign_intake
	stable_seconds = 0
	return true

func record(kind: String, amount: float) -> void:
	if enabled and exposures.has(kind): exposures[kind] += maxf(0,amount)

func fail(reason: String) -> void:
	if terminal(): return
	status = "lost"
	ending = reason

func advance(dt: float, sim) -> void:
	if not enabled or terminal(): return
	if sim.player.dead or sim.player.health <= 0:
		fail("Your lineage ended. Start a new life.")
		return
	clock += dt
	light_factor = move_toward(light_factor,float(TIDES[tide].light),dt/24.0)
	if challenge == "stability":
		stable_seconds = stable_seconds+dt if sim.player.activity > 0.5 and sim.player.energy >= 25 and sim.player.health >= 60 else 0.0
	var next_tide := mini(6,int(clock/TIDE_SECONDS))
	if next_tide > tide:
		var passed: bool = challenge == "growth" and sim.player.organic_mass() >= challenge_mass+18 and sim.player.foreign_intake >= challenge_intake+18 and sim.player.health >= 60
		passed = passed or (challenge == "stability" and stable_seconds >= 30)
		challenge_result = "+1 adaptation: challenge complete" if passed else "Challenge ended" if challenge != "" else ""
		if passed: points += 1
		challenge = ""
		stable_seconds = 0
		tide = next_tide
		if tide < 6:
			points += 3
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
	if tide == 6:
		if offspring_id < 0:
			if sim.divide_lineage():
				status = "offspring"
				offspring_id = sim.player.id
				viability_food = sim.player.processed
				viability_carbon = sim.player.fixed_carbon
			elif clock >= FINALE_START+30:
				fail("No viable offspring by the final tide. Fund its tissue and ATP before dusk.")
		else:
			viability_window += dt
			if viability_window >= 1.0-0.000001 or clock >= FINISH:
				var metabolism: float = sim.player.processed-viability_food+sim.player.fixed_carbon-viability_carbon
				metabolism_age = 0.0 if metabolism > 0.001 else metabolism_age+viability_window
				if sim.player.activity > 0.5 and sim.player.health >= 50 and sim.player.energy >= 10 and metabolism_age <= 15:
					viable_seconds += viability_window
				viability_window = 0
				viability_food = sim.player.processed
				viability_carbon = sim.player.fixed_carbon
	if clock >= FINISH and not terminal():
		if offspring_id >= 0 and viable_seconds >= 60.0-0.00001 and sim.player.health >= 50:
			status = "won"
			ending = "LINEAGE ESTABLISHED · Your offspring survived the long dusk."
		else: fail("The offspring did not sustain 60 healthy, metabolically active seconds through dusk.")

func newcomer(cell, sim) -> void:
	if not enabled: return
	newcomer_count += 1
	var kind := ""
	if tide == 3 and newcomer_count%2 == 0 and cell.role == "hunter": kind = "toxin"
	elif tide >= 5 and newcomer_count%2 == 0 and cell.role == "hunter": kind = "protection"
	var adaptive := clock >= resistance_clock and newcomer_count%3 == 0 and counter_budget > 0 and resistance != ""
	if adaptive:
		kind = {"toxin":"neutralizing","spike":"protection","acid":"regenerative","photo":"feeding"}.get(resistance,kind)
	if kind != "":
		for i in 12:
			if cell.biomass < cell.organ_cost(kind)+2: break
			if cell.add_organ(kind,TAU*i/12,"graze",true):
				if adaptive: counter_budget -= 1
				sim.events.append({"type":"adapted_arrival","id":cell.id,"organ":kind,"time":sim.time})
				break

func forecast() -> String:
	if terminal(): return ending
	if tide >= 6:
		return "LONG DUSK · %.0f / 60 viable seconds · %ds remain" % [viable_seconds,maxi(0,ceili(FINISH-clock))]
	var seconds := maxi(0,ceili((tide+1)*TIDE_SECONDS-clock))
	var note: String = "Next: "+TIDES[tide+1].title+" in %ds — "%seconds+TIDES[tide+1].forecast
	if resistance != "":
		note += "\nEmerging response: "+{"toxin":"toxin neutralizers","spike":"protective cortex","acid":"buffer-producing repair bodies","photo":"competing grazers"}[resistance]
	return note
