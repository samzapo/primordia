extends VBoxContainer
## Build-only controls. The simulation owns transactions and all prices.
var game
var run_label := Label.new()
var forecast_label := Label.new()
var budget_label := Label.new()
var offspring_label := Label.new()
var reserve_row := HFlowContainer.new()
var offers := VBoxContainer.new()
var anatomy := VBoxContainer.new()
var detail := VBoxContainer.new()
var existing_id := -1
var moving := false
var signature := ""
var sections: Dictionary = {}

func initialize(owner_game) -> void:
	game = owner_game
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",10)
	for name in ["modify","genome","lineage"]:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation",10)
		add_child(box)
		sections[name] = box
	for label in [run_label,forecast_label,budget_label,offspring_label]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sections.lineage.add_child(run_label)
	sections.lineage.add_child(offspring_label)
	sections.lineage.add_child(reserve_row)
	game._button(reserve_row,"Reserve +10",func(): game.world.player.reserve(10,game.world.offspring_quote().material); refresh())
	game._button(reserve_row,"Withdraw 10",func(): game.world.player.reserve(-10); refresh())
	sections.lineage.add_child(forecast_label)
	var challenges := HFlowContainer.new()
	sections.lineage.add_child(challenges)
	game._button(challenges,"Risk: growth",func(): _challenge("growth"))
	game._button(challenges,"Risk: stability",func(): _challenge("stability"))
	game._label(sections.lineage,"Optional +1 AP next tide: retain 18 new tissue from outside your cell with health ≥60%, or finish with 30 steady seconds at health ≥60%, ATP ≥25. Accept during the first 90s; one per tide.",game.MUTED)
	game._label(sections.genome,"Keep one blueprint per tide. Apply it to a matching organ under Modify.",game.MUTED)
	sections.genome.add_child(offers)
	sections.modify.add_child(budget_label)
	game._label(sections.modify,"Choose an existing organ.",game.MINT)
	sections.modify.add_child(anatomy)
	sections.modify.add_child(detail)
	game._button(sections.modify,"Shape microtubules",func(): existing_id = -1; moving = false; game.selected = -1; signature = ""; refresh())
	show_section("genome")
	refresh()

func _challenge(kind: String) -> void:
	if game.world.evolution.accept_challenge(kind,game.world.player):
		game._message("Challenge planned. Apply to accept it.")
	else: game._message("One challenge per tide; accept before its last 30 seconds.")
	refresh()

func _clear(container: Node) -> void:
	for node in container.get_children():
		container.remove_child(node)
		node.queue_free()

func inspect(identity: int) -> void:
	existing_id = identity
	moving = false
	game.selected = -1
	signature = ""
	refresh()

