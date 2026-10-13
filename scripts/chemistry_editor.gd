extends PanelContainer
## A temporary cell-local pathway editor. It configures local catalysts only.
const Catalog = preload("res://scripts/chemistry_catalog.gd")
var game
var graph := GraphEdit.new()
var status := Label.new()
var add_menu := MenuButton.new()
var blueprint_menu := MenuButton.new()
var inspected := Label.new()
var bound_cell := -1
var port_outputs: Dictionary = {}
var port_inputs: Dictionary = {}
var templates: Array = []
var designs: Array = []
const SAVE_PATH := "user://chemistry_blueprints.json"

func initialize(owner_game) -> void:
	game = owner_game
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 30
	var column := VBoxContainer.new()
	add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var title := Label.new()
	title.text = "Cell pathways"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	add_menu.text = "Add catalyst"
	bar.add_child(add_menu)
	blueprint_menu.text = "Designs"
	bar.add_child(blueprint_menu)
	var save := Button.new()
	save.text = "Save design"
	save.pressed.connect(_save)
	bar.add_child(save)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(hide)
	bar.add_child(close_button)
	graph.custom_minimum_size = Vector2(650,450)
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.minimap_enabled = false
	column.add_child(graph)
	inspected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(inspected)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	graph.connection_request.connect(_connect)
	graph.disconnection_request.connect(_disconnect)
	for template in Catalog.data().modules:
		templates.append(template.id)
		add_menu.get_popup().add_item(template.name,templates.size()-1)
	add_menu.get_popup().id_pressed.connect(_add)
	blueprint_menu.get_popup().id_pressed.connect(_load)
	hide()

func open_cell() -> void:
	if not game.build_open or game.world.player.dead: return
	bound_cell = game.world.player.id
	var viewport: Vector2 = game.get_viewport_rect().size
	size = Vector2(minf(790,viewport.x-40),minf(650,viewport.y-40))
	position = (viewport-size)*0.5
	show()
	_rebuild()
	_read_designs()
	status.text = "Connections permit local binding. Molecules reach catalysts through circulation and diffusion."

func _valid() -> bool:
	return visible and game.build_open and not game.world.player.dead and game.world.player.id == bound_cell

func _process(_dt: float) -> void:
	if not visible: return
	if not _valid(): hide(); return
	var chemistry = game.world.player.chemistry
	inspected.text = "Particles %d · glucose %.2f · pyruvate %.2f · ATP %.1f · water %.2f\nPaused: molecule stocks, reaction clocks, and physiology are frozen." % [chemistry.particles.size(),chemistry.amount("glucose"),chemistry.amount("pyruvate"),chemistry.amount("atp"),chemistry.amount("water")]

func _rebuild() -> void:
	graph.clear_connections()
	for child in graph.get_children():
		if child is GraphNode:
			graph.remove_child(child)
			child.queue_free()
	port_outputs.clear()
	port_inputs.clear()
	var chemistry = game.world.player.chemistry
	for model in chemistry.nodes:
		var definition := Catalog.module(model.module)
		var node := GraphNode.new()
		node.name = "reaction_"+str(model.id)
		node.title = definition.name
		node.position_offset = model.position
		node.custom_minimum_size = Vector2(210,0)
		graph.add_child(node)
		var inputs: Array = definition.inputs.keys()
		var outputs: Array = definition.outputs.keys()
		if model.module == "digestion": outputs.append("salvage")
		inputs = inputs.filter(func(key): return key != "biomass")
		outputs = outputs.filter(func(key): return key != "biomass")
		port_inputs[node.name] = inputs
		port_outputs[node.name] = outputs
		for i in maxi(inputs.size(),outputs.size()):
			var row := HBoxContainer.new()
			var left := Label.new()
			var right := Label.new()
			left.text = Catalog.data().species[inputs[i]].name if i < inputs.size() else ""
			right.text = Catalog.data().species[outputs[i]].name if i < outputs.size() else ""
			left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(left)
			row.add_child(right)
			node.add_child(row)
			node.set_slot(i,i<inputs.size(),0,Color("72d8df"),i<outputs.size(),0,Color("b6e887"))
		var controls := HBoxContainer.new()
		var active := CheckButton.new()
		active.text = "Active"
		active.button_pressed = model.enabled
		controls.add_child(active)
		var allocation := SpinBox.new()
		allocation.min_value = 0
		allocation.max_value = 100
		allocation.step = 25
		allocation.value = model.allocation*100
		allocation.suffix = "%"
		controls.add_child(allocation)
		node.add_child(controls)
		active.toggled.connect(func(value): chemistry.configure(model.id,allocation.value/100,value))
		allocation.value_changed.connect(func(value): chemistry.configure(model.id,value/100,active.button_pressed))
		var description := Label.new()
		description.text = "%s · %.2f/s\n%s" % [model.compartment,chemistry.flux.get(model.id,0),chemistry.limiting.get(model.id,"Waiting for local particles")]
		node.add_child(description)
		if not model.basal:
			var recycle := Button.new()
			recycle.text = "Recycle · no AP refund"
			recycle.pressed.connect(func():
				chemistry.remove_module(model.id,game.world.player)
				_rebuild())
			node.add_child(recycle)
		node.position_offset_changed.connect(func(): model.position = node.position_offset)
	for edge in chemistry.edges:
		var from_name := "reaction_"+str(edge.from)
		var to_name := "reaction_"+str(edge.to)
		if not port_outputs.has(from_name) or not port_inputs.has(to_name): continue
		var a: int = port_outputs[from_name].find(edge.species)
		var b: int = port_inputs[to_name].find(edge.species)
		if a>=0 and b>=0: graph.connect_node(from_name,a,to_name,b)

