extends Control
## Cell-local entry points replace the HUD and assembly/modify panes.
var pathways := preload("res://scripts/chemistry_editor.gd").new()
const Interior = preload("res://scripts/cell_interior.gd")
const Action = preload("res://scripts/cell_action.gd")
const Biomass = preload("res://scripts/biomass_preview.gd")
var game
var interior := Interior.new()
var biomass_view := Biomass.new()
var choices: Array[Button] = []
var context: Dictionary = {}
var hovered: Dictionary = {}
var hovered_price: Dictionary = {}
var tip_box := PanelContainer.new()
var tip := Label.new()
var message := Label.new()
var edit_hint := Label.new()
var menu_center := Vector2.ZERO
var menu_radius := 100.0
var keyboard_index := -1
var keyboard_target: Dictionary = {}
var last_tide := 0
var last_resistance := ""
var last_ending := ""
var last_critical := false
var last_lineage := 0
var last_goal := ""

func initialize(owner_game) -> void:
	game = owner_game
	add_child(pathways)
	pathways.initialize(game)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interior.game = game
	interior.z_index = 3
	game.world_layer.add_child(interior)
	biomass_view.game = game
	add_child(biomass_view)
	add_child(tip_box)
	tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_box.add_child(tip)
	tip_box.z_index = 20
	for label in [message,edit_hint]:
		add_child(label)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_outline_color",Color("122443"))
		label.add_theme_constant_override("outline_size",6)
	tip_box.hide()
	reset()

func reset() -> void:
	interior.ecology = Interior.Ecology.new()
	close_context()
	keyboard_index = -1
	keyboard_target.clear()
	last_tide = game.world.evolution.tide
	last_resistance = ""
	last_ending = ""
	last_critical = false
	last_lineage = game.world.lineage.serial
	last_goal = game.world.evolution.goal_key(game.world)

func close_context() -> void:
	pathways.hide()
	context.clear()
	hovered_price.clear()
	for choice in choices:
		remove_child(choice)
		choice.queue_free()
	choices.clear()
	tip_box.hide()
	biomass_view.sync()
	queue_redraw()

func screen_at(target: Dictionary) -> Vector2:
	var cell = game.world.player
	var p := Vector2.ZERO
	if target.kind in ["organ","scar"]:
		var record: Dictionary = cell.organ_by_id(target.id) if target.kind == "organ" else {}
		if target.kind == "scar":
			for scar in cell.lost_organs:
				if scar.id == target.id: record = scar; break
		if not record.is_empty():
			p = cell.local_point(record.a)
			p += cell.local_normal(record.a)*5*record.scale
	else: p = interior.anchors.get("nucleus" if target.kind in ["lineage","archive","past"] else target.kind,Vector2.ZERO)
	return game.world_layer.to_global(interior.position+p.rotated(interior.rotation))

func targets() -> Array:
	var result: Array = []
	for kind in ["assembly","chemistry","nucleus","bud","atp"]: result.append({"kind":kind})
	for organ in game.world.player.organs: result.append({"kind":"organ","id":organ.id})
	for scar in game.world.player.lost_organs: result.append({"kind":"scar","id":scar.id})
	return result

func hit(screen: Vector2) -> Dictionary:
	if interior.anchors.is_empty() or not interior.visible: return {}
	var nearest := {}
	var best := INF
	for target in targets():
		var radius := maxf(18*game.preferences.hud_scale,interior.anchors.radius*game.zoom*(0.28 if target.kind == "nucleus" else 0.16))
		if target.kind in ["organ","scar"]: radius = maxf(17*game.preferences.hud_scale,14*game.zoom)
		var distance := screen.distance_to(screen_at(target))
		if distance < radius and distance/radius < best:
			best = distance/radius
			nearest = target
	return nearest

func _choice(title: String, description: String, action: Callable, organ_kind: String = "", symbol: String = "", affordable: bool = true, tissue_cost: float = -1.0, ap_cost: int = 0, rate_model: Dictionary = {}) -> void:
	var node = Action.new()
	node.caption = title
	node.description = description
	node.kind = organ_kind
	node.symbol = symbol
	node.affordable = affordable
	node.tissue_cost = tissue_cost
	node.ap_cost = ap_cost
	node.rate_model = rate_model
	node.pressed.connect(action)
	add_child(node)
	choices.append(node)

