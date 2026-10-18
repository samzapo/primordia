extends Control
## Cell-local entry points replace the HUD and assembly/modify panes.
var pathways := preload("res://scripts/chemistry_editor.gd").new()
const Interior = preload("res://scripts/cell_interior.gd")
const Action = preload("res://scripts/cell_action.gd")
const Biomass = preload("res://scripts/biomass_preview.gd")
var game
var family_picker:=preload("res://scripts/family_picker.gd").new()
var investment_picker:=preload("res://scripts/investment_picker.gd").new()
var mobile_menu_height:=0.0
var mobile_tray:=PanelContainer.new()
var mobile_scroll:=ScrollContainer.new()
var mobile_flow:=HFlowContainer.new()
var mobile_close:=Button.new()
var mobile_resources:=PanelContainer.new()
var mobile_stocks:=Label.new()
var mobile_hide:=Button.new()
var resources_hidden:=false
var cancel_icon=Action.new()
const COMIC=preload("res://assets/fonts/ComicNeue-Regular.ttf")
func mobile() -> bool:return game!=null and game.touch_zoom.enabled
func ui_scale() -> float:return game.preferences.hud_scale*(game.touch_zoom.pixels if mobile() else 1.0)
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
var pending_mutation: Dictionary={}

func initialize(owner_game) -> void:
	game = owner_game
	game.ui.add_child(family_picker);family_picker.initialize(self)
	add_child(investment_picker);investment_picker.initialize(game)
	mobile_tray.z_index=90;add_child(mobile_tray)
	var tray_row:=HBoxContainer.new();mobile_tray.add_child(tray_row)
	tray_row.add_child(mobile_scroll);mobile_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	mobile_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	mobile_scroll.add_child(mobile_flow);mobile_flow.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tray_row.add_child(mobile_close);mobile_close.text="×";mobile_close.pressed.connect(close_context)
	mobile_resources.z_index=90;add_child(mobile_resources)
	var stock_row:=HBoxContainer.new();mobile_resources.add_child(stock_row)
	stock_row.add_child(mobile_stocks);mobile_stocks.add_theme_font_override("font",COMIC);mobile_stocks.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	stock_row.add_child(mobile_hide);mobile_hide.pressed.connect(func():resources_hidden=not resources_hidden)
	cancel_icon.z_index=90;cancel_icon.caption="Cancel placement";cancel_icon.description="Tap to cancel";add_child(cancel_icon)
	cancel_icon.pressed.connect(func():
		if game.merge_selecting():game._end_merge_selection()
		else:game._cancel_placement())
	message.z_index=100
	message.add_theme_font_override("font",COMIC)
	add_child(pathways)
	pathways.initialize(game)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interior.game = game
	interior.z_index = 8
	game.world_layer.add_child(interior)
	biomass_view.game = game
	add_child(biomass_view)
	add_child(tip_box)
	tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_box.add_child(tip)
	tip.add_theme_font_override("font",COMIC)
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
	investment_picker.hide()
	family_picker.hide()
	context.clear()
	mobile_tray.hide();mobile_menu_height=0.0
	if mobile():game.touch_zoom.layout()
	hovered_price.clear()
	for choice in choices:
		choice.get_parent().remove_child(choice)
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
			if target.kind == "organ" and cell.inherent(record):
				p = preload("res://scripts/visuals.gd").oral_path(cell,record.a)[12]
			else:
				p = cell.organ_local_position(record)
	else: p = interior.anchors.get("nucleus" if target.kind in ["lineage","archive","past","investment"] else "bud" if target.kind=="division" else target.kind,Vector2.ZERO)
	return game.world_layer.to_global(interior.position+p.rotated(interior.rotation))

func targets() -> Array:
	var result: Array = []
	for kind in ["assembly","chemistry","receptors","nucleus","bud","atp"]: result.append({"kind":kind})
	for organ in game.world.player.organs: result.append({"kind":"organ","id":organ.id})
	for scar in game.world.player.lost_organs: result.append({"kind":"scar","id":scar.id})
	return result

