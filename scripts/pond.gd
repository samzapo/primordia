extends Node2D
const Simulation = preload("res://scripts/simulation.gd")
const CellView = preload("res://scripts/cell_view.gd")
const Preferences = preload("res://scripts/preferences.gd")
const OrganCard = preload("res://scripts/organ_card.gd")
const Visuals = preload("res://scripts/visuals.gd")
const PARTICLE_SHADER = preload("res://shaders/particle.gdshader")
const MINT := Color("80efce")
const GOLD := Color("f5d47b")
const TEXT := Color("e5f5ec")
const MUTED := Color("a3bfc5")
const PALETTE := [Color("a1e88a"),Color("70d6e1"),Color("af9ac3"),Color("fc8c90"),Color("f6b86a")]
const TITLES := ["Flagellum","Protective cortex","Toxin vesicle","Repair body","Feeding pore","Flight receptor"]
const HELP := ["Larger flagella deliver more thrust. Anatomy aims the selected pore or receptor and chooses travel direction.","Protects the membrane directly beneath it. Larger armor covers more surface.","Fires chemicals toward a cell sensed by your feeding pore or flight receptor.","Uses biomass and ATP to repair organs and close punctures faster.","Right-click this card to cycle mouths. Each mouth senses its own food and draws surrounding fluid inward.","Faces a detected cell while flagella propel you away. This is the only organ that triggers flight."]
const FEED_NAMES := ["Grazing pore","Engulfing pore","Proboscis"]
const FEED_HELP := ["Follows nutrient particles, pumps them toward its opening, and consumes them on contact.","Follows prey and nutrient particles. Its opening must cover more than half of a prey cell before damaging it. On death, biomass and gut contents become food; excess spills into the medium.","Follows larger hosts. The tip pierces local defenses and drains biomass. Its fluid pump draws nearby material toward the mouth."]
var world: Simulation = Simulation.new()
var preferences = Preferences.new()
var world_layer := Node2D.new()
var currents := Node2D.new()
var currents_origin := Vector2.ZERO
var preview := Node2D.new()
var vignette := ColorRect.new()
var ui := Control.new()
var hud := PanelContainer.new()
var build_panel := PanelContainer.new()
var settings_panel := PanelContainer.new()
var bottom := PanelContainer.new()
var status_label := Label.new()
var detail_label := Label.new()
var stats_label := Label.new()
var growth_label := Label.new()
var help_label := Label.new()
var debug_label := Label.new()
var cards: Array[Button] = []
var build_scroll := ScrollContainer.new()
var health_bar := ProgressBar.new()
var atp_bar := ProgressBar.new()
var health_text := Label.new()
var atp_text := Label.new()
var scale_select := OptionButton.new()
var fullscreen_check := CheckButton.new()
var batches: Array[MultiMeshInstance2D] = []
var buffers: Array[PackedFloat32Array] = []
var views: Dictionary = {}
var tube_controls := VBoxContainer.new()
var tube_card := OrganCard.new()
var tension_slider := HSlider.new()
var tension_label := Label.new()
var tube_adjust := false
var tube_start: Dictionary = {}
var tube_group := -1
var tube_tension := 0.3
var shape_preview_ticks := 0
var selected := -1
var feeding_mode := 0
var placement_scale := 1.0
var paused := false
var build_open := false
var show_senses := false
var show_debug := false
var ui_time := 0.0
var hud_clock := 0.0
var zoom := 1.0
var manual_zoom := 1.0
var camera_screen := Vector2.ZERO
var render_camera := Vector2.ZERO
var simulation_ms := 0.0
var render_ms := 0.0
var screenshot_path := ""
var capture_frame := 0
var notice := "Tab opens assembly · your anatomy controls movement"
var notice_timer := 8.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	preferences.persist = DisplayServer.get_name() != "headless" and not Array(args).any(func(a): return a.begins_with("--capture=") or a == "--benchmark")
	preferences.load_settings()
	for arg in args:
		if arg.begins_with("--capture="):
			screenshot_path = arg.trim_prefix("--capture=")
			set_physics_process(false)
		elif arg.begins_with("--hud-scale="): preferences.hud_scale = clampf(float(arg.trim_prefix("--hud-scale=")),0.85,1.75)
		elif arg.begins_with("--habitat="): world = Simulation.new(world.seed_value,int(arg.trim_prefix("--habitat=")))
		elif arg.begins_with("--advance="):
			for i in int(arg.trim_prefix("--advance=")): world.step(1.0/60)
		elif arg == "--assembly":
			build_open = true
			selected = 4
		elif arg == "--senses": show_senses = true
	add_child(world_layer)
	world_layer.add_child(currents)
	currents.draw.connect(_draw_currents)
	for kind in 5:
		var instance := MultiMeshInstance2D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_2D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = 256
		multi.visible_instance_count = 0
		instance.multimesh = multi
		var material := ShaderMaterial.new()
		material.shader = PARTICLE_SHADER
		instance.material = material
		world_layer.add_child(instance)
		batches.append(instance)
		var data := PackedFloat32Array()
		data.resize(256*12)
		buffers.append(data)
	world_layer.add_child(preview)
	preview.z_index = 3
	preview.draw.connect(_draw_preview)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.z_index = 4
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/microscope.gdshader")
	vignette.material = material
	add_child(vignette)
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_apply_ui_scale(preferences.hud_scale)
	_apply_fullscreen()
	get_viewport().size_changed.connect(_layout)
	if "--settings" in args: settings_panel.show()
	_layout()
	_update_hud()
	_update_world(1.0)