func open_context(target: Dictionary) -> void:
	close_context()
	context = target.duplicate()
	game.selected = -1
	game.moving_id = -1
	game.tube_start.clear()
	var sim = game.world
	var cell = sim.player
	var run = sim.evolution
	match target.kind:
		"assembly","chemistry":
			for index in ([0,1,2,3,5,10,11] if target.kind == "assembly" else [7,8,9]):
				var kind: String = sim.KINDS[index]
				var cost: float = sim.Cell.organ_cost(kind)
				_choice(game.TITLES[index],"%.0f tissue · 1 AP\n%s" % [cost,game.HELP[index]],game._select.bind(index),kind,"",cell.biomass >= cost and run.points >= 1,cost,1,{"kind":kind,"scale":1.0,"mutation":""})
			if target.kind == "chemistry":
				_choice("Food vacuoles","Inspect digestion, numeric ATP and biomass, and waste expulsion.",func():
					close_context()
					pathways.open_cell(),"","Food")
		"organ":
			var organ: Dictionary = cell.organ_by_id(target.id)
			if organ.is_empty(): close_context(); return
			if not cell.inherent(organ):
				_choice("Move","Choose a new membrane location. No resource cost.",func():
					game.moving_id = target.id
					game.placement_angle = organ.a
					close_context()
					game._message("Choose a membrane location · right-click cancels the move."),"","Move")
				_choice("Recycle","Returns half the tissue as usable biomass; half becomes waste. AP is not refunded.",func():
					sim.remove(cell.organs.find(organ))
					close_context()
					game._message("Organelle recycled · no AP refund."),"","Recycle")
			if sim.Cell.tunable_steering(organ):
				var strength: float = sim.Cell.steering_strength(organ)
				var label: String = "Off" if strength == 0 else "%d%%" % roundi(strength*100)
				var details := "Click to cycle Off / 25 / 50 / 100 / 200 / 400%. Changes signal priority and response time versus exploration; flight always wins."
				if organ.kind == "feeding": details += "\nSuction, digestion and absorption still work even with steering Off."
				elif organ.kind == "photosynthesis": details += "\nPhotosynthesis is inactive in this simplified revision."
				_choice("Steering "+label,details,func():
					var steps: Array = sim.Cell.STEERING_STEPS
					var index: int = steps.find(strength)
					sim.edit("steering",{"id":organ.id,"value":steps[(index+1)%steps.size()]})
					open_context(target),"",label)
			if not cell.inherent(organ) and organ.get("mutation","") == "":
				for gene in run.learned:
					var data: Dictionary = sim.Genes.DATA[gene]
					if data.kind != organ.kind: continue
					var cost: float = sim.Genes.price(organ)
					var ap: int = sim.Genes.adaptation_price(organ)
					var rate_model: Dictionary = organ.duplicate(true)
					rate_model.mutation = gene
					_choice(data.title,"%s\n%.0f tissue · %d AP" % [data.text,cost,ap],func():
						game._message("Specialization installed." if sim.mutate_organ(target.id,gene) else "Needs more AP or usable tissue.")
						open_context(target),organ.kind,"",cell.biomass >= cost and run.points >= ap,cost,ap,rate_model)
		"scar":
			for scar in cell.lost_organs:
				if scar.id != target.id: continue
				_choice("Restore "+game.TITLES[sim.KINDS.find(scar.kind)],"%.0f tissue · 0 AP\nRestore the lost organ in its original form." % scar.max_material,func():
					game._message("Organelle restored." if sim.edit("restore",{"id":target.id}) else "Needs usable tissue and membrane room.")
					close_context(),scar.kind,"",cell.biomass >= scar.max_material,scar.max_material,0,scar)
		"nucleus":
			if not run.sandbox and not run.chosen:
				for gene in run.offers:
					var data: Dictionary = sim.Genes.DATA[gene]
					_choice("Keep "+data.title,data.text+"\nThen select a matching membrane organ to specialize it.",func():
						run.choose(gene)
						game._message("Blueprint kept: "+data.title)
						open_context(target),data.kind)
			if not run.sandbox and run.challenge == "" and run.tide < 6 and run.clock-run.tide*run.TIDE_SECONDS < 90:
				_choice("Growth risk","+2 AP next tide: ingest and retain 18 new external tissue; finish at ≥60% health.",_challenge.bind("growth"),"","Grow")
				_choice("Stability risk","+2 AP next tide: finish with 30 steady seconds at ≥60% health and ≥25 ATP.",_challenge.bind("stability"),"","Steady")
			if not run.sandbox and run.challenge == "" and run.tide < 6 and run.clock-run.tide*run.TIDE_SECONDS < 90:
				_choice("Feeding risk","+2 AP next tide: collect 12 external food or fix 12 carbon (or a mixture); finish healthy.",_challenge.bind("metabolism"),"","Feed")
			_choice("Family & goals",sim.lineage.summary(sim),open_context.bind({"kind":"lineage"}),"","Family")
			_choice("Behavior","Tune wandering versus signals and the response cycle.",open_context.bind({"kind":"behavior"}),"","Explore")
		"behavior":
			var label: String = "Off" if cell.exploration == 0 else "%d%%" % roundi(cell.exploration*100)
			_choice("Exploration "+label,"Relative wandering weight. Signal weight / (signal + exploration) determines following time. Flight bypasses this cycle. No resource cost.",func():
				var steps: Array = sim.Cell.STEERING_STEPS
				var index: int = steps.find(cell.exploration)
				sim.edit("exploration",{"value":steps[(index+1)%steps.size()]})
				open_context(target),"",label)
			_choice("Cycle %.0fs" % cell.response_cycle,"Cycle between following a sensed goal and a seeded exploration heading. Click: 2 / 4 / 8 seconds. Memory and senses keep working throughout.",func():
				var cycles: Array = sim.Cell.RESPONSE_CYCLES
				sim.edit("cycle",{"value":cycles[(cycles.find(cell.response_cycle)+1)%cycles.size()]})
				open_context(target),"","%.0fs" % cell.response_cycle)
			_choice("Nucleus","Return to goals and blueprints.",open_context.bind({"kind":"nucleus"}),"","Back")
		"bud":
			_choice("Fund offspring","Automatic investment uses surplus tissue and ATP. This adds up to 10 of each now.",func():
				sim.edit("reserve",{"value":10})
				game._message(run.objective(sim)),"","+10")
			_choice("Reclaim reserves","Withdraw up to 10 tissue and 10 ATP.",func():
				sim.edit("reserve",{"value":-10})
				game._message(run.objective(sim)),"","−10")
			var funded: bool = cell.brood_mass >= sim.offspring_quote().material and cell.brood_energy >= 60
			_choice("Release successor","A fully funded bud releases automatically when there is room. This releases it now; you keep this body.",_reproduce.bind(false),"","Divide",funded and sim.lineage.active_family(sim).size() < sim.Lineage.MAX_ACTIVE)
			_choice("Store dormant successor","Same tissue and ATP cost. A prepaid dormant body hatches if the active family is lost.",_reproduce.bind(true),"","Cyst",funded and sim.lineage.dormant.size() < sim.Lineage.MAX_DORMANT)
			var family: Array = sim.lineage.active_family(sim)
			for relative in family:
				if relative != cell:
					_choice("Follow generation %d" % relative.generation,"Continue managing this existing family member; the current body stays alive.",_follow.bind(relative.id),"","G%d" % relative.generation)
					break
		"lineage":
			var page: int = int(target.get("page",0))
			var last: int = maxi(0,sim.lineage.records.size()-page*4)
			for record in sim.lineage.records.slice(maxi(0,last-4),last):
				var can_follow: bool = record.state == "living" and not run.terminal()
				_choice("Cell %d · %s" % [record.id,record.state],sim.lineage.biography(record)+("\nClick to follow this living relative." if can_follow else ""),_follow.bind(record.id) if can_follow else game._message.bind(sim.lineage.biography(record)),"","You" if record.state == "active" else "Zz%d" % record.generation if record.state == "dormant" else "†G%d" % record.generation if record.state == "dead" else "G%d" % record.generation)
				choices[-1].set_meta("family_id",record.id)
				choices[-1].set_meta("parent_id",record.parent)
			if not run.sandbox: _choice("Known blueprints","Recall a discovered blueprint as this tide's one draft choice; installation costs remain.",open_context.bind({"kind":"archive","page":0}),"","Genes")
			_choice("Earlier history","Cycle this family tree, then previous expeditions.",open_context.bind({"kind":"lineage","page":page+1} if last > 4 else {"kind":"past","page":0}),"","History")
		"archive":
			var known: Array = game.archive.discovered.filter(func(gene): return gene not in run.learned and sim.Genes.DATA[gene].kind != "feeding")
			var page: int = int(target.get("page",0))
			for gene in known.slice(page*3,page*3+3):
				var data: Dictionary = sim.Genes.DATA[gene]
				_choice("Recall "+data.title,data.text+"\nUses this tide's draft choice.",func():
					game._message("Blueprint recalled." if game.archive.recall(run,gene) else "Already chose this tide; recall remains available next tide.")
					open_context({"kind":"archive","page":page}),data.kind,"",not run.chosen and not run.terminal())
			if known.size() > 3: _choice("More blueprints","Next page.",open_context.bind({"kind":"archive","page":(page+1)%ceili(known.size()/3.0)}),"","More")
			_choice("Family tree","Return to your current family.",open_context.bind({"kind":"lineage"}),"","Back")
		"past":
			var page: int = int(target.get("page",0))
			var first: int = maxi(0,game.archive.expeditions.size()-(page+1)*3)
			for entry in game.archive.expeditions.slice(first,first+3):
				var description := "Expedition %d · %s · %.0fs\n" % [entry.id+1,entry.status,entry.seconds]
				for record in entry.family.slice(-4): description += "Generation %d · %s%s\n" % [record.generation,record.state," · "+record.cause if record.state == "dead" else ""]
				_choice("Expedition %d" % [entry.id+1],description,game._message.bind(description),"",str(entry.id+1))
			if first > 0: _choice("Earlier expeditions","Previous histories.",open_context.bind({"kind":"past","page":page+1}),"","Older")
			_choice("Current family","Return.",open_context.bind({"kind":"lineage"}),"","Back")
	# At most four actions plus a next-page node around any structure.
	if choices.size() > 5:
		var all_choices: Array[Button] = choices.duplicate()
		var page := posmod(int(target.get("menu_page",0)),ceili(all_choices.size()/4.0))
		choices = []
		for i in all_choices.size():
			if i >= page*4 and i < page*4+4: choices.append(all_choices[i])
			else:
				remove_child(all_choices[i])
				all_choices[i].queue_free()
		var next := target.duplicate()
		next["menu_page"] = page+1
		_choice("More","Next choices.",open_context.bind(next),"","…")
	if not choices.is_empty():
		for i in choices.size():
			choices[i].focus_neighbor_left = choices[(i-1+choices.size())%choices.size()].get_path()
			choices[i].focus_neighbor_right = choices[(i+1)%choices.size()].get_path()
			choices[i].focus_neighbor_top = choices[i].focus_neighbor_left
			choices[i].focus_neighbor_bottom = choices[i].focus_neighbor_right
	sync(0)

