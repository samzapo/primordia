extends Control
## Cell-local entry points replace the HUD and assembly/modify panes.
const Interior = preload("res://scripts/cell_interior.gd")
const Action = preload("res://scripts/cell_action.gd")
var game
var interior := Interior.new()
var choices: Array[Button] = []
var context: Dictionary = {}
var hovered: Dictionary = {}
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

func initialize(owner_game) -> void:
	game = owner_game
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interior.game = game
	interior.z_index = 3
	game.world_layer.add_child(interior)
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
	close_context()
	keyboard_index = -1
	keyboard_target.clear()
	last_tide = game.world.evolution.tide
	last_resistance = ""
	last_ending = ""
	last_critical = false
	interior.previous_coins = -1
	interior.coin_transfers.clear()

func close_context() -> void:
	context.clear()
	for choice in choices:
		remove_child(choice)
		choice.queue_free()
	choices.clear()
	tip_box.hide()
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
			p += p.normalized()*5*record.scale
	else: p = interior.anchors.get(target.kind,Vector2.ZERO)
	return game.world_layer.to_global(interior.position+p.rotated(interior.rotation))

func targets() -> Array:
	var result: Array = []
	for kind in ["assembly","chemistry","nucleus","bud","atp","coins"]: result.append({"kind":kind})
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

func _choice(title: String, description: String, action: Callable, organ_kind: String = "", symbol: String = "", affordable: bool = true) -> void:
	var node = Action.new()
	node.caption = title
	node.description = description
	node.kind = organ_kind
	node.symbol = symbol
	node.affordable = affordable
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
			for index in (range(6) if target.kind == "assembly" else range(6,10)):
				var kind: String = sim.KINDS[index]
				var cost: float = sim.Cell.organ_cost(kind)
				_choice(game.TITLES[index],"%.0f tissue · 1 AP\n%s" % [cost,game.HELP[index]],game._select.bind(index),kind,"",cell.biomass >= cost and run.points >= 1)
		"organ":
			var organ: Dictionary = cell.organ_by_id(target.id)
			if organ.is_empty(): close_context(); return
			_choice("Move","Choose a new membrane location. No resource cost.",func():
				game.moving_id = target.id
				game.placement_angle = organ.a
				close_context()
				game._message("Choose a membrane location · right-click cancels the move."),"","Move")
			_choice("Recycle","Returns half the tissue as usable biomass; half becomes waste. AP is not refunded.",func():
				sim.remove(cell.organs.find(organ))
				close_context()
				game._message("Organelle recycled · no AP refund."),"","Recycle")
			if organ.get("mutation","") == "":
				for gene in run.learned:
					var data: Dictionary = sim.Genes.DATA[gene]
					if data.kind != organ.kind: continue
					var cost: float = sim.Genes.price(organ)
					var ap: int = sim.Genes.adaptation_price(organ)
					_choice(data.title,"%s\n%.0f tissue · %d AP" % [data.text,cost,ap],func():
						game._message("Specialization installed." if sim.mutate_organ(target.id,gene) else "Needs more AP or usable tissue.")
						open_context(target),organ.kind,"",cell.biomass >= cost and run.points >= ap)
		"scar":
			for scar in cell.lost_organs:
				if scar.id != target.id: continue
				_choice("Restore "+game.TITLES[sim.KINDS.find(scar.kind)],"%.0f tissue · 0 AP\nRestore the lost organ in its original form." % scar.max_material,func():
					game._message("Organelle restored." if cell.restore_organ(target.id) else "Needs usable tissue and membrane room.")
					close_context(),scar.kind,"",cell.biomass >= scar.max_material)
		"nucleus":
			if not run.chosen:
				for gene in run.offers:
					var data: Dictionary = sim.Genes.DATA[gene]
					_choice("Keep "+data.title,data.text+"\nThen select a matching membrane organ to specialize it.",func():
						run.choose(gene)
						game._message("Blueprint kept: "+data.title)
						open_context(target),data.kind)
			if run.challenge == "" and run.tide < 6 and run.clock-run.tide*run.TIDE_SECONDS < 90:
				_choice("Growth risk","+1 AP next tide: ingest and retain 18 new external tissue; finish at ≥60% health.",_challenge.bind("growth"),"","Grow")
				_choice("Stability risk","+1 AP next tide: finish with 30 steady seconds at ≥60% health and ≥25 ATP.",_challenge.bind("stability"),"","Steady")
		"bud":
			if run.offspring_id < 0:
				_choice("Fund offspring","Transfer up to 10 usable tissue and 10 ATP to the offspring reserve.",func():
					cell.reserve(10,sim.offspring_quote().material)
					game._message("Reproductive reserves funded."),"","+10")
				_choice("Reclaim reserves","Withdraw up to 10 tissue and 10 ATP from the offspring reserve.",func():
					cell.reserve(-10)
					game._message("Reproductive reserves reclaimed."),"","−10")
	if not choices.is_empty():
		for i in choices.size():
			choices[i].focus_neighbor_left = choices[(i-1+choices.size())%choices.size()].get_path()
			choices[i].focus_neighbor_right = choices[(i+1)%choices.size()].get_path()
			choices[i].focus_neighbor_top = choices[i].focus_neighbor_left
			choices[i].focus_neighbor_bottom = choices[i].focus_neighbor_right
	sync(0)