func _physics_process(dt: float) -> void:
	if is_paused(): return
	var started := Time.get_ticks_usec()
	world.step(dt)
	simulation_ms = lerpf(simulation_ms,(Time.get_ticks_usec()-started)/1000.0,0.15)
	if world.revision%4 == 0: currents.queue_redraw()

func is_paused() -> bool:
	return paused or build_open or settings_panel.visible or world.player.dead

func _process(dt: float) -> void:
	ui_time += dt
	notice_timer = maxf(0,notice_timer-dt)
	var started := Time.get_ticks_usec()
	var alpha := 1.0 if is_paused() or screenshot_path != "" else Engine.get_physics_interpolation_fraction()
	_update_world(alpha)
	render_ms = lerpf(render_ms,(Time.get_ticks_usec()-started)/1000.0,0.15)
	hud_clock += dt
	if hud_clock >= 0.1:
		hud_clock = 0
		_update_hud()
		_layout()
	if build_open:
		if shape_preview_ticks > 0:
			for i in mini(4,shape_preview_ticks):
				world.player.membrane.step(1.0/60,world.player.radius,Vector2.ZERO,world.player.age)
				shape_preview_ticks -= 1
			world.player.render_revision += 1
		preview.queue_redraw()
	if screenshot_path != "":
		capture_frame += 1
		if capture_frame == 30: _capture.call_deferred()

func _update_world(alpha: float) -> void:
	var size := get_viewport_rect().size
	var base_zoom := minf(size.x/Simulation.VIEW.x,size.y/Simulation.VIEW.y)
	zoom = base_zoom*manual_zoom*minf(1.0,150.0/world.player.radius)
	if build_open: zoom = minf(zoom,(size.x-build_panel.size.x-60)/(world.player.radius*3.2))
	camera_screen = Vector2((size.x-build_panel.size.x-24)*0.5 if build_open else size.x*0.5,size.y*0.52)
	world.view_half = size/(2*zoom)
	render_camera = world.player.previous_position+Simulation.Medium.offset(world.player.previous_position,world.player.position)*alpha
	world_layer.position = camera_screen
	world_layer.scale = Vector2.ONE*zoom
	currents.position = Simulation.Medium.offset(render_camera,currents_origin)
	vignette.material.set_shader_parameter("center",camera_screen/size)
	_sync_particles(alpha)
	var alive_ids: Dictionary = {}
	for cell in world.cells:
		var offset: Vector2 = Simulation.Medium.offset(render_camera,cell.position)
		if absf(offset.x) > world.view_half.x+cell.extent()+80 or absf(offset.y) > world.view_half.y+cell.extent()+80: continue
		alive_ids[cell.id] = true
		if not views.has(cell.id):
			var node = CellView.new()
			node.cell = cell
			node.game = self
			world_layer.add_child(node)
			node.z_index = 2
			views[cell.id] = node
		var fraction: float = alpha if cell.activity > 0 else 1.0
		var p: Vector2 = cell.previous_position+Simulation.Medium.offset(cell.previous_position,cell.position)*fraction
		var heading := lerp_angle(cell.previous_angle,cell.angle,fraction)
		views[cell.id].sync(Simulation.Medium.offset(render_camera,p),heading,zoom,world.activity_at(cell.position))
	for identity in views.keys():
		if not alive_ids.has(identity):
			views[identity].queue_free()
			views.erase(identity)