func _hit_candidates(screen: Vector2) -> Array:
	if interior.anchors.is_empty() or not interior.visible: return []
	var found: Array = []
	for target in targets():
		var radius := maxf(18*game.preferences.hud_scale,interior.anchors.radius*game.zoom*(0.28 if target.kind == "nucleus" else 0.16))
		if target.kind=="chemistry":radius=maxf(20*ui_scale(),interior.anchors.radius*game.zoom*.24)
		if target.kind in ["organ","scar"]: radius = maxf(17*game.preferences.hud_scale,14*game.zoom)
		var distance := screen.distance_to(screen_at(target))
		if distance < radius: found.append({"target":target,"score":distance/radius})
	found.sort_custom(func(a,b):return a.score < b.score)
	return found

func hit(screen: Vector2) -> Dictionary:
	var found := _hit_candidates(screen)
	return {} if found.is_empty() else found[0].target

func pick(screen: Vector2) -> Dictionary:
	var found := _hit_candidates(screen)
	if found.is_empty(): return {}
	if found.size() == 1: return found[0].target
	# Every overlapping control remains reachable, including ones behind art.
	return {"kind":"overlap","targets":found.map(func(item):return item.target)}

func target_title(target: Dictionary) -> String:
	if target.kind == "organ":
		var organ: Dictionary = game.world.player.organ_by_id(target.id)
		return game.TITLES[game.Simulation.KINDS.find(organ.kind)] if not organ.is_empty() else "Organelle"
	return {"assembly":"Assembly factory","chemistry":"Chemistry factory","receptors":"Receptor factory","nucleus":"Nucleus","bud":"Division","atp":"ATP","scar":"Restore organelle"}.get(target.kind,"Cell")

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
	if context.get("kind","") in ["lineage","merge_family"]:family_picker.grid.add_child(node)
	elif mobile():mobile_flow.add_child(node)
	else:add_child(node)
	choices.append(node)