func _challenge(kind: String) -> void:
	game._message("Challenge accepted: "+kind if game.world.evolution.accept_challenge(kind,game.world.player) else "This tide's challenge window has closed.")
	open_context({"kind":"nucleus"})

func describe(target: Dictionary) -> String:
	var cell = game.world.player
	var sim = game.world
	var run = sim.evolution
	match target.kind:
		"assembly": return "Assembly factory\nFlagella, armor, spikes, repair, feeding and flight."
		"chemistry": return "Chemistry factory\nPhotosynthesis, toxins, neutralizers and acid."
		"atp": return "ATP %.0f / %.0f\nStored food %.1f · oxygen %.1f\nActive upkeep ≈ %.2f ATP/s before repairs and combat." % [cell.energy,cell.energy_capacity(),cell.substrate,cell.oxygen,cell.operating_budget().steady]
		"coins": return "%d AP\nEach coin funds one point of adaptation." % run.points
		"nucleus": return "Nucleus · Tide %d / 6 · %d:%02d\n%s\n%s" % [mini(6,run.tide+1),int(sim.time)/60,int(sim.time)%60,run.forecast(),"Blueprint ready · click to choose." if not run.chosen else "%d blueprints kept · specialize matching organs." % run.learned.size()]
		"bud":
			if run.offspring_id >= 0: return "Offspring viability\n%.0f / 60 healthy, active seconds\nKeep feeding through 13:30." % run.viable_seconds
			return "Offspring reserve\n%.0f / %.0f tissue · %.0f / 60 ATP\nDivide at 12:00; sustain the offspring through 13:30." % [cell.brood_mass,sim.offspring_quote().material,cell.brood_energy]
		"organ":
			var organ: Dictionary = cell.organ_by_id(target.id)
			if organ.is_empty(): return ""
			var result: String = game.TITLES[sim.KINDS.find(organ.kind)]+"\nHealth %d%%" % roundi(100*organ.hp/organ.max_hp)
			if organ.blocked > 0.05: result += "\nReceptors blocked · cleaning in progress."
			if organ.get("mutation","") != "": result += "\n"+sim.Genes.DATA[organ.mutation].title
			return result+"\n"+game.HELP[sim.KINDS.find(organ.kind)]
		"body": return "Membrane · health %d%%\nAcid stress %d%% · local light %d%%\nPunctures lose tissue; repair needs biomass and ATP." % [roundi(cell.health),roundi(cell.acid_stress*100),roundi(sim.light_at(cell.position)*100)]
		"scar": return "Lost organelle\nClick to restore using tissue."
	return ""