func _sync_particles(alpha: float = 1.0) -> void:
	var counts := PackedInt32Array([0,0,0,0,0])
	const SIZES := [6.5,3.8,4.5,4.5,9.0]
	for index in world.local_particle_ids(30):
		var p: Dictionary = world.particles[index]
		if not p.alive: continue
		var at: Vector2 = p.p
		if p.get("updated",-1) == world.revision: at = p.previous+Simulation.Medium.offset(p.previous,p.p)*alpha
		at = _visible_particle_position(at,alpha)
		at = Simulation.Medium.offset(render_camera,at)
		if absf(at.x)>world.view_half.x+20 or absf(at.y)>world.view_half.y+20: continue
		var kind: int = p.kind
		var slot: int = counts[kind]
		if slot >= batches[kind].multimesh.instance_count:
			batches[kind].multimesh.instance_count *= 2
			buffers[kind].resize(batches[kind].multimesh.instance_count*12)
		var color: Color = PALETTE[kind]
		color.a = 0.6 if kind in [Simulation.OXYGEN,Simulation.DANGER] else 1.0
		if p.life > 0: color.a *= minf(1,p.life)
		var offset := slot*12
		# Transform2D row-major (8 floats), followed by RGBA (4 floats).
		buffers[kind][offset] = SIZES[kind]
		buffers[kind][offset+3] = at.x
		buffers[kind][offset+5] = SIZES[kind]
		buffers[kind][offset+7] = at.y
		buffers[kind][offset+8] = color.r
		buffers[kind][offset+9] = color.g
		buffers[kind][offset+10] = color.b
		buffers[kind][offset+11] = color.a
		counts[kind] += 1
	for kind in 5:
		if counts[kind] > 0: batches[kind].multimesh.buffer = buffers[kind]
		batches[kind].multimesh.visible_instance_count = counts[kind]

func _visible_particle_position(at: Vector2, alpha: float) -> Vector2:
	# Match particle exclusion to interpolated bodies, not only physics poses.
	for cell in world.cells:
		if cell.dead or cell.activity <= 0: continue
		var fraction: float = alpha if cell.activity > 0 else 1.0
		var center: Vector2 = cell.previous_position+Simulation.Medium.offset(cell.previous_position,cell.position)*fraction
		var d := Simulation.Medium.offset(center,at)
		if d.length_squared() > pow(cell.extent()+8,2): continue
		var heading := lerp_angle(cell.previous_angle,cell.angle,fraction)
		var local_angle := d.angle()-heading
		var radius: float = cell.visible_support(local_angle)+7
		if d.length() < radius: at = center+Vector2.from_angle(d.angle())*radius
	return at

func _draw_currents() -> void:
	var half: Vector2 = world.view_half
	var step := maxf(64,64/zoom)
	var origin: Vector2 = world.player.position
	currents_origin = origin
	currents.position = Simulation.Medium.offset(render_camera,origin)
	var lo := Vector2i(((origin-half)/step).floor())
	var hi := Vector2i(((origin+half)/step).ceil())
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			var at := Vector2(x+0.5,y+0.5)*step
			var p := Simulation.Medium.offset(origin,at)
			var flow: Vector2 = world.fluid.sample(at)
			currents.draw_line(p,p+flow*0.55,Color(0.32,0.64,0.69,0.17),1.0/zoom,true)

func _draw_preview() -> void:
	if not build_open: return
	if selected == -2:
		_draw_tubule_preview()
		return
	if selected < 0: return
	var relative := (get_global_mouse_position()-camera_screen)/zoom
	var a: float = world.player.surface_parameter(relative.angle()-world.player.angle)
	var local: Vector2 = world.player.local_point(a)
	var point: Vector2 = (local+local.normalized()*5*placement_scale).rotated(world.player.angle)
	var fits: bool = world.player.can_fit(Simulation.KINDS[selected],a,placement_scale) and world.player.biomass >= Simulation.Cell.organ_cost(Simulation.KINDS[selected],placement_scale)
	Visuals.icon(preview,point,Simulation.KINDS[selected],local.angle()+world.player.angle,placement_scale,ui_time,"flee" if selected == 5 else Simulation.Cell.MODES[feeding_mode])
	preview.draw_arc(point,22*placement_scale,0,TAU,32,MINT if fits else Color("fc8c90"),2/zoom,true)