func open_context(target: Dictionary) -> void:
	if target.get("kind","")=="merge_family":game._begin_merge_selection();return
	close_context()
	context = target.duplicate()
	game.selected = -1
	game.moving_id = -1
	game.tube_start.clear()
	var sim = game.world
	var cell = sim.player
	var run = sim.evolution
	match target.kind:
		"overlap":
			for entry in target.targets:
				var kind: String={"assembly":"assembly_factory","chemistry":"internal_factory","receptors":"receptor_factory","nucleus":"cell_nucleus","atp":"atp_store","bud":"offspring_store"}.get(entry.kind,"")
				if entry.kind == "organ":
					var organ: Dictionary = cell.organ_by_id(entry.id)
					if organ.is_empty(): continue
					kind = organ.kind
				if entry.kind=="scar":
					for scar in cell.lost_organs:
						if scar.id==entry.id:kind=scar.kind;break
				var symbol: String = {"assembly":"Build","chemistry":"Chem","nucleus":"Genes","bud":"Bud","atp":"ATP","scar":"Restore"}.get(entry.kind,"")
				_choice(target_title(entry),describe(entry),open_context.bind(entry),kind,symbol)
				choices[-1].scar=entry.kind=="scar"
				if entry.kind=="nucleus" and game.views.has(cell.id):choices[-1].structure_art=game.views[cell.id].art
		"assembly","chemistry","receptors":
			for index in ([0,1,2,3,11,13] if target.kind == "assembly" else [5,10,15,16] if target.kind=="receptors" else [12,14,6,7,9,3,8]):
				var kind: String = sim.KINDS[index]
				var cost := 0.0
				var price: int=cell.construction_price(kind)
				_choice(game.TITLES[index],"%d AP\n%s" % [price,game.HELP[index]],game._select.bind(index),kind,"",cell.ap >= price,cost,price,{"kind":kind,"scale":1.0,"mutation":""})
			if target.kind == "chemistry":
				_choice("Food vacuoles","Inspect oxygen-dependent digestion, fermentation, photosynthesis and waste expulsion.",func():
					close_context()
					pathways.open_cell(),"","Food")
		"organ":
			var organ: Dictionary = cell.organ_by_id(target.id)
			if organ.is_empty(): close_context(); return
			if not cell.inherent(organ):
				_choice("Reabsorb","Returns half the tissue and %d AP. Four non-receptor organelles return 3 AP; three return 2. Lowers the next build price." % cell.construction_refund(organ),func():
					# Snapshots replace organ dictionaries while this menu stays open.
					# Resolve the stable ID at click time; never compare an old snapshot.
					var current=sim.player
					var live: Dictionary=current.organ_by_id(target.id) if current.id==cell.id else {}
					var refund: int=current.construction_refund(live)
					var ok: bool=not live.is_empty() and sim.edit("remove",{"id":target.id})
					close_context()
					if not ok:game._message("This organelle is no longer available.")
					elif not sim.remote_client:game._message("Organelle reabsorbed · %d AP returned to this cell." % refund),"","Reabsorb")
			if organ.kind in ["toxin","poreforming"] and cell.count("hunting")==0:
				_choice("Hunting receptor","Detect nearby prey through their chemical signals. Build this to guide the gland.",game._select.bind(10),"hunting","",cell.ap>=cell.construction_price("hunting"),0,cell.construction_price("hunting"))
			if not cell.inherent(organ):
				for gene in sim.Genes.available(organ,run.learned):
					var data: Dictionary = sim.Genes.DATA[gene]
					var cost: float = sim.Genes.price(organ)
					var ap: int = sim.Genes.adaptation_price(organ)
					var rate_model: Dictionary = organ.duplicate(true)
					rate_model.mutation = gene
					_choice(data.title,data.text+"\nFree mutation.",_specialize.bind(cell.id,target.id,gene),"" if gene in sim.Genes.LIGHT_ADAPTATIONS else organ.kind,("Sun" if gene == "sun_leaf" else "Shade") if gene in sim.Genes.LIGHT_ADAPTATIONS else "",cell.biomass >= cost and cell.ap >= ap,cost,ap,rate_model)
					if pending_mutation.get("cell",-1)==cell.id and pending_mutation.get("id",-1)==organ.id:
						choices[-1].disabled=true
						if pending_mutation.gene==gene:choices[-1].caption+=" (applying)"
					if organ.get("mutation","") == gene:
						choices[-1].caption += " (active)"
						choices[-1].selected = true
						choices[-1].tint = Color("ffe6a1")
						choices[-1].disabled = true
		"scar":
			for scar in cell.lost_organs:
				if scar.id != target.id: continue
				_choice("Restore "+game.TITLES[sim.KINDS.find(scar.kind)],"%d AP\nRestore the lost organ in its original form." % cell.construction_price(scar.kind),func():
					game._message("Organelle restored." if sim.edit("restore",{"id":target.id}) else "Needs %d AP and membrane room." % cell.construction_price(scar.kind))
					close_context(),scar.kind,"",cell.ap >= cell.construction_price(scar.kind),0,cell.construction_price(scar.kind),scar)
		"nucleus":
			for gene in run.division_offers:
				var data: Dictionary=sim.Genes.DATA[gene]
				_choice("Keep "+data.title,data.text+"\nFree division mutation.",func():
					sim.edit("choose_mutation",{"gene":gene})
					game._message("Mutation selected.")
					close_context(),data.kind)
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
			_choice("Family",sim.lineage.summary(sim),open_context.bind({"kind":"lineage"}),"","Family")
			if not run.sandbox: _choice("Known blueprints","Recall a discovered blueprint.",open_context.bind({"kind":"archive","page":0}),"","Genes")
			_choice("Investment","Choose automatic AP spending for unattended cells.",open_context.bind({"kind":"investment"}),"","Invest")
			_choice("Instinct","Show or hide this cell’s current intention and direction.",_toggle_instinct,"","Instinct")
			choices[-1].set_meta("instinct_toggle",true);choices[-1].selected=game.preferences.show_instinct
		"investment":
			investment_picker.open()
		"bud":
			var readiness: Dictionary=sim.division_status()
			_choice("Divide",readiness.reason,open_context.bind({"kind":"division"}),"","Divide")
			choices[-1].set_meta("division_entry",true)
			_choice("Investment","Choose Hunter, Producer or Grazer for unattended cells.",open_context.bind({"kind":"investment"}),"","Invest")
			_choice("Family",sim.lineage.summary(sim),open_context.bind({"kind":"lineage"}),"","Family")
		"division":
			_choice("Auto divide","Keep dividing this cell when resources and clear water are ready.",_toggle_auto_division,"","Auto divide")
			choices[-1].set_meta("division_auto",true)
			_choice("Start division now","Divide once now, or queue one division until ready.",_reproduce,"","Start now")
			choices[-1].set_meta("division_once",true)
			_choice("Back","Return to this cell.",open_context.bind({"kind":"bud"}),"","Back")
		"lineage","merge_family":
			context["roster"]=hash(sim.lineage.records)
			var records: Array=sim.lineage.records.filter(func(record):return record.state in ["living","active"])
			family_picker.layout_key=[]
			for record in records:
				var can_follow: bool=record.state=="living" and not run.terminal()
				_choice("Cell %d · %s" % [record.id,record.state],sim.lineage.biography(record),_merge.bind(record.id) if target.kind=="merge_family" else _follow.bind(record.id) if can_follow else game._message.bind(sim.lineage.biography(record)),"","%d" % record.generation)
				choices[-1].selected=record.state=="active"
				choices[-1].set_meta("family_id",record.id)
				choices[-1].set_meta("parent_id",record.parent)
		"archive":
			var known: Array = game.archive.discovered.filter(func(gene): return gene not in run.learned and sim.Genes.DATA[gene].kind != "feeding")
			var page: int = int(target.get("page",0))
			for gene in known.slice(page*3,page*3+3):
				var data: Dictionary = sim.Genes.DATA[gene]
				_choice("Recall "+data.title,data.text+"\nUses this tide's draft choice.",func():
					game._message("Blueprint recalled." if game.archive.recall(run,gene) else "Already chose this tide; recall remains available next tide.")
					open_context({"kind":"archive","page":page}),data.kind,"",not run.chosen and not run.terminal())
			if known.size() > 3: _choice("More blueprints","Next page.",open_context.bind({"kind":"archive","page":(page+1)%ceili(known.size()/3.0)}),"","More")
			_choice("Nucleus","Return to the nucleus.",open_context.bind({"kind":"nucleus"}),"","Back")
	# At most four actions plus a next-page node around any structure.
	if choices.size() > 5 and not mobile() and target.kind not in ["lineage","merge_family"]:
		var all_choices: Array[Button] = choices.duplicate()
		var page := posmod(int(target.get("menu_page",0)),ceili(all_choices.size()/4.0))
		choices = []
		for i in all_choices.size():
			if i >= page*4 and i < page*4+4: choices.append(all_choices[i])
			else:
				all_choices[i].get_parent().remove_child(all_choices[i])
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