func _tooltip(value: String, at: Vector2) -> void:
	tip_box.visible = value != ""
	if value == "": return
	var s: float = game.preferences.hud_scale
	tip.custom_minimum_size.x = minf(320*s,get_viewport_rect().size.x-48)
	tip.add_theme_font_size_override("font_size",roundi(16*s))
	if tip.text != value:
		tip.text = value
		tip_box.reset_size()
	var extent := tip_box.get_combined_minimum_size()
	tip_box.position = (at+Vector2(18,18)).clamp(Vector2(12,12),get_viewport_rect().size-extent-Vector2(12,12))

func _events() -> void:
	var run = game.world.evolution
	if run.tide != last_tide:
		last_tide = run.tide
		game._message("Tide %d · %s\n%s" % [mini(6,run.tide+1),run.TIDES[run.tide].title,run.forecast()])
	if run.resistance != last_resistance:
		last_resistance = run.resistance
		game._message(run.forecast())
	if run.terminal() and run.ending != last_ending:
		last_ending = run.ending
		game._message(run.ending+"\nR starts a new life.")
	var critical: bool = game.world.player.health < 30 or game.world.player.energy < 10
	if critical and not last_critical: game._message("Critical resources · inspect the ATP sac and damaged membrane.")
	last_critical = critical

func sync(_dt: float) -> void:
	if game == null: return
	_events()
	var active: bool = not game.settings_panel.visible
	visible = active
	if not active: return
	var s: float = game.preferences.hud_scale
	var size := get_viewport_rect().size
	var cell_screen: Vector2 = game.camera_screen+interior.position*game.zoom
	message.visible = game.notice_timer > 0 or game.world.evolution.terminal()
	message.text = game.notice
	message.custom_minimum_size.x = minf(500*s,size.x-48)
	message.size.x = message.custom_minimum_size.x
	message.add_theme_font_size_override("font_size",roundi(16*s))
	message.position = (cell_screen+Vector2(-message.size.x*0.5,game.world.player.radius*game.zoom+35)).clamp(Vector2(16,16),size-message.size-Vector2(16,16))
	edit_hint.visible = game.build_open
	edit_hint.text = "Paused · Tab / Enter to resume · click a factory" if game.selected < 0 and game.moving_id < 0 else "Place on membrane · right-click to cancel · wheel zooms"
	edit_hint.add_theme_font_size_override("font_size",roundi(14*s))
	edit_hint.size = Vector2(minf(540*s,size.x-32),0)
	edit_hint.position = Vector2((size.x-edit_hint.size.x)*0.5,14)
	if not game.build_open and not context.is_empty(): close_context()
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

	var choice_tip := false
	for choice in choices:
		if choice.get_global_rect().has_point(cursor) or choice.has_focus():
			_tooltip(choice.caption+"\n"+choice.description,choice.position+Vector2(choice.size.x,0))
			choice_tip = true
			break
	if not choice_tip:
		if not context.is_empty() and choices.is_empty(): _tooltip(describe(context),screen_at(context))
		elif not hovered.is_empty() and game.selected < 0 and game.moving_id < 0: _tooltip(describe(hovered),screen_at(hovered))
		elif not keyboard_target.is_empty() and game.selected < 0: _tooltip(describe(keyboard_target),screen_at(keyboard_target))
		elif game.selected >= 0:
			var cost: float = game.Simulation.Cell.organ_cost(game.Simulation.KINDS[game.selected])
			_tooltip("%s · %.0f tissue · 1 AP\n%s" % [game.TITLES[game.selected],cost,game.placement_status()],cursor)
		else:
			tip_box.hide()
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
		for choice in choices: draw_line(menu_center,choice.position+choice.size*0.5,Color(0.5,0.91,0.85,0.28),1.5,true)
	if game.build_open and not hovered.is_empty() and hovered.kind != "body" and game.selected < 0:
		draw_arc(screen_at(hovered),24*game.preferences.hud_scale,0,TAU,32,Color(0.67,1,0.89,0.8),1.5,true)
	if game.build_open and not keyboard_target.is_empty():
		draw_arc(screen_at(keyboard_target),24*game.preferences.hud_scale,0,TAU,32,Color("fff0a1"),2,true)