func _reproduce(dormant: bool) -> void:
	# Commit the parent's edits before transferring tissue into a separate body.
	game.world.commit_build()
	var success: bool = game.world.divide_lineage(dormant,false)
	game.world.begin_build()
	close_context()
	game._message(("Dormant successor secured." if dormant else "Successor released. The family menu lets you follow it.") if success else "Needs full tissue/ATP reserves, feeding anatomy and room for another family member.")

func _follow(identity: int) -> void:
	game.world.commit_build()
	if game.world.follow_family(identity):
		game.camera_locked = true
		game.camera_offset = Vector2.ZERO
		game.free_camera = game.world.player.position
		game._message(game.world.lineage.notices[-1])
	if game.build_open: game.world.begin_build()
	close_context()
	game._update_world(1)

func _challenge(kind: String) -> void:
	game._message("Challenge accepted: "+kind if game.world.evolution.accept_challenge(kind,game.world.player) else "This tide's challenge window has closed.")
	open_context({"kind":"nucleus"})

func describe(target: Dictionary) -> String:
	var cell = game.world.player
	var sim = game.world
	var run = sim.evolution
	match target.kind:
		"assembly": return "Assembly factory\nCilia, flagella, armor, chemical glands, repair and receptors."
		"chemistry": return "Chemistry factory\nPhotosynthesis, toxins, neutralizers and acid."
		"atp":
			var rates: Dictionary = cell.energy_budget.rates(cell.age)
			var breakdown := ""
			for category in ["upkeep","movement","pumping","secretion","repair","combat","acid stress","receptor cleaning"]:
				var rate: float = rates.categories.get(category,0.0)
				if rate > 0.005: breakdown += "\n%s −%.2f/s" % [category.capitalize(),rate]
			return "ATP · +%.2f/s −%.2f/s\nStored %.1f · turnover %.2f/s\n%s" % [rates.production,rates.spent,cell.energy,cell.atp_decay_rate(),breakdown]
		"nucleus": return "%s\n%s\n%s" % [run.objective(sim),run.forecast(),"Blueprint ready · click to choose." if not run.chosen else "%d blueprints kept." % run.learned.size()]
		"lineage": return "FAMILY TREE\n"+sim.lineage.summary(sim)+"\n"+run.forecast()
		"archive": return "Known blueprints · %d\nOne draft choice per tide; recalling grants no free anatomy." % game.archive.discovered.size()
		"past": return "Expedition history · %d recorded\nYour next expedition retains these discoveries, not extra stats." % game.archive.expeditions.size()
		"bud": return "Offspring reserve\n%.0f / %.0f tissue · %.0f / 60 ATP\n%d living family · %d dormant\nSurplus is invested automatically; a funded bud releases when there is room.\nDescendant viability: %.0f / 60 s" % [cell.brood_mass,sim.offspring_quote().material,cell.brood_energy,sim.lineage.active_family(sim).size(),sim.lineage.dormant.size(),run.viable_seconds]
		"organ":
			var organ: Dictionary = cell.organ_by_id(target.id)
			if organ.is_empty(): return ""
			var result: String = game.TITLES[sim.KINDS.find(organ.kind)]+"\nHealth %d%%" % roundi(100*organ.hp/organ.max_hp)
			if sim.Cell.tunable_steering(organ):
				var strength: float = sim.Cell.steering_strength(organ)
				result += "\nSteering "+("Off" if strength == 0 else "%d%%" % roundi(strength*100))
				result += "\nFollow %.0f%% / explore %.0f%% · %.0fs cycle" % [cell.response_share(organ)*100,(1-cell.response_share(organ))*100,cell.response_cycle]
			var rates: Dictionary = cell.energy_budget.rates(cell.age)
			var upkeep: float = sim.Cell.organ_upkeep(organ)
			var whole: float = cell.operating_budget().steady
			var recent: float = rates.organs.get(organ.id,0.0)
			result += "\nSteady ATP %.2f/s · %.0f%% of cell estimate\nRecent actual %.2f/s · %.0f%% of spending\nCell production surplus %+.2f ATP/s" % [upkeep,100*upkeep/maxf(0.000001,whole),recent,100*recent/maxf(0.000001,rates.spent),rates.net]
			if organ.blocked > 0.05: result += "\nReceptors blocked · cleaning in progress."
			if organ.get("mutation","") != "": result += "\n"+sim.Genes.DATA[organ.mutation].title
			return result+"\n"+game.HELP[sim.KINDS.find(organ.kind)]
		"body": return "Membrane · health %d%%\nAcid stress %d%% · local light %d%%\nPunctures lose tissue; repair needs biomass and ATP." % [roundi(cell.health),roundi(cell.acid_stress*100),roundi(sim.light_at(cell.position)*100)]
		"scar": return "Lost organelle\nClick to restore using tissue."
	return ""