func _toggle_instinct() -> void:
	game.preferences.show_instinct=not game.preferences.show_instinct
	game.preferences.save_settings()
	if game.views.has(game.world.player.id):game.views[game.world.player.id].queue_redraw()
	sync(0)

func _toggle_auto_division() -> void:
	var status: Dictionary=game.world.division_status()
	game.world.edit("division_policy",{"scope":"cell","automatic":not status.get("automatic",game.world.player.automatic_division)})
	sync(0)

func _merge(identity: int) -> void:
	if identity==game.world.player.id:return
	if game.world.edit("merge",{"id":identity}):game._message("Merge requested. Seeking your relative’s chemical trail.")
	else:game._message("Choose a living, unattended member of this family.")
	close_context()

func _specialize(cell_id: int,organ_id: int,gene: String) -> void:
	var cell=game.world.player
	if cell.id!=cell_id or cell.organ_by_id(organ_id).is_empty() or not pending_mutation.is_empty():return
	if game.world.mutate_organ(organ_id,gene):
		if game.world.remote_client:
			pending_mutation={"cell":cell_id,"id":organ_id,"gene":gene}
			game._message("Applying specialization…")
		else:game._message("Specialization installed.")
	else:game._message("This organ cannot accept that mutation.")
	open_context({"kind":"organ","id":organ_id})

func command_result(command: Dictionary,result: Dictionary) -> void:
	if command.get("action","")!="mutate" or pending_mutation.is_empty():return
	if not result.get("ok",false):
		pending_mutation.clear()
		if context.get("kind","")=="organ":open_context(context.duplicate())

func _reproduce() -> void:
	# Commit local editing first. Authority owns the durable one-shot request.
	var status: Dictionary=game.world.division_status()
	var active: bool=not status.get("queued",game.world.player.division_requested)
	if active:game.world.commit_build()
	var success: bool=game.world.request_division(active)
	if active:game.world.begin_build()
	open_context({"kind":"bud"})
	if game.world.remote_client:game._message("Division request sent…" if success else "Could not request division.")
	elif not success:game._message(game.world.division_status().reason)
	elif not active:game._message("Queued division cancelled.")
	elif game.world.player.division_requested:game._message("One division queued. Waiting for resources and clear water.")
	else:game._message("Cell divided. Choose your daughter from Family.")

