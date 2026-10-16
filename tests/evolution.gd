extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Cell = Sim.Cell
var suite
func check(condition: bool, message: String) -> void: suite.expect(condition,"Economy: "+message)
func total(sim) -> float:
	var mass := 0.0
	for cell in sim.cells:
		if not cell.dead: mass += cell.organic_mass()
	for particle in sim.particles:
		if particle.alive: mass += particle.amount*Sim.Catalog.material(particle.kind)
	return mass+sim.build_waste+sim.lineage.stored_material()-sim.external_input

func run(owner_suite) -> void:
	if not preload("res://tests/test_policy.gd").GAMEPLAY_OBJECTIVES_ENABLED:
		preload("res://tests/test_policy.gd").skip("gameplay objectives and progression")
		return
	suite = owner_suite
	var sim = Sim.new(713)
	sim.habitat_geometry.enabled = false
	check(sim.cells.size() == 16 and sim.pending_replacements.size() == 3,"balanced opening reserves three later hunter arrivals")
	check(sim.pending_replacements.map(func(item): return item.not_before) == [150.0,390.0,630.0],"one bounded arrival follows each crisis warning")
	check(sim.evolution.points == 3 and sim.evolution.offers.size() == 3,"functional starter and initial three-option draft")
	sim.time = 150
	sim.evolution.clock = 149.9
	sim._replace_population()
	check(sim.cells.size() == 16,"reserved migrants wait for the director to cross the tide boundary")
	sim.time = 0
	sim.evolution.clock = 0
	var original = sim.player
	var initial_mass := total(sim)
	var offers: Array = sim.evolution.offers.duplicate()
	sim.begin_build()
	check(sim.player != original and sim.player.membrane != original.membrane,"planning clones anatomy and membrane")
	check(sim.player.membrane.skeleton != original.membrane.skeleton,"planning clones tension network")
	check(sim.install("neutralizing",2.0),"affordable installation accepted")
	check(sim.evolution.points == 2,"one normal organ spends one AP")
	sim.player.membrane.skeleton.set_tension(0,0.9)
	sim.evolution.choose(offers[0])
	sim.evolution.accept_challenge("stability",sim.player)
	sim.step(10)
	check(sim.time == 0 and sim.evolution.clock == 0,"preview pauses physics and tides")
	sim.remove(sim.player.organs.size()-1)
	check(sim.build_waste > 0 and absf(total(sim)-initial_mass) < 0.01,"preview recycling accounts for deferred debris")
	sim.cancel_build()
	check(sim.player == original and sim.evolution.points == 3,"cancel restores anatomy and AP")
	check(sim.evolution.learned.is_empty() and not sim.evolution.chosen and sim.evolution.challenge == "","cancel restores draft and challenge choices")
	check(sim.build_waste == 0 and absf(total(sim)-initial_mass) < 0.01,"cancel emits no particles or mass")
	check(sim.evolution.offers == offers,"opening and cancelling cannot reroll offers")
	sim.begin_build()
	var radius: float = sim.player.radius
	var capacity: float = sim.player.energy_reference()
	sim.player.reserve(10)
	check(is_equal_approx(sim.player.radius,radius) and is_equal_approx(sim.player.energy_reference(),capacity),"reserve allocation preserves volume and operating capacity")
	check(is_equal_approx(total(sim),initial_mass),"reserving transfers tissue without new material")
	sim.undo_build()
	check(sim.player.brood_mass == 0 and sim.player.brood_energy == 0,"undo restores reserves")
	sim.install("neutralizing",2.0)
	sim.commit_build()
	check(sim.player.count("neutralizing") == 1 and sim.evolution.points == 2,"apply keeps paid anatomy")
	var before: float = sim.player.biomass
	sim.evolution.points = 0
	check(not sim.install("poreforming",1.0) and sim.player.biomass == before,"insufficient AP is atomic")
	sim.evolution.points = 20
	sim.player.biomass = 600
	sim.player.update_geometry()
	sim.player.membrane = Cell.Membrane.new(sim.player.radius)
	var twin = Cell.clone_state(sim.player)
	var id: int = sim.player.organs[-1].id
	var start_points: int = sim.evolution.points
	for size in [1.05,1.1,1.15,1.2]: check(sim.resize_organ(id,size),"small enlargement accepted")
	var direct: Dictionary = twin.resize_organ(id,1.2)
	check(start_points-sim.evolution.points == direct.ap,"tiny enlargements cost the same cumulative AP")
	var spent: int = sim.evolution.points
	check(sim.resize_organ(id,0.8) and sim.resize_organ(id,1.2),"shrink and regrow supported")
	check(sim.evolution.points < spent,"shrink cannot refund or reset purchased capacity")
	for gene in Sim.Genes.DATA:
		if Sim.Genes.DATA[gene].kind == "feeding": continue
		var cell = Cell.new()
		cell.biomass = 500
		cell.update_geometry()
		cell.membrane = Cell.Membrane.new(cell.radius)
		var kind: String = Sim.Genes.DATA[gene].kind
		cell.add_organ(kind,0,"graze",true)
		var mass: float = cell.organic_mass()
		check(cell.specialize(0,gene),"specialization "+gene)
		check(not cell.specialize(0,gene),"one specialization per organ "+gene)
		check(absf(cell.organic_mass()-mass) < 0.01,"mutation preserves material "+gene)
		var health: float = cell.organs[0].max_hp
		cell.waste += cell.damage(health,0)
		check(cell.organs.is_empty() and cell.lost_organs.size() == 1,"destroyed trait retained for restoration "+gene)
		check(cell.restore_organ(0) and cell.organs[0].mutation == gene,"restoration retains paid trait "+gene)
		check(absf(cell.organic_mass()-mass) < 0.01,"restoration transfers actual replacement material "+gene)
	var e = Sim.Evolution.new(713)
	check(e.offers == offers,"same seed reproduces draft")
	e.clock = 119.9
	e.advance(0.11,sim)
	check(e.tide == 1 and e.points == 5,"tide grants exactly two baseline AP")
	e.advance(0.1,sim)
	check(e.points == 5,"milestone reward cannot repeat")
	check(e.choose(e.offers[0]) and not e.choose(e.offers[1]),"one blueprint per tide")
	check(e.accept_challenge("stability",sim.player) and not e.accept_challenge("growth",sim.player),"one optional challenge")
	e.stable_seconds = 31
	e.clock = 239.9
	e.advance(0.11,sim)
	check(e.points == 9,"two earned AP plus the two-point tide allowance")
	sim.evolution.exposures.toxin = 100
	sim.evolution.clock = 119.9
	sim.evolution.advance(0.11,sim)
	check(sim.evolution.resistance == "toxin" and sim.evolution.resistance_clock > sim.evolution.clock,"exposure announces a delayed counter")
	var npc = Cell.new()
	npc.biomass = 80
	npc.role = "grazer"
	sim.evolution.newcomer_count = 2
	var npc_mass: float = npc.organic_mass()
	sim.evolution.newcomer(npc,sim)
	check(npc.count("neutralizing") == 0,"counter cannot arrive during warning")
	sim.evolution.clock += 31
	sim.evolution.newcomer_count = 2
	sim.evolution.newcomer(npc,sim)
	check(npc.count("neutralizing") == 1 and npc.biomass < 80,"counter uses paid physical anatomy")
	check(is_equal_approx(npc.organic_mass(),npc_mass),"counter material conserved")
	for count in [5,8]:
		var other = Cell.new()
		other.biomass = 80
		sim.evolution.newcomer_count = count
		sim.evolution.newcomer(other,sim)
		check(other.count("neutralizing") == (1 if count == 5 else 0),"at most two adaptive counters per tide")
	# Own-packet cycling or free remodeling cannot manufacture a growth bonus.
	var challenge_run = Sim.Evolution.new(5)
	check(challenge_run.accept_challenge("growth",sim.player),"growth challenge accepted")
	sim.player.biomass += 20 # Fixture represents recovered previously secreted tissue.
	challenge_run.clock = 119.9
	challenge_run.advance(0.11,sim)
	check(challenge_run.points == 5,"growth bonus also requires outside intake")
	# Division fixture funds reserves explicitly to isolate the transfer, without
	# representing a playthrough or claiming these resources were earned.
	sim = Sim.new(29)
	sim.habitat_geometry.enabled = false
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.player.biomass = 300
	sim.player.energy = 90
	sim.player.reserve(200)
	sim.player.brood_energy = 60
	sim.player.oxygen = 20
	var parent = sim.player
	var parental_body: float = parent.body
	var structural_share: float = sim.offspring_quote().body_transfer
	var mass := total(sim)
	var energy: float = parent.energy+parent.brood_energy
	var oxygen: float = parent.oxygen
	check(sim.divide_lineage(),"funded lineage divides")
	check(sim.player.id != parent.id and parent.role == "ancestor","control transfers to autonomous offspring")
	check(absf(total(sim)-mass) < 0.01,"offspring receives real parental tissue")
	check(is_equal_approx(parent.body,parental_body-structural_share) and parent.body >= 30,"division partitions structural tissue and retains a viable parental body")
	check(is_equal_approx(parent.energy+parent.brood_energy+sim.player.energy,energy-20),"division spends 20 ATP and transfers 40")
	check(is_equal_approx(parent.oxygen+sim.player.oxygen,oxygen),"offspring oxygen is transferred")
	check(sim.external_input == 0,"offspring is not an external population introduction")
	check(not sim.divide_lineage(),"another offspring still needs a separately funded reserve")
	check(sim.player.membrane.skeleton != parent.membrane.skeleton,"offspring tension network is independent")
	check(sim.player.lineage_id() == parent.lineage_id(),"offspring inherits self-recognition")
	sim.spawn_particle(sim.TOXIN,sim.player.position+Vector2.RIGHT*sim.player.radius,Vector2.ZERO,1,parent.id)
	sim._toxin_contacts()
	check(sim.player.health == 100,"parental toxin is recognized as self")
	sim.spawn_particle(sim.TOXIN,parent.position+Vector2.RIGHT*parent.radius,Vector2.ZERO,1,sim.player.id)
	sim._toxin_contacts()
	check(parent.health == 100,"offspring toxin is recognized by parent")
	parent.add_organ("poreforming",0,"graze",false)
	sim.spawn_particle(sim.TAG,sim.player.position+Vector2.RIGHT*sim.player.radius,Vector2.ZERO,0.03,parent.id)
	sim.particles[-1].direction=Vector2.LEFT
	sim._surface_contacts()
	check(sim.player.surface_complexes.is_empty(),"Parent chemical secretion cannot mark offspring")

	sim.spawn_particle(sim.TOXIN,sim.player.position+Vector2.RIGHT*sim.player.radius,Vector2.ZERO,0.1,999)
	sim._toxin_contacts()
	check(sim.player.organs[0].hp < sim.player.organs[0].max_hp or sim.player.health < 100,"unrelated toxins remain harmful")
	sim.player.health = 100
	sim.evolution.status = "offspring"
	sim.evolution.tide = 6
	sim.evolution.clock = 720
	sim.evolution.crisis_seconds = [60.0,60.0,0.0]
	for i in 65: sim.evolution.advance(1,sim)
	check(sim.evolution.viable_seconds == 0,"alive without metabolism is not viability")
	for i in 10:
		sim.player.processed += 1
		sim.player.activity = 0
		sim.evolution.advance(1,sim)
	check(sim.evolution.viable_seconds == 0,"offscreen dormancy cannot finish viability")
	sim.evolution.clock = 720
	sim.player.activity = 1
	for i in 90:
		sim.player.processed += 0.1
		sim.evolution.advance(1,sim)
	check(sim.evolution.status == "won","sustained health, ATP and metabolism wins at deadline")
	var time: float = sim.time
	sim.step(1)
	check(sim.time == time,"terminal run stops the simulation")
	sim = Sim.new(29)
	sim.evolution.clock = 809
	sim.evolution.tide = 6
	sim.evolution.advance(1,sim)
	check(sim.evolution.status == "lost","the final deadline requires a prepared lineage and completed crises")

	var anaerobic = Sim.new(31)
	anaerobic.habitat_geometry.enabled = false
	anaerobic.cells = [anaerobic.player]
	var anaerobic_quote: Dictionary = anaerobic.offspring_quote()
	anaerobic.player.biomass += anaerobic_quote.material
	anaerobic.player.reserve(maxf(60,anaerobic_quote.material),anaerobic_quote.material)
	anaerobic.player.oxygen = 0
	check(anaerobic.divide_lineage() and anaerobic.player.oxygen == 0,"funded fermentation-capable offspring does not require an oxygen quota")
	var reserve_cell = Cell.new()
	reserve_cell.biomass = 100
	reserve_cell.energy = 100
	reserve_cell.reserve(60,42)
	check(reserve_cell.brood_mass == 42 and reserve_cell.brood_energy == 60,"reserve quotas fill independently without surplus tissue")
	if preload("res://tests/test_policy.gd").GAMEPLAY_BALANCE_ENABLED:
		var starving = Cell.new()
		starving.energy = 0
		starving.substrate = 0
		starving.biomass = 20
		starving.oxygen = 10
		var starving_mass: float = starving.organic_mass()
		sim._metabolize(starving,1)
		check(starving.reserve_used>0 and starving.biomass<20 and starving.substrate>0,"Starvation transfers surplus biomass into finite metabolic fuel")
		check(is_equal_approx(starving.organic_mass(),starving_mass),"reserve respiration conserves organic material")
		starving.oxygen = 0
		var remaining: float = starving.biomass
		sim._metabolize(starving,1)
		check(starving.biomass<remaining and starving.oxygen==0 and starving.fermented>0,"Mobilized food can ferment without oxygen")
		starving.oxygen = 10
		starving.biomass = 8;starving.substrate=0;starving.energy=0
		sim._metabolize(starving,1)
		check(starving.biomass == 8,"emergency metabolism protects the last repair reserve")
	else: preload("res://tests/test_policy.gd").skip("emergency reserve metabolic yields")
	sim = Sim.new(22)
	sim.particles.clear()
	sim.grid.rebuild(sim.particles)
	var secreter = Cell.new(1003,sim.player.position)
	for kind in ["feeding","neutralizing","regenerative"]: secreter.add_organ(kind,TAU*secreter.organs.size()/3,"graze",false)
	secreter.carbon = 0
	var secretion_mass: float = secreter.biomass
	var secretion_energy: float = secreter.energy
	sim._emit_and_attack(secreter,100)
	check(secreter.biomass == secretion_mass and secreter.energy == secretion_energy,"clean water does not drain conditional secretions")
	sim.spawn_particle(sim.WASTE,secreter.organ_position(secreter.organs[0]),Vector2.ZERO,1,999)
	sim.spawn_particle(sim.TOXIN,secreter.organ_position(secreter.organs[1]),Vector2.ZERO,1,999)
	sim.acidity.values.fill(0.1)
	sim._emit_and_attack(secreter,100)
	check(is_equal_approx(secreter.biomass,secretion_mass-0.18),"waste, toxin and acid trigger three paid secretions")
	check(is_equal_approx(secreter.energy,secretion_energy-3*Cell.SECRETION_COST),"conditional secretion pays actual ATP")
	var secreted: Array = []
	for packet in sim.particles:
		if packet.kind in [sim.ENZYME,sim.ANTITOXIN,sim.BUFFER]: secreted.append(packet.kind)
	check(secreted.size() == 3,"all three triggered particle species are emitted")
	if not preload("res://tests/test_policy.gd").GAMEPLAY_BALANCE_ENABLED:
		preload("res://tests/test_policy.gd").skip("fermentation yields and live victory playthrough")
		return
	var fermenter = Cell.new()
	fermenter.substrate = 1
	fermenter.oxygen = 0
	fermenter.energy = 0
	var ferment_mass: float = fermenter.organic_mass()
	var prior_loss: float = sim.respiration_loss
	fermenter.chemistry.advance(fermenter,10)
	check(fermenter.processed == 1 and fermenter.energy > 0 and fermenter.oxygen == 0,"Finite vacuole food yields ATP without oxygen after residence")
	check(is_equal_approx(fermenter.organic_mass()+sim.respiration_loss-prior_loss,ferment_mass),"fermentation accounts for unrecoverable end products")
	check(is_zero_approx(fermenter.raw_fuel) and is_equal_approx(fermenter.energy,Cell.FERMENT_ATP),"Spent food and waste cannot close a free-energy loop")
	# Live finale integration, distinct from an earned-resource playthrough.
	# A finite donor supplies known cell-sourced packets to isolate the objective.
	sim = Sim.new(18)
	sim.habitat_geometry.enabled = false
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.pending_replacements.clear()
	var quote: Dictionary = sim.offspring_quote()
	sim.player.biomass += quote.material
	sim.player.reserve(maxf(quote.material,quote.energy),quote.material)
	sim.player.oxygen = 24
	sim.evolution.clock = 719.99
	sim.time = 719.99
	sim.evolution.crisis_seconds = [60.0,60.0,0.0] # Earlier crises are explicit fixture preconditions.
	check(sim.divide_lineage(),"a funded successor can be released before dusk")
	var donor = Cell.new(1001,sim.Medium.wrap_position(sim.player.position+Vector2(1700,1000)))
	donor.body = 500
	donor.oxygen = 200
	sim.cells.append(donor)
	var starting_material := total(sim)
	for tick in 5500:
		if sim.evolution.terminal(): break
		if tick%60 == 0 and sim.evolution.offspring_id >= 0:
			var pore: Dictionary = sim.player.organs[0]
			donor.body -= 1.4
			donor.oxygen -= 1.4
			sim.spawn_particle(sim.NUTRIENT,sim.player.pore_center(pore),Vector2.ZERO,1.4,donor.id)
			sim.spawn_particle(sim.OXYGEN,sim.player.position+Vector2.RIGHT*(sim.player.radius+8),Vector2.ZERO,1.4,donor.id)
		sim.step(1.0/60)
	check(sim.won and sim.evolution.offspring_id >= 0,"real physics, feeding, division and finale reach victory")
	check(sim.evolution.viable_seconds >= 60,"live offspring sustains measured viability")
	check(absf(total(sim)+sim.respiration_loss-starting_material) < 0.15,"live finale including parental death accounts for material and decay loss")