func _tooltip(value: String, at: Vector2) -> void:
	tip_box.visible = value != ""
	if value == "": return
	if not Input.is_key_pressed(KEY_ALT): value = value.split("\n")[0]
	var s: float = game.preferences.hud_scale
	tip.custom_minimum_size.x = minf(320*s,get_viewport_rect().size.x-48)
	tip.add_theme_font_size_override("font_size",roundi(16*s))
	if tip.text != value:
		tip.text = value
		tip_box.reset_size()
	var extent := tip_box.get_combined_minimum_size()
	tip_box.size = extent # Shrink after text reflow; stale tall panels otherwise clip at large UI scales.
	tip_box.position = (at+Vector2(18,18)).clamp(Vector2(12,12),get_viewport_rect().size-extent-Vector2(12,12))
	var budget_area: Rect2 = biomass_view.comparison_bounds()
	if game.build_open and Rect2(tip_box.position,extent).intersects(budget_area):
		var left: float = budget_area.position.x-extent.x-18*s
		if left >= 12: tip_box.position.x = left
		elif budget_area.end.y+extent.y+18*s <= get_viewport_rect().size.y:
			tip_box.position.y = budget_area.end.y+18*s

func _events() -> void:
	var run = game.world.evolution
	if run.tide != last_tide:
		last_tide = run.tide
		game._message("%s\n%s\n%s" % [run.TIDES[run.tide].title,run.TIDES[run.tide].forecast,run.challenge_result])
	if run.resistance != last_resistance:
		last_resistance = run.resistance
		game._message("The habitat is adapting to your recent strategy.\nInspect the nucleus for the emerging response.")
	var family = game.world.lineage
	if family.serial != last_lineage:
		last_lineage = family.serial
		game._message(family.notices[-1])
	var goal: String = run.goal_key(game.world)
	if goal != last_goal:
		last_goal = goal
		if family.notices.is_empty() or game.notice_timer < 3: game._message(run.objective(game.world))
	if run.terminal() and run.ending != last_ending:
		last_ending = run.ending
		game._message(run.ending+"\nEsc → Family history · R starts the next expedition.")
	if run.terminal(): return
	var critical: bool = game.world.player.health < 30 or game.world.player.energy < 10
	if critical and not last_critical: game._message("Critical resources · inspect the ATP sac and damaged membrane.")
	last_critical = critical