func _follow(identity: int) -> void:
	var keep_editing: bool=game.build_open and not game.world.remote_client
	if game._switch_family(identity) and keep_editing:
		game.world.begin_build();game.build_open=true
		game._update_world(1)
	close_context()

func _challenge(kind: String) -> void:
	game._message("Challenge accepted: "+kind if game.world.evolution.accept_challenge(kind,game.world.player) else "This tide's challenge window has closed.")
	open_context({"kind":"nucleus"})

func describe(target: Dictionary) -> String:
	var cell = game.world.player
	var sim = game.world
	var run = sim.evolution
	match target.kind:
		"overlap": return "Choose a structure\nSeveral controls overlap here."
		"assembly": return "Assembly factory\nCilia, flagella, armor, chemical glands and repair."
		"receptors": return "Receptor factory\nFree Flight, Hunting, Toward family and Away from family receptors. Receptors do not raise other organelle prices."
		"chemistry": return "Chemistry factory\nPhotosynthesis, mitochondria, toxin sacs, toxin, acid, buffer/repair and toxin-neutralizing glands."
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
		"bud","division": return sim.division_status().reason
		"organ":
			var organ: Dictionary = cell.organ_by_id(target.id)
			if organ.is_empty(): return ""
			var result: String = game.TITLES[sim.KINDS.find(organ.kind)]+"\nHealth %d%%" % roundi(100*organ.hp/organ.max_hp)

			var rates: Dictionary = cell.energy_budget.rates(cell.age)
			var upkeep: float = sim.Cell.organ_upkeep(organ)
			var whole: float = cell.operating_budget().steady
			var recent: float = rates.organs.get(organ.id,0.0)
			result += "\nSteady ATP %.2f/s · %.0f%% of cell estimate\nRecent actual %.2f/s · %.0f%% of spending\nCell production surplus %+.2f ATP/s" % [upkeep,100*upkeep/maxf(0.000001,whole),recent,100*recent/maxf(0.000001,rates.spent),rates.net]
			if organ.blocked > 0.05: result += "\nReceptors blocked · cleaning in progress."
			if organ.get("mutation","") != "": result += "\n"+sim.Genes.DATA[organ.mutation].title
			if organ.kind=="toxin_sac":result+="\nStored toxin %.2f / %.2f" % [float(organ.get("stored_toxin",0)),preload("res://scripts/toxin_sac.gd").capacity(organ)]
			return result+"\n"+game.HELP[sim.KINDS.find(organ.kind)]
		"body": return "Membrane · health %d%%\nAcid stress %d%% · local light %d%%\nPunctures lose tissue; repair needs biomass and ATP." % [roundi(cell.health),roundi(cell.acid_stress*100),roundi(sim.light_at(cell.position)*100)]
		"scar":
			for scar in cell.lost_organs:
				if scar.id==target.id:return "Lost organelle\nRestore for %d AP." % cell.construction_price(scar.kind)
			return "Lost organelle"
	return ""

func _tooltip(value: String, at: Vector2) -> void:
	if context.get("kind","")=="organ":
		var organ: Dictionary=game.world.player.organ_by_id(context.id)
		if not organ.is_empty():
			if organ.kind=="toxin_sac":value+="\nStored toxin %.2f / %.2f · released on death" % [float(organ.get("stored_toxin",0)),preload("res://scripts/toxin_sac.gd").capacity(organ)]
			var state: Dictionary=preload("res://scripts/organelle_status.gd").state(game.world,game.world.player,organ)
			value=game.TITLES[game.Simulation.KINDS.find(organ.kind)]+" · "+state.label+"\n"+value
	tip_box.visible = value != ""
	if value == "": return
	if mobile():
		value=value.replace("\n"," · ").replace("Click","Tap").replace("click","tap")
		if value.length()>220:value=value.left(217)+"…"
	elif not Input.is_key_pressed(KEY_ALT): value = value.split("\n")[0]
	var s: float = ui_scale()
	tip.custom_minimum_size.x = minf(320*s,get_viewport_rect().size.x-48)
	tip.add_theme_font_size_override("font_size",roundi(16*s))
	if tip.text != value:
		tip.text = value
		tip_box.reset_size()
	var extent := tip_box.get_combined_minimum_size()
	tip_box.size = extent # Shrink after text reflow; stale tall panels otherwise clip at large UI scales.
	tip_box.position = (at+Vector2(18,18)).clamp(Vector2(12,12),get_viewport_rect().size-extent-Vector2(12,12))
	if mobile() or game.merge_selecting() or context.get("kind","")=="organ" or value.begins_with("Instinct ·"):
		tip.custom_minimum_size.x=maxf(50,get_viewport_rect().size.x-32*s)
		tip.max_lines_visible=3
		tip.add_theme_font_size_override("font_size",roundi((22 if game.notice_timer>3 else 18)*s))
		tip_box.reset_size();tip_box.size=tip_box.get_combined_minimum_size()
		tip_box.position=Vector2(8*s,get_viewport_rect().size.y-mobile_resources.get_combined_minimum_size().y-tip_box.size.y-16*s)
		return
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