func refresh() -> void:
	if game == null: return
	var sim = game.world
	var cell = sim.player
	var run = sim.evolution
	var quote: Dictionary = sim.offspring_quote()
	var budget: Dictionary = cell.operating_budget()
	run_label.text = "%s · Tide %d / 6 · %d AP" % [run.TIDES[run.tide].title,mini(6,run.tide+1),run.points]
	forecast_label.text = run.forecast()
	budget_label.text = "Active upkeep ≈ %.2f ATP/s · Stored fuel %.0f ATP" % [budget.steady,budget.fuel]
	offspring_label.text = "OFFSPRING RESERVE\n%.1f / %.1f biomass · %.0f / 60 ATP\nOxygen available: %.1f (up to 12 transfers)\nParent contributes %.1f structural tissue. Low oxygen uses fermentation.\nAuto-division at 12:00. Sustain the offspring through 13:30." % [cell.brood_mass,quote.material,cell.brood_energy,cell.oxygen,quote.body_transfer]
	reserve_row.visible = run.offspring_id < 0
	if run.offspring_id >= 0:
		offspring_label.text = "OFFSPRING VIABILITY\n%.1f / 60 healthy, active seconds\nHealth %.0f%% · ATP %.1f\nKeep feeding through the 13:30 deadline." % [run.viable_seconds,cell.health,cell.energy]
	if run.challenge != "": forecast_label.text += "\nChallenge accepted: "+run.challenge
	elif run.challenge_result != "": forecast_label.text += "\n"+run.challenge_result
	var reserve_fuel: float = minf(maxf(0,cell.biomass-8),0.3*cell.growth_scale()) if cell.energy < 20 and cell.substrate < 1 else 0.0
	var capacity: float = 1.8*cell.growth_scale()*(1-cell.acid_stress*0.6)
	var aerobic: float = minf(minf(cell.substrate+reserve_fuel,cell.oxygen),capacity)
	var income: float = aerobic*5+minf(maxf(0,cell.substrate+reserve_fuel-aerobic),maxf(0,capacity-aerobic))*2
	for organ in cell.organs:
		if organ.kind == "photosynthesis" and cell.carbon > 0:
			var light: float = sim.light_at(cell.organ_position(organ))
			income += minf(cell.carbon,3.5*light*organ.scale*organ.scale*sim.Genes.factor(organ,"sun" if light >= 0.5 else "shade"))*4
	budget_label.text += "\nNext-second estimate: %+.1f ATP" % (income-budget.steady)
	budget_label.tooltip_text = "Estimate uses current food, oxygen and light, with all secretors active. Enzymes respond to waste, antitoxin to foreign toxin, buffers to acidity; actual quiet-water upkeep can be lower. Healing, pursuit and combat cost extra. Below 12 ATP, discretionary secretion rests; feeding and repair continue. Below 20 ATP, biomass above the protected 8-unit reserve can supply fuel. Oxygen-poor fermentation gives less ATP and tissue per food and loses material as unrecoverable byproducts."
	if cell.biomass < 8: budget_label.text += "\nLow repair reserve: less than 8 tissue remains."
	var ids: Array = []
	for organ in cell.organs: ids.append([organ.id,organ.kind,organ.scale,organ.get("mutation","")])
	var scars: Array = []
	for organ in cell.lost_organs: scars.append(organ.id)
	var key := str([run.tide,run.offers,run.chosen,run.learned,ids,scars,existing_id])
	if key == signature: return
	signature = key
	_clear(offers)
	_clear(anatomy)
	_clear(detail)
	if not run.chosen:
		for gene in run.offers:
			var data: Dictionary = sim.Genes.DATA[gene]
			game._label(offers,data.title+" · "+data.text,game.TEXT)
			game._button(offers,"Keep "+data.title,func(): run.choose(gene); refresh())
	else: game._label(offers,"Blueprint kept. Next draft arrives with the tide.",game.MUTED)
	for organ in cell.organs:
		var title: String = game.TITLES[sim.KINDS.find(organ.kind)]
		game._button(anatomy,"%s · %.2f×%s" % [title,organ.scale," ★" if organ.get("mutation","") != "" else ""],inspect.bind(organ.id))
	for record in cell.lost_organs:
		game._label(anatomy,"Lost %s · %.1f tissue · 0 AP" % [game.TITLES[sim.KINDS.find(record.kind)],record.max_material],game.MUTED)
		game._button(anatomy,"Restore organ",func():
			game._message("Restoration planned." if cell.restore_organ(record.id) else "Restoration needs tissue and membrane room.")
			refresh())
	var organ: Dictionary = cell.organ_by_id(existing_id)
	if organ.is_empty(): existing_id = -1; return
	game._label(detail,"SELECTED · "+game.TITLES[sim.KINDS.find(organ.kind)],game.GOLD)
	var controls := HFlowContainer.new()
	detail.add_child(controls)
	game._button(controls,"Move (free)",func(): moving = true; game._message("Click a membrane location to move this organ."))
	game._button(controls,"Smaller",func(): resize(1.0/1.1))
	game._button(controls,"Larger",func(): resize(1.1))
	game._button(controls,"Recycle 50%",func(): sim.remove(cell.organs.find(organ)); existing_id = -1; refresh())
	game._label(detail,"Enlargement: 1 AP per added unit area, cumulatively rounded up. Tissue scales with area. Shrinking/recycling returns half the removed tissue; no AP refund.",game.MUTED)
	if organ.get("mutation","") != "":
		var data: Dictionary = sim.Genes.DATA[organ.mutation]
		game._label(detail,data.title+" · "+data.text,game.GOLD)
	else:
		var found := false
		for gene in run.learned:
			var data: Dictionary = sim.Genes.DATA[gene]
			if data.kind != organ.kind: continue
			found = true
			game._label(detail,"%s · %d AP / %.1f tissue\n%s" % [data.title,sim.Genes.adaptation_price(organ),sim.Genes.price(organ),data.text],game.MUTED)
			game._button(detail,"Apply mutation",func():
				game._message("Specialization planned." if sim.mutate_organ(existing_id,gene) else "Needs more AP or tissue.")
				refresh())
		if not found: game._label(detail,"No matching blueprint kept yet.",game.MUTED)

func resize(factor: float) -> void:
	var organ: Dictionary = game.world.player.organ_by_id(existing_id)
	if organ.is_empty(): return
	var size := maxf(0.5,float(organ.scale)*factor)
	game._message("Resize planned." if game.world.resize_organ(existing_id,size) else "Resize needs AP, tissue and membrane room.")
	refresh()

func show_section(name: String) -> void:
	for key in sections: sections[key].visible = key == name