func sync(_dt: float) -> void:
	if game == null: return
	_events()
	biomass_view.sync()
	var active: bool = not game.settings_panel.visible
	visible = active
	if not active: return
	var s: float = game.preferences.hud_scale
	var size := get_viewport_rect().size
	var cell_screen: Vector2 = game.world_layer.to_global(interior.position)
	message.visible = (game.notice_timer > 3) or game.world.evolution.terminal()
	message.text = game.notice if Input.is_key_pressed(KEY_ALT) else game.notice.split("\n")[0]
	message.custom_minimum_size.x = minf(500*s,size.x-48)
	message.size.x = message.custom_minimum_size.x
	message.add_theme_font_size_override("font_size",roundi(16*s))
	message.position = (cell_screen+Vector2(-message.size.x*0.5,game.world.player.radius*game.zoom+35)).clamp(Vector2(16,16),size-message.size-Vector2(16,16))
	edit_hint.visible = game.build_open
	edit_hint.text = "Tab · return to habitat" if game.selected < 0 and game.moving_id < 0 else "Place on membrane · right-click cancels"
	edit_hint.add_theme_font_size_override("font_size",roundi(14*s))
	edit_hint.size = Vector2(minf(540*s,size.x-32),0)
	edit_hint.position = Vector2((size.x-edit_hint.size.x)*0.5,14)
	if not game.build_open and not context.is_empty() and context.kind not in ["lineage","archive","past"]: close_context()
	if context.get("kind","") == "bud" and choices.size() >= 4:
		var sim = game.world
		var funded: bool = sim.player.brood_mass+0.000001 >= sim.offspring_quote().material and sim.player.brood_energy >= 60
		choices[2].affordable = funded and sim.lineage.active_family(sim).size() < sim.Lineage.MAX_ACTIVE
		choices[3].affordable = funded and sim.lineage.dormant.size() < sim.Lineage.MAX_DORMANT
	if not context.is_empty():
		var anchor := screen_at(context)
		menu_radius = 106*s if choices.size() > 3 else 88*s
		var margin := Vector2.ONE*(menu_radius+38*s+12)
		menu_center = anchor.clamp(margin,size-margin)
		for i in choices.size():
			var choice = choices[i]
			choice.text_scale = s
			choice.size = Vector2.ONE*68*s
			var a := -PI/2+TAU*i/maxi(1,choices.size())
			choice.position = menu_center+Vector2.from_angle(a)*menu_radius-choice.size*0.5
			choice.queue_redraw()
	var cursor := get_global_mouse_position()
	hovered = hit(cursor)
	if hovered.is_empty():
		var relative: Vector2 = game._player_relative(cursor).rotated(-game.world.player.angle)
		if relative.length() < game.world.player.visible_support(relative.angle()): hovered = {"kind":"body"}

	var inspected_choice = null
	for choice in choices:
		if choice.get_global_rect().has_point(cursor):
			inspected_choice = choice
			break
	if inspected_choice == null:
		for choice in choices:
			if choice.has_focus():
				inspected_choice = choice
				break
	hovered_price.clear()
	if inspected_choice != null:
		_tooltip(inspected_choice.caption+"\n"+inspected_choice.description,inspected_choice.position+Vector2(inspected_choice.size.x,0))
		if not inspected_choice.rate_model.is_empty():
			var model: Dictionary = inspected_choice.rate_model
			var future: float = game.Simulation.Cell.organ_upkeep(model)
			var existing: Dictionary = game.world.player.organ_by_id(model.get("id",-1))
			var current: float = game.Simulation.Cell.organ_upkeep(existing) if not existing.is_empty() else 0.0
			_tooltip(inspected_choice.caption+"\n"+inspected_choice.description+"\nSteady ATP %.2f/s · change %+.2f/s\nSteady estimate; pursuit/repair/combat extra." % [future,future-current],inspected_choice.position+Vector2(inspected_choice.size.x,0))
		if inspected_choice.tissue_cost >= 0:
			hovered_price = {"tissue":inspected_choice.tissue_cost,"ap":inspected_choice.ap_cost,"rate_model":inspected_choice.rate_model}
	else:
		if not context.is_empty() and choices.is_empty(): _tooltip(describe(context),screen_at(context))
		elif not hovered.is_empty() and (game.build_open or Input.is_key_pressed(KEY_ALT)) and (hovered.kind != "body" or Input.is_key_pressed(KEY_ALT)) and game.selected < 0 and game.moving_id < 0: _tooltip(describe(hovered),screen_at(hovered))
		elif not keyboard_target.is_empty() and game.selected < 0: _tooltip(describe(keyboard_target),screen_at(keyboard_target))
		elif game.selected >= 0:
			var cost: float = game.Simulation.Cell.organ_cost(game.Simulation.KINDS[game.selected])
			_tooltip("%s\n%.0f tissue · 1 AP\n%s" % [game.TITLES[game.selected],cost,game.placement_status()],cursor)
		else:
			tip_box.hide()
	biomass_view.sync()
	queue_redraw()