func _sync_family_portraits() -> void:
	if context.get("kind","") not in ["lineage","merge_family"]:return
	var models: Dictionary=game.family_portraits if game.world.remote_client else preload("res://scripts/cell_portrait.gd").family(game.world,game.world.lineage)
	for choice in choices:
		if not choice.has_meta("family_id"):continue
		var model: Dictionary=models.get(choice.get_meta("family_id"),{})
		choice.set_portrait(model,game.world.seed_value,game.lineage_color(int(model.get("lineage",0))))

func sync(_dt: float) -> void:
	if not pending_mutation.is_empty():
		var cell=game.world.player
		var organ: Dictionary=cell.organ_by_id(int(pending_mutation.id))
		if cell.id!=pending_mutation.cell or organ.is_empty() or organ.get("mutation","")==pending_mutation.gene:
			pending_mutation.clear()
			if context.get("kind","")=="organ":open_context(context.duplicate())

	if game == null: return
	_events()
	biomass_view.sync()
	var active: bool = not game.settings_panel.visible
	visible = active
	if not active:
		family_picker.hide();return
	if context.get("kind","") in ["lineage","merge_family"] and context.get("roster",0)!=hash(game.world.lineage.records):
		open_context(context.duplicate());return
	_sync_family_portraits()
	var s: float = ui_scale()
	var size := get_viewport_rect().size
	var cell_screen: Vector2 = game.world_layer.to_global(interior.position)
	message.visible = (game.notice_timer > 3) or game.world.evolution.terminal()
	message.text = game.notice if Input.is_key_pressed(KEY_ALT) else game.notice.split("\n")[0]
	message.custom_minimum_size.x = minf(500*s,size.x-48)
	message.size.x = message.custom_minimum_size.x
	message.add_theme_font_size_override("font_size",roundi((22 if mobile() else 20)*s))
	message.position = (cell_screen+Vector2(-message.size.x*0.5,game.world.player.radius*game.zoom+35)).clamp(Vector2(16,16),size-message.size-Vector2(16,16))
	edit_hint.visible = game.build_open and not mobile() and context.get("kind","") not in ["lineage","merge_family"] and (game.selected>=0 or game.moving_id>=0 or not context.is_empty())
	var placing_kind: String=game.Simulation.KINDS[game.selected] if game.selected>=0 else game.world.player.organ_by_id(game.moving_id).get("kind","")
	edit_hint.text = "Tab · return to habitat" if placing_kind=="" else ("Place inside the cell · right-click cancels" if game.world.player.internal_organ(placing_kind) else "Place on membrane · right-click cancels")
	edit_hint.add_theme_font_size_override("font_size",roundi(14*s))
	edit_hint.size = Vector2(minf(540*s,size.x-32),0)
	edit_hint.position = Vector2((size.x-edit_hint.size.x)*0.5,14)
	if not game.build_open and not context.is_empty() and context.kind not in ["lineage","merge_family","archive","past"]: close_context()
	if context.get("kind","") in ["bud","division"] and not choices.is_empty():
		var sim = game.world
		var readiness: Dictionary=sim.division_status()
		var queued: bool=readiness.get("queued",sim.player.division_requested)
		var automatic: bool=readiness.get("automatic",sim.player.automatic_division)
		for choice in choices:
			if choice.has_meta("division_entry") or choice.has_meta("division_once"):
				choice.affordable=true;choice.selected=queued or (automatic and choice.has_meta("division_entry"))
				choice.description=("One division queued. " if queued else "")+readiness.reason
				choice.radial_progress=readiness.get("progress",0.0);choice.progress_ready=readiness.ready
				if choice.has_meta("division_once"):
					choice.caption="Cancel queued division" if queued else "Start division now"
					choice.symbol="Queued" if queued else "Start now"
				choice.queue_redraw()
			elif choice.has_meta("division_auto"):
				choice.selected=automatic;choice.queue_redraw()
	if context.get("kind","") in ["lineage","merge_family"]:family_picker.sync()
	_layout_mobile()
	if investment_picker.visible:investment_picker.sync()
	for choice in choices:
		if choice.has_meta("instinct_toggle"):
			choice.selected=game.preferences.show_instinct
			choice.description=game.world.Behavior.summary(game.world.player)+(" · Tap again to hide." if mobile() else " · Click again to hide.") if game.preferences.show_instinct else "Show this cell’s current intention and direction."
			choice.queue_redraw()
	if not context.is_empty() and context.kind not in ["lineage","merge_family"]:
		if mobile():
			for choice in choices:
				choice.text_scale=s*.85
				choice.custom_minimum_size=Vector2.ONE*60*s
				choice.queue_redraw()
		else:
			var anchor:=screen_at(context)
			menu_radius=106*s if choices.size()>3 else 88*s
			var margin:=Vector2.ONE*(menu_radius+38*s+12)
			menu_center=anchor.clamp(margin,size-margin)
			for i in choices.size():
				var choice=choices[i];choice.text_scale=s;choice.size=Vector2.ONE*68*s
				choice.position=menu_center+Vector2.from_angle(-PI/2+TAU*i/maxi(1,choices.size()))*menu_radius-choice.size*.5
				choice.queue_redraw()
	if mobile():
		message.visible=false


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
		if game.merge_selecting():_tooltip("No available relatives detected yet. Wait for a family trail, or Cancel." if game.merge_candidates.is_empty() else "Tap a bright relative to merge. Tap Cancel to go back." if mobile() else "Click a bright relative to merge. Right-click or Cancel to go back.",Vector2.ZERO)
		elif not context.is_empty() and choices.is_empty() and context.kind!="investment": _tooltip(describe(context),screen_at(context))
		elif not hovered.is_empty() and (game.build_open or Input.is_key_pressed(KEY_ALT)) and (hovered.kind != "body" or Input.is_key_pressed(KEY_ALT)) and game.selected < 0 and game.moving_id < 0: _tooltip(describe(hovered),screen_at(hovered))
		elif not keyboard_target.is_empty() and game.selected < 0: _tooltip(describe(keyboard_target),screen_at(keyboard_target))
		elif game.selected >= 0:
			_tooltip("%s\nCost %d AP · You have %d AP\n%s" % [game.TITLES[game.selected],game.world.player.construction_price(game.Simulation.KINDS[game.selected]),game.world.player.ap,game.placement_status()],cursor)
		elif game.preferences.show_instinct and not game.world.player.dead:
			_tooltip("Instinct · "+game.world.Behavior.summary(game.world.player),Vector2.ZERO)
		else:
			tip_box.hide()
	if context.get("kind","")=="organ" and not tip_box.visible:_tooltip(describe(context),Vector2.ZERO)
	if mobile():
		if game.notice_timer>3:_tooltip(game.notice,Vector2.ZERO)
		elif game.inspector.box.visible:tip_box.hide()
	biomass_view.sync()
	queue_redraw()