func _identity(name: StringName) -> int:
	return int(str(name).trim_prefix("reaction_"))

func _connect(from_name: StringName, from_port: int, to_name: StringName, to_port: int) -> void:
	if not _valid(): return
	var source: String = port_outputs[from_name][from_port]
	var destination: String = port_inputs[to_name][to_port]
	if source != destination: status.text = "These ports carry different metabolites."; return
	var error: String = game.world.player.chemistry.connect_route(_identity(from_name),_identity(to_name),source)
	status.text = error if error != "" else "Binding compatibility connected. No molecules moved."
	if error == "": graph.connect_node(from_name,from_port,to_name,to_port)

func _disconnect(from_name: StringName, from_port: int, to_name: StringName, to_port: int) -> void:
	if not _valid(): return
	game.world.player.chemistry.disconnect_route(_identity(from_name),_identity(to_name),port_outputs[from_name][from_port])
	graph.disconnect_node(from_name,from_port,to_name,to_port)

func _add(index: int) -> void:
	if not _valid() or index < 0 or index >= templates.size(): return
	if templates[index] in ["digestion","osmosis","photosynthesis"]:
		status.text = "This domain is inherent. Set its activity and allocation on the graph; photosynthesis also needs membrane anatomy."
		return
	var cell = game.world.player
	if game.world.evolution.points < 1 or cell.biomass < 10:
		status.text = "Needs 10 usable tissue and 1 AP."
		return
	var identity: int = cell.chemistry.add_module(templates[index],cell)
	if identity < 0: status.text = "Capacity unavailable. Food, water and light domains are inherent; configure them in place."; return
	game.world.evolution.points -= 1
	status.text = "Catalyst installed. Operation needs local substrate and ATP particles."
	_rebuild()

func _read_designs() -> void:
	designs.clear()
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH,FileAccess.READ)
		if file != null and file.get_length() <= 1048576:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and parsed.get("version",0) == 1 and parsed.get("designs") is Array:
				for design in parsed.designs.slice(-32):
					if design is Dictionary and design.get("configuration") is Dictionary: designs.append(design)
	blueprint_menu.get_popup().clear()
	for i in designs.size(): blueprint_menu.get_popup().add_item(str(designs[i].get("name","Design")),i)

func _save() -> void:
	if not _valid(): return
	_read_designs()
	designs.append({"name":"Design "+str(designs.size()+1),"configuration":game.world.player.chemistry.configuration()})
	if designs.size()>32: designs.pop_front()
	var file := FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if file == null: status.text = "Could not save the local design."; return
	file.store_string(JSON.stringify({"version":1,"designs":designs}))
	_read_designs()
	status.text = "Configuration saved. Resource amounts and live particles are never saved in a blueprint."

func _load(index: int) -> void:
	if not _valid() or index < 0 or index >= designs.size(): return
	var error: String = game.world.player.chemistry.load_configuration(designs[index].configuration)
	status.text = error if error != "" else "Configuration loaded; particles and resources retained."
	if error == "": _rebuild()