func cycle_target(direction: int) -> void:
	close_context()
	var list := targets()
	keyboard_index = posmod(keyboard_index+direction,list.size())
	keyboard_target = list[keyboard_index]
	game.selected = -1
	game.moving_id = -1

func activate_keyboard() -> bool:
	for choice in choices:
		if choice.has_focus(): choice.pressed.emit(); return true
	if not keyboard_target.is_empty():
		open_context(keyboard_target)
		if not choices.is_empty(): choices[0].grab_focus()
		return true
	return false

func _draw() -> void:
	if game == null or game.settings_panel.visible: return
	if not context.is_empty():
		draw_line(screen_at(context),menu_center,Color(0.5,0.91,0.85,0.35),1.5,true)
		for choice in choices:
			var origin := menu_center
			if context.kind == "lineage" and choice.has_meta("parent_id"):
				for parent in choices:
					if parent.get_meta("family_id",-2) == choice.get_meta("parent_id",-1): origin = parent.position+parent.size*0.5
			draw_line(origin,choice.position+choice.size*0.5,Color(0.5,0.91,0.85,0.50),2,true)
	if game.build_open and not hovered.is_empty() and hovered.kind != "body" and game.selected < 0:
		draw_arc(screen_at(hovered),24*game.preferences.hud_scale,0,TAU,32,Color(0.67,1,0.89,0.8),1.5,true)
	if game.build_open and not keyboard_target.is_empty():
		draw_arc(screen_at(keyboard_target),24*game.preferences.hud_scale,0,TAU,32,Color("fff0a1"),2,true)