func _layout_mobile() -> void:
	var prior_height:=mobile_menu_height
	var s:=ui_scale();var size:=get_viewport_rect().size
	mobile_tray.visible=mobile() and not context.is_empty() and context.kind not in ["lineage","merge_family"] and not choices.is_empty()
	mobile_resources.visible=not game.world.player.dead and ((mobile() and game.touch_controls_available()) or (not mobile() and game.build_open))
	mobile_menu_height=investment_picker.size.y+16*s if mobile() and investment_picker.visible else 0.0
	if mobile() and family_picker.visible:mobile_menu_height=family_picker.position.y+family_picker.size.y+8*s
	cancel_icon.visible=(game.merge_selecting() or (mobile() and (game.selected>=0 or game.moving_id>=0))) and not game.settings_panel.visible
	if cancel_icon.visible:
		var organ: Dictionary=game.world.player.organ_by_id(game.moving_id)
		cancel_icon.kind="" if game.merge_selecting() else game.Simulation.KINDS[game.selected] if game.selected>=0 else organ.get("kind","")
		cancel_icon.symbol="Cancel" if game.merge_selecting() else ""
		cancel_icon.caption="Cancel merge" if game.merge_selecting() else "Cancel placement"
		cancel_icon.position=Vector2(8,38 if game.merge_selecting() else 8)*s;cancel_icon.size=Vector2.ONE*54*s;cancel_icon.text_scale=s*.75;cancel_icon.queue_redraw()
	if mobile_tray.visible:
		var columns:=maxi(1,int((size.x-64*s)/(65*s)))
		var height:=minf(size.y*.32,ceilf(float(choices.size())/columns)*65*s+12*s)
		mobile_tray.position=Vector2(6,6)*s;mobile_tray.size=Vector2(size.x-12*s,height)
		mobile_scroll.custom_minimum_size.y=height-12*s
		mobile_flow.add_theme_constant_override("h_separation",roundi(5*s))
		mobile_flow.add_theme_constant_override("v_separation",roundi(5*s))
		mobile_close.custom_minimum_size=Vector2(32,32)*s;mobile_close.add_theme_font_size_override("font_size",roundi(22*s))
		mobile_menu_height=height+12*s
	if mobile_resources.visible:
		mobile_stocks.custom_minimum_size.x=minf(330*s,size.x-70*s)
		mobile_stocks.visible=not resources_hidden or not mobile()
		mobile_hide.visible=mobile()
		mobile_stocks.add_theme_font_size_override("font_size",roundi(18*s))
		mobile_stocks.text="Biomass %.1f   AP %d   ATP %.1f" % [game.world.player.biomass,game.world.player.ap,game.world.player.energy]
		if game.selected>=0:mobile_stocks.text+="\nCost %d AP" % game.world.player.construction_price(game.Simulation.KINDS[game.selected])
		mobile_hide.text="Resources" if resources_hidden else "−"
		mobile_hide.add_theme_font_size_override("font_size",roundi(16*s))
		mobile_hide.custom_minimum_size=Vector2(30,30)*s
		mobile_resources.reset_size()
		mobile_resources.position=Vector2(8*s,size.y-mobile_resources.get_combined_minimum_size().y-8*s)
	if mobile() and not is_equal_approx(prior_height,mobile_menu_height):game.touch_zoom.layout()