func _label(parent: Node, value: String, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _panel_box(panel: PanelContainer) -> VBoxContainer:
	ui.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	margin.add_child(box)
	return box

func _build_ui() -> void:
	var top := _panel_box(hud)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation",16)
	row.add_theme_constant_override("v_separation",8)
	top.add_child(row)
	var title := _label(row,"primordia",MINT)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_resource_bar(row,health_bar,health_text,MINT)
	_resource_bar(row,atp_bar,atp_text,GOLD)
	row.add_child(stats_label)
	_button(row,"Build [Tab]",func(): _toggle_build())
	_button(row,"Pause [Space]",func(): paused = not paused)
	_button(row,"Settings",func(): settings_panel.visible = not settings_panel.visible; _layout())
	var lower := _panel_box(bottom)
	lower.add_child(status_label)
	lower.add_child(detail_label)
	lower.add_child(debug_label)
	var box := _panel_box(build_panel)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	_label(heading,"ASSEMBLY PAUSED",MINT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading,"Close",func(): _toggle_build())
	var scroll := build_scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var items := VBoxContainer.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.add_theme_constant_override("separation",10)
	scroll.add_child(items)
	for i in 6:
		var card = OrganCard.new()
		items.add_child(card)
		card.pressed.connect(_select.bind(i))
		card.gui_input.connect(_card_input.bind(i))
		cards.append(card)
	items.add_child(tube_card)
	tube_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tube_card.pressed.connect(func(): _select(-2))
	items.add_child(tube_controls)
	_button(tube_controls,"Connect points",func(): tube_adjust = false; tube_start.clear(); tube_group = -1; _update_hud())
	_button(tube_controls,"Select a link to adjust",func(): tube_adjust = true; tube_start.clear(); _update_hud())
	tube_controls.add_child(tension_label)
	tube_controls.add_child(tension_slider)
	tension_slider.min_value = 0
	tension_slider.max_value = 1
	tension_slider.step = 0.05
	tension_slider.value = tube_tension
	tension_slider.custom_minimum_size.y = 32
	tension_slider.value_changed.connect(_set_tubule_tension)
	items.add_child(help_label)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	items.add_child(growth_label)
	growth_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(items,"Wheel over the cell: size the selected organ.
Click to attach; neighbors make room.
Right-click an installed organ to recycle.",MUTED)
	var options_box := _panel_box(settings_panel)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_box.add_child(settings_scroll)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation",12)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(options)
	_label(options,"DISPLAY & ACCESSIBILITY",MINT)
	_label(options,"HUD and text size")
	options.add_child(scale_select)
	for scale_value in Preferences.SCALES: scale_select.add_item("%d%%" % roundi(scale_value*100))
	scale_select.item_selected.connect(func(i): _apply_ui_scale(Preferences.SCALES[i]))
	options.add_child(fullscreen_check)
	fullscreen_check.text = "Fullscreen [F11]"
	fullscreen_check.toggled.connect(func(on): set_fullscreen(on))
	_button(options,"Sense view [S]",func(): show_senses = not show_senses)
	_button(options,"Performance overlay [F3]",func(): show_debug = not show_debug)
	_button(options,"Next habitat [H]",func(): _restart((world.habitat+1)%3))
	_button(options,"New life [R]",func(): _restart())
	_label(options,"Wheel during placement: organ size
Wheel during play: microscope zoom
No movement keys: anatomy steers.",MUTED)
	_button(options,"Close",func(): settings_panel.hide(); _layout())
	settings_panel.hide()
	build_panel.visible = build_open

func _resource_bar(parent: Node, bar: ProgressBar, label: Label, color: Color) -> void:
	parent.add_child(bar)
	bar.show_percentage = false
	bar.step = 0.0
	bar.add_theme_stylebox_override("background",_style(Color("193642"),Color("355664")))
	bar.add_theme_stylebox_override("fill",_style(color.darkened(0.42),color))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if index == 4: feeding_mode = (feeding_mode+1)%3
		_select(index)
		cards[index].accept_event()

func _style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _apply_ui_scale(value: float) -> void:
	preferences.hud_scale = clampf(value,0.85,1.75)
	var theme := Theme.new()
	theme.default_font_size = roundi(20*preferences.hud_scale)
	theme.set_color("font_color","Label",TEXT)
	theme.set_color("font_color","Button",TEXT)
	theme.set_stylebox("panel","PanelContainer",_style(Color(0.035,0.09,0.13,0.88),Color("355664")))
	for type_name in ["Button","OptionButton"]:
		theme.set_stylebox("normal",type_name,_style(Color("193642"),Color("355664")))
		theme.set_stylebox("hover",type_name,_style(Color("27505a"),MINT))
		theme.set_stylebox("pressed",type_name,_style(Color("27505a"),MINT))
	ui.theme = theme
	for bar in [health_bar,atp_bar]: bar.custom_minimum_size = Vector2(205,44)*preferences.hud_scale
	var closest := 0
	for i in Preferences.SCALES.size():
		if absf(Preferences.SCALES[i]-preferences.hud_scale) < absf(Preferences.SCALES[closest]-preferences.hud_scale): closest = i
	scale_select.select(closest)
	preferences.save_settings()
	_update_hud()
	_layout()
	_layout.call_deferred()
	_scroll_selected.call_deferred()

func _layout() -> void:
	var size := get_viewport_rect().size
	vignette.size = size
	hud.position = Vector2(16,16)
	hud.size = Vector2(size.x-32,0)
	var panel_y := hud.position.y+hud.size.y+16
	var panel_width := minf(490*preferences.hud_scale,size.x*0.48)
	build_panel.position = Vector2(size.x-panel_width-16,panel_y)
	build_panel.size = Vector2(panel_width,maxf(120,size.y-panel_y-16))
	settings_panel.position = Vector2(size.x-minf(500*preferences.hud_scale,size.x-40)-20,panel_y)
	settings_panel.size = Vector2(minf(500*preferences.hud_scale,size.x-40),maxf(120,size.y-panel_y-16))
	bottom.size = Vector2(size.x-32,0)
	bottom.position = Vector2(16,size.y-bottom.size.y-16)
	bottom.visible = not build_open and not settings_panel.visible
	build_panel.visible = build_open
	preview.queue_redraw()

func set_fullscreen(on: bool) -> void:
	preferences.fullscreen = on
	_apply_fullscreen()
	preferences.save_settings()

func _apply_fullscreen() -> void:
	fullscreen_check.set_pressed_no_signal(preferences.fullscreen)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if preferences.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _update_hud() -> void:
	var cell = world.player
	stats_label.text = "Biomass %s" % _quantity(cell.biomass)
	health_bar.max_value = 100
	health_bar.value = cell.health
	atp_bar.max_value = cell.energy_capacity()
	atp_bar.value = cell.energy
	health_text.text = "Health %d%%" % roundi(cell.health)
	atp_text.text = "ATP %s / %s" % [_quantity(cell.energy),_quantity(cell.energy_capacity())]
	var status: String = cell.state
	if cell.dead: status = "LIFE ENDED · R to start again"
	elif build_open: status = "ASSEMBLY PAUSED"
	elif paused or settings_panel.visible: status = "PAUSED"
	status_label.text = status+(" · "+cell.feeding_feedback if cell.feeding_feedback != "" else "")
	detail_label.text = notice if notice_timer > 0 else "%s · Food %s / %s · Oxygen %s · %d sec · Tab to build" % [Simulation.HABITATS[world.habitat],_quantity(cell.substrate),_quantity(cell.gut_capacity()),_quantity(cell.oxygen),int(world.time)]
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label.visible = show_debug
	debug_label.text = "%d FPS · sim %.2f ms · prepare %.2f ms · %d active cells / %d particles" % [Engine.get_frames_per_second(),simulation_ms,render_ms,world.active_cells,world.active_particles]
	if selected >= 0:
		help_label.text = HELP[selected]+("\n\n"+FEED_HELP[feeding_mode] if selected == 4 else "")
		help_label.text += "\n\nSize %.2f× · Cost %.1f biomass\nWheel over the cell to resize." % [placement_scale,Simulation.Cell.organ_cost(Simulation.KINDS[selected],placement_scale)]
	elif selected == -2:
		help_label.text = ("Click a microtubule to select its tension." if tube_adjust else "Click any membrane point or microtubule, then another point to connect them. Branches create movable junctions.")+"\n\nDrag the tension slider to pull more strongly. Right-click a link to remove it, or cancel a pending connection. Shape previews while paused."
	else: help_label.text = "Choose an illustrated organ, then click the membrane. Placement pushes neighbors aside; organs remain anchored during play."
	growth_label.text = "Biomass %s · Radius %.1f · Surface %.0f%% occupied
Growth has no size cap. More food supports more volume and anatomy." % [_quantity(cell.biomass),cell.radius,100*cell.occupied()/cell.perimeter()]
	tube_card.configure("7  Microtubules\nShape & tension","microtubule","",preferences.hud_scale)
	tube_controls.visible = selected == -2
	tension_label.text = "Tension %d%% · %s" % [roundi(tube_tension*100),"select a link" if tube_adjust else "connect points"]
	for i in cards.size():
		cards[i].modulate = MINT if selected == i else Color.WHITE
		var size: float = placement_scale if selected == i else 1.0
		var title: String = FEED_NAMES[feeding_mode] if i == 4 else TITLES[i]
		cards[i].configure("%d  %s\n%.1f biomass · %.2f×" % [i+1,title,Simulation.Cell.organ_cost(Simulation.KINDS[i],size),size],Simulation.KINDS[i],Simulation.Cell.MODES[feeding_mode] if i == 4 else "flee",preferences.hud_scale)

func _quantity(value: float) -> String:
	if value >= 1000000: return "%.2fM" % (value/1000000)
	if value >= 10000: return "%.1fk" % (value/1000)
	return "%.0f" % value

func _toggle_build() -> void:
	build_open = not build_open
	settings_panel.hide()
	if not build_open:
		selected = -1
		tube_start.clear()
	_layout()
	_update_hud()

func _select(index: int) -> void:
	if world.player.dead: return
	build_open = true
	selected = index
	settings_panel.hide()
	_layout()
	_update_hud()
	if index != -2: tube_start.clear()
	_scroll_selected.call_deferred()

func _scroll_selected() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not build_open: return
	if selected == -2: build_scroll.ensure_control_visible(tube_controls)
	elif selected >= 0: build_scroll.ensure_control_visible(cards[selected])

func _restart(profile: int = -1) -> void:
	world = Simulation.new(world.seed_value,world.habitat if profile < 0 else profile)
	selected = -1
	paused = false
	build_open = false
	settings_panel.hide()
	for node in views.values(): node.queue_free()
	views.clear()
	manual_zoom = 1
	tube_start.clear()
	tube_group = -1
	shape_preview_ticks = 0
	_layout()
	_message("A new life. Organs are anchored; flight requires a flight receptor.")

func _message(value: String) -> void:
	notice = value
	notice_timer = 6
	_update_hud()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB: _toggle_build()
			KEY_SPACE: paused = not paused
			KEY_ESCAPE:
				if settings_panel.visible: settings_panel.hide()
				elif build_open: _toggle_build()
			KEY_F11: set_fullscreen(not preferences.fullscreen)
			KEY_F3: show_debug = not show_debug
			KEY_S: show_senses = not show_senses
			KEY_F:
				feeding_mode = (feeding_mode+1)%3
				_select(4)
			KEY_C: _select(5)
			KEY_7: _select(-2)
			KEY_H: _restart((world.habitat+1)%3)
			KEY_R: _restart()
			_:
				if event.keycode >= KEY_1 and event.keycode <= KEY_6: _select(event.keycode-KEY_1)
				else: return
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if build_open and selected >= 0:
				placement_scale = maxf(0.5,placement_scale*(1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/1.1))
				_update_hud()
				preview.queue_redraw()
				return
			manual_zoom = clampf(manual_zoom*(1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/1.12),0.15,3)
			currents.queue_redraw()
			return
		if not build_open: return
		var relative: Vector2 = (event.position-camera_screen)/zoom
		if selected == -2:
			_tubule_input(event,relative.rotated(-world.player.angle))
			return
		if event.button_index == MOUSE_BUTTON_LEFT and selected >= 0:
			var a: float = world.player.surface_parameter(relative.angle()-world.player.angle)
			if absf(relative.length()-world.player.support(relative.angle())) > maxf(26/zoom,12): return
			var mode: String = "flee" if selected == 5 else Simulation.Cell.MODES[feeding_mode]
			if world.install(Simulation.KINDS[selected],a,mode,placement_scale):
				world.player.render_revision += 1
				_message("Attached. Tab resumes life; right-click recycles an organelle.")
			else: _message("Needs enough biomass and total membrane area. Neighbors move aside.")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			for i in world.player.organs.size():
				var at: Vector2 = Simulation.Medium.offset(world.player.position,world.player.organ_position(world.player.organs[i]))
				if relative.distance_to(at) < maxf(22/zoom,20*world.player.organs[i].scale) and world.remove(i):
					world.player.render_revision += 1
					_message("Recycled half the remaining material; the rest becomes debris.")
					break

func _nearest_tubule(local: Vector2) -> Dictionary:
	var membrane = world.player.membrane
	var best: Dictionary = {}
	var distance := 18.0/zoom
	for link in membrane.skeleton.links:
		var a: Vector2 = membrane.skeleton.point(link.a,membrane)
		var b: Vector2 = membrane.skeleton.point(link.b,membrane)
		var t := clampf((local-a).dot(b-a)/maxf(0.001,(b-a).length_squared()),0,1)
		var error := local.distance_to(a.lerp(b,t))
		if error < distance:
			distance = error
			best = {"kind":"link","id":link.id,"t":t}
	return best

func _tubule_anchor(local: Vector2) -> Dictionary:
	var cell = world.player
	var a: float = cell.surface_parameter(local.angle())
	if local.distance_to(cell.local_point(a)) < 20/zoom: return {"kind":"membrane","a":a}
	return _nearest_tubule(local)

func _set_tubule_tension(value: float) -> void:
	tube_tension = value
	if tube_group >= 0:
		world.player.membrane.skeleton.set_tension(tube_group,value)
		shape_preview_ticks = 60
	_update_hud()

func _tubule_input(event: InputEventMouseButton, local: Vector2) -> void:
	var membrane = world.player.membrane
	var skeleton = membrane.skeleton
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not tube_start.is_empty(): tube_start.clear()
		else:
			var hit := _nearest_tubule(local)
			if not hit.is_empty():
				skeleton.remove_group(skeleton.link_by_id(hit.id).group)
				tube_group = -1
				shape_preview_ticks = 60
		return
	if event.button_index != MOUSE_BUTTON_LEFT: return
	if tube_adjust:
		var hit := _nearest_tubule(local)
		if hit.is_empty(): return
		var link: Dictionary = skeleton.link_by_id(hit.id)
		tube_group = link.group
		tube_tension = link.tension
		tension_slider.set_value_no_signal(tube_tension)
		_update_hud()
		return
	var anchor := _tubule_anchor(local)
	if anchor.is_empty():
		_message("Choose a point on the membrane or an existing microtubule.")
		return
	if tube_start.is_empty():
		tube_start = anchor
		tube_group = -1
	else:
		tube_group = skeleton.connect_points(tube_start,anchor,tube_tension,membrane,world.player.radius)
		tube_start.clear()
		if tube_group >= 0:
			shape_preview_ticks = 60
			_message("Microtubule connected. Adjust its tension to change the shape.")

func _draw_tubule_preview() -> void:
	var membrane = world.player.membrane
	var skeleton = membrane.skeleton
	for link in skeleton.links:
		var a: Vector2 = skeleton.point(link.a,membrane).rotated(world.player.angle)
		var b: Vector2 = skeleton.point(link.b,membrane).rotated(world.player.angle)
		preview.draw_line(a,b,GOLD if link.group == tube_group else Color("b7d9e8"),2/zoom,true)
		preview.draw_circle(a,4/zoom,MINT)
		preview.draw_circle(b,4/zoom,MINT)
	if not tube_start.is_empty() and skeleton.valid(tube_start):
		var a: Vector2 = skeleton.point(tube_start,membrane).rotated(world.player.angle)
		var cursor := (get_global_mouse_position()-camera_screen)/zoom
		preview.draw_line(a,cursor,GOLD,2/zoom,true)
		preview.draw_circle(a,6/zoom,GOLD)

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("CAPTURE ",screenshot_path," result=",result)
	get_tree().quit(result)