func mobile_diagnostics(conversion: Vector2) -> Dictionary:
	var bounds:=func(node: Control) -> Array:
		var rect:=node.get_global_rect()
		return [rect.position.x*conversion.x,rect.position.y*conversion.y,rect.size.x*conversion.x,rect.size.y*conversion.y]
	var factory:=screen_at({"kind":"assembly"})*conversion
	var chemistry_factory:=screen_at({"kind":"chemistry"})*conversion
	var nucleus:=screen_at({"kind":"nucleus"})*conversion
	return {"resources_visible":mobile_resources.is_visible_in_tree(),"stocks_visible":mobile_stocks.is_visible_in_tree(),
		"stocks":mobile_stocks.text,"resources_bounds":bounds.call(mobile_resources),"hide_bounds":bounds.call(mobile_hide),
		"factory_visible":interior.is_visible_in_tree(),"factory":[factory.x,factory.y],
		"chemistry_factory":[chemistry_factory.x,chemistry_factory.y],"nucleus":[nucleus.x,nucleus.y],
		"investment":investment_picker.diagnostics(conversion),
		"tray_visible":mobile_tray.is_visible_in_tree(),"tray_bounds":bounds.call(mobile_tray),
		"settings_visible":game.settings_panel.visible,
		"placement_cancel":{"visible":cancel_icon.is_visible_in_tree(),"kind":cancel_icon.kind,"bounds":bounds.call(cancel_icon)},
		"description":{"visible":tip_box.is_visible_in_tree(),"text":tip.text,"bounds":bounds.call(tip_box)},
		"choices":choices.map(func(choice):return {"caption":choice.caption,"bounds":bounds.call(choice)})}

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
	if not context.is_empty() and context.kind not in ["investment","lineage","merge_family"] and not mobile():
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
