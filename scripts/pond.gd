extends Node2D
const Simulation = preload("res://scripts/simulation.gd")
const CellView = preload("res://scripts/cell_view.gd")
const Preferences = preload("res://scripts/preferences.gd")
const OrganCard = preload("res://scripts/organ_card.gd")
const Visuals = preload("res://scripts/visuals.gd")
const ParticleArt = preload("res://scripts/particle_art.gd")
const PARTICLE_SHADER = preload("res://shaders/particle.gdshader")
const MINT := Color("80efce")
const GOLD := Color("f5d47b")
const TEXT := Color("e5f5ec")
const MUTED := Color("a3bfc5")
const TITLES := ["Flagellum","Protective cortex","Hunting spike","Repair body","Grazing pore","Flight receptor","Photosynthesis","Toxin vesicle","Toxin neutralizer","Acid gland"]
const HELP := ["Larger flagella deliver more thrust. Anatomy chooses travel direction.","Protects the membrane directly beneath it. Larger armor covers more surface.","Senses lower total biomass cells at long range, turns toward them and pulls you into pursuit. Its physical tip punctures on contact.","Uses biomass and ATP to repair organs and close punctures faster. Releases buffers that neutralize local acidity and accelerates receptor cleaning.","Senses and pumps nutrients into its opening. Secretes reusable enzymes that turn waste into food when aligned.","Faces a detected cell while propelling you away. This is the only organ that triggers flight.","Seeks brighter water. Light fixes dissolved carbon into biomass and food, releasing oxygen. Works best in bright habitat patches.","Spends ATP and biomass to fire toxins and receptor-blocking decoys at a cell detected by a spike or flight receptor.","Releases complementary particles that bind toxin into harmless waste. Costs small amounts of biomass and ATP.","Releases acidifying particles. Moderate acidity favors digestive enzymes; excess acidity costs ATP and stresses cells. Repair bodies release buffers."]
var world: Simulation = Simulation.new()
var preferences = Preferences.new()
var world_layer := Node2D.new()
var habitat_view := preload("res://scripts/habitat_view.gd").new()
var currents := Node2D.new()
var currents_origin := Vector2.ZERO
var preview := Node2D.new()
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
var tube_hint := Label.new()
var cards: Array[Button] = []
var build_scroll := ScrollContainer.new()
var health_bar := ProgressBar.new()
var atp_bar := ProgressBar.new()
var health_text := Label.new()
var atp_text := Label.new()
var scale_select := OptionButton.new()
var fullscreen_check := CheckButton.new()
var bloom_check := CheckButton.new()
var batches: Array[MultiMeshInstance2D] = []
var buffers: Array[PackedFloat32Array] = []
var views: Dictionary = {}
var tube_start: Dictionary = {}
var tube_group := -1
var tube_tension := 0.3
var shape_preview_ticks := 0
var selected := -1
var placement_scale := 1.0
var camera_locked := true
var free_camera := Vector2.ZERO
var camera_dragging := false
var camera_button := 0
var camera_button_control := Button.new()
var quit_button := Button.new()
var light_layer := ColorRect.new()
var microscope_layer := ColorRect.new()
var acidity_texture := ImageTexture.new()
var light_texture := ImageTexture.new()
var organ_items := VBoxContainer.new()
var genome_button := Button.new()
var evolution_panel = preload("res://scripts/evolution_panel.gd").new()
var light_factor_shown := -1.0
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
var notice := "Establish a lineage: fund offspring before 12:00, then sustain it through dusk. Tab to adapt."
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
			world.begin_build()
			build_open = true
			selected = 4
		elif arg == "--senses": show_senses = true
	light_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var light_material := ShaderMaterial.new()
	light_material.shader = preload("res://shaders/light.gdshader")
	light_layer.material = light_material
	microscope_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var microscope_material := ShaderMaterial.new()
	microscope_material.shader = preload("res://shaders/microscope.gdshader")
	microscope_layer.material = microscope_material
	microscope_layer.z_index = 4
	microscope_material.set_shader_parameter("bloom_enabled",preferences.bloom)
	acidity_texture = ImageTexture.create_from_image(Image.create_from_data(64,40,false,Image.FORMAT_RF,world.acidity.values.to_byte_array()))
	light_material.set_shader_parameter("acidity_map",acidity_texture)
	_refresh_light_texture()
	add_child(light_layer)
	free_camera = world.player.position
	add_child(world_layer)
	world_layer.add_child(habitat_view)
	habitat_view.z_index = 0
	habitat_view.configure(world.habitat_geometry)
	light_material.set_shader_parameter("habitat_seed",float(posmod(world.seed_value,997)))
	world_layer.add_child(currents)
	currents.draw.connect(_draw_currents)
	var particle_material := ShaderMaterial.new()
	particle_material.shader = PARTICLE_SHADER
	for kind in Simulation.SPECIES_COUNT:
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
		instance.texture = ParticleArt.texture(kind)
		instance.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		instance.material = particle_material
		world_layer.add_child(instance)
		batches.append(instance)
		var data := PackedFloat32Array()
		data.resize(256*12)
		buffers.append(data)
	world_layer.add_child(preview)
	preview.z_index = 3
	preview.draw.connect(_draw_preview)
	add_child(microscope_layer)
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(tube_hint)
	tube_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tube_hint.modulate = GOLD
	_build_ui()
	_apply_ui_scale(preferences.hud_scale)
	_apply_fullscreen()
	get_viewport().size_changed.connect(_layout)
	if "--settings" in args: settings_panel.show()
	_configure_backend()
	_layout()
	_update_hud()
	_update_world(1.0)

func _physics_process(dt: float) -> void:
	if is_paused(): return
	var started := Time.get_ticks_usec()
	var identity: int = world.player.id
	world.step(dt)
	if identity != world.player.id:
		camera_locked = true
		free_camera = world.player.position
		_message("Division complete. You now follow the offspring; keep it healthy and feeding through dusk.")
	simulation_ms = lerpf(simulation_ms,(Time.get_ticks_usec()-started)/1000.0,0.15)
	if world.revision%4 == 0: currents.queue_redraw()

func is_paused() -> bool:
	return build_open or settings_panel.visible or world.player.dead or world.evolution.terminal()

func _can_edit_tubules() -> bool:
	return build_open and not settings_panel.visible and not world.player.dead and not world.evolution.terminal()

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
	if is_paused():
		if shape_preview_ticks > 0:
			for i in mini(4,shape_preview_ticks):
				world.player.membrane.step(1.0/60,world.player.radius,Vector2.ZERO,world.player.age)
				shape_preview_ticks -= 1
			world.player.render_revision += 1
	preview.queue_redraw()
	var hover := _nearest_tubule(_player_relative(get_global_mouse_position()).rotated(-world.player.angle)) if _can_edit_tubules() else {}
	tube_hint.visible = not settings_panel.visible and not hover.is_empty() and get_viewport().gui_get_hovered_control() == null
	if tube_hint.visible:
		var link: Dictionary = world.player.membrane.skeleton.link_by_id(hover.id)
		tube_hint.text = "%d%% tension · scroll to adjust" % roundi(link.tension*100)
		tube_hint.position = (get_global_mouse_position()+Vector2(16,20)).clamp(Vector2(8,8),get_viewport_rect().size-tube_hint.size-Vector2(8,8))
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
	world.camera_follows_player = camera_locked
	world.camera_position = free_camera
	render_camera = world.player.previous_position+Simulation.Medium.offset(world.player.previous_position,world.player.position)*alpha if camera_locked else free_camera
	light_layer.material.set_shader_parameter("camera",render_camera)
	light_layer.material.set_shader_parameter("view_size",size/zoom)
	light_layer.material.set_shader_parameter("screen_center",camera_screen/size)
	microscope_layer.material.set_shader_parameter("camera",render_camera)
	microscope_layer.material.set_shader_parameter("view_size",size/zoom)
	microscope_layer.material.set_shader_parameter("screen_center",camera_screen/size)
	preview.position = Simulation.Medium.offset(render_camera,world.player.position)
	world_layer.position = camera_screen
	world_layer.scale = Vector2.ONE*zoom
	currents.position = Simulation.Medium.offset(render_camera,currents_origin)
	habitat_view.sync(render_camera,world.view_half)
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
		if views[cell.id].cell != cell: views[cell.id].seen_revision = -1
		views[cell.id].cell = cell
		var fraction: float = alpha if cell.activity > 0 else 1.0
		var p: Vector2 = cell.previous_position+Simulation.Medium.offset(cell.previous_position,cell.position)*fraction
		var heading := lerp_angle(cell.previous_angle,cell.angle,fraction)
		views[cell.id].sync(Simulation.Medium.offset(render_camera,p),heading,zoom,world.activity_at(cell.position))
	for identity in views.keys():
		if not alive_ids.has(identity):
			views[identity].queue_free()
			views.erase(identity)

func _sync_particles(alpha: float = 1.0) -> void:
	if world.native_render:
		var capacities := PackedInt32Array()
		for batch in batches: capacities.append(batch.multimesh.instance_count)
		var result: Array = world.kernels.render_particles(world.particles,world.local_particle_ids(30),world.cells,render_camera,world.view_half,alpha,world.revision,capacities)
		for kind in Simulation.SPECIES_COUNT:
			buffers[kind] = result[kind]
			var count: int = result[-1][kind]
			var capacity: int = result[kind].size()/12
			if batches[kind].multimesh.instance_count != capacity: batches[kind].multimesh.instance_count = capacity
			if count > 0: batches[kind].multimesh.buffer = buffers[kind]
			batches[kind].multimesh.visible_instance_count = count
		return
	if world.spatial_queries: world.cell_index.rebuild(world.cells)
	var counts := PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0])
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
		var color := Color.WHITE
		color.a = 0.6 if kind in [Simulation.OXYGEN,Simulation.DANGER] else 1.0
		var offset := slot*12
		# Transform2D row-major (8 floats), followed by RGBA (4 floats).
		var heading: float = lerp_angle(p.previous_angle,p.angle,alpha) if p.get("updated",-1) == world.revision else p.angle
		# The vector silhouette fits inside the existing circular contact envelope.
		var diameter: float = 2.0*Simulation.particle_radius(kind)*Simulation.particle_scale(p.amount)
		var cosine: float = cos(heading)*diameter
		var sine: float = sin(heading)*diameter
		buffers[kind][offset] = cosine
		buffers[kind][offset+1] = -sine
		buffers[kind][offset+3] = at.x
		buffers[kind][offset+4] = sine
		buffers[kind][offset+5] = cosine
		buffers[kind][offset+7] = at.y
		buffers[kind][offset+8] = color.r
		buffers[kind][offset+9] = color.g
		buffers[kind][offset+10] = color.b
		buffers[kind][offset+11] = color.a
		counts[kind] += 1
	for kind in Simulation.SPECIES_COUNT:
		if counts[kind] > 0: batches[kind].multimesh.buffer = buffers[kind]
		batches[kind].multimesh.visible_instance_count = counts[kind]

func _visible_particle_position(at: Vector2, alpha: float) -> Vector2:
	# Match particle exclusion to interpolated bodies, not only physics poses.
	for cell_id in world.cell_index.at(at) if world.spatial_queries else range(world.cells.size()):
		var cell = world.cells[cell_id]
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
	var origin: Vector2 = render_camera
	currents_origin = origin
	currents.position = Simulation.Medium.offset(render_camera,origin)
	var lo := Vector2i(((origin-half)/step).floor())
	var hi := Vector2i(((origin+half)/step).ceil())
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			var at := Vector2(x+0.5,y+0.5)*step
			var p := Simulation.Medium.offset(origin,at)
			var flow: Vector2 = world.fluid.sample(at)
			currents.draw_line(p,p+flow*0.55,Color(0.48,0.89,0.91,0.2),1.0/zoom,true)

func _draw_preview() -> void:
	if settings_panel.visible or world.player.dead or world.evolution.terminal(): return
	_draw_tubule_preview()
	if not build_open or selected < 0: return
	var relative := _player_relative(get_global_mouse_position())
	var a: float = world.player.surface_parameter(relative.angle()-world.player.angle)
	var local: Vector2 = world.player.local_point(a)
	var point: Vector2 = (local+local.normalized()*5*placement_scale).rotated(world.player.angle)
	var fits: bool = world.player.can_fit(Simulation.KINDS[selected],a,placement_scale) and world.player.biomass >= Simulation.Cell.organ_cost(Simulation.KINDS[selected],placement_scale) and world.evolution.points >= world.Evolution.install_price(placement_scale)
	Visuals.icon(preview,point,Simulation.KINDS[selected],local.angle()+world.player.angle,placement_scale,ui_time)
	preview.draw_arc(point,22*placement_scale,0,TAU,32,MINT if fits else Color("fc8c90"),2/zoom,true)

func _refresh_light_texture() -> void:
	var values := PackedFloat32Array()
	values.resize(64*40)
	for y in 40:
		for x in 64: values[y*64+x] = world.light_at(Vector2(x+0.5,y+0.5)*64)
	light_texture = ImageTexture.create_from_image(Image.create_from_data(64,40,false,Image.FORMAT_RF,values.to_byte_array()))
	light_layer.material.set_shader_parameter("light_map",light_texture)
	microscope_layer.material.set_shader_parameter("light_map",light_texture)

func _player_relative(screen: Vector2) -> Vector2:
	return (screen-camera_screen)/zoom-Simulation.Medium.offset(render_camera,world.player.position)

func _toggle_camera() -> void:
	if camera_locked: free_camera = Simulation.Medium.wrap_position(render_camera)
	camera_locked = not camera_locked
	camera_dragging = false
	world.camera_follows_player = camera_locked
	world.camera_position = free_camera
	currents.queue_redraw()
	_update_hud()

func _toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	tube_start.clear()
	camera_dragging = false
	if settings_panel.visible:
		world.cancel_build()
		build_open = false
		selected = -1
		shape_preview_ticks = 0
	_layout()
	_update_hud()

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
	row.add_child(camera_button_control)
	camera_button_control.pressed.connect(_toggle_camera)
	_button(row,"Settings [Esc]",_toggle_settings)
	var lower := _panel_box(bottom)
	for label in [status_label,detail_label,debug_label]: label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lower.add_child(status_label)
	lower.add_child(detail_label)
	lower.add_child(debug_label)
	var box := _panel_box(build_panel)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	_label(heading,"BUILD · PAUSED",MINT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading,"Cancel",func(): _toggle_build())
	var actions := HFlowContainer.new()
	box.add_child(actions)
	_button(actions,"Apply & resume",_apply_build)
	_button(actions,"Undo plan",_undo_build)
	var scroll := build_scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pages := HFlowContainer.new()
	box.add_child(pages)
	_button(pages,"Grow",func(): organ_items.show(); evolution_panel.hide())
	_button(pages,"Modify",func(): _build_section("modify"))
	pages.add_child(genome_button)
	genome_button.pressed.connect(func(): _build_section("genome"))
	_button(pages,"Lineage",func(): _build_section("lineage"))
	box.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contents)
	contents.add_child(evolution_panel)
	evolution_panel.initialize(self)
	evolution_panel.hide()
	var items := organ_items
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.add_theme_constant_override("separation",10)
	contents.add_child(items)
	_label(items,"GROW NEW ANATOMY",MINT)
	for i in Simulation.KINDS.size():
		var card = OrganCard.new()
		items.add_child(card)
		card.pressed.connect(_select.bind(i))
		cards.append(card)
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
	_label(options,"SETTINGS",MINT)
	_label(options,"HUD and text size")
	options.add_child(scale_select)
	for scale_value in Preferences.SCALES: scale_select.add_item("%d%%" % roundi(scale_value*100))
	scale_select.item_selected.connect(func(i): _apply_ui_scale(Preferences.SCALES[i]))
	options.add_child(fullscreen_check)
	fullscreen_check.text = "Fullscreen [F11]"
	fullscreen_check.toggled.connect(func(on): set_fullscreen(on))
	options.add_child(bloom_check)
	bloom_check.text = "Light bloom"
	bloom_check.set_pressed_no_signal(preferences.bloom)
	bloom_check.toggled.connect(set_bloom)
	_button(options,"Sense view [S]",func(): show_senses = not show_senses)
	_button(options,"Performance overlay [F3]",func(): show_debug = not show_debug)
	_button(options,"Next habitat [H]",func(): _restart((world.habitat+1)%3))
	_button(options,"New life [R]",func(): _restart())
	_label(options,"Wheel during placement: organ size
In build: drag microtubules; hover + wheel: tension
Wheel elsewhere: zoom
Space: follow / free camera
Free camera: drag empty water or middle-drag
No movement keys: anatomy steers.",MUTED)
	_button(options,"Close [Esc]",_toggle_settings)
	options.add_child(quit_button)
	quit_button.text = "Quit game"
	quit_button.pressed.connect(func(): get_tree().quit())
	settings_panel.hide()
	build_panel.visible = build_open

func _resource_bar(parent: Node, bar: ProgressBar, label: Label, color: Color) -> void:
	parent.add_child(bar)
	bar.show_percentage = false
	bar.step = 0.0
	bar.add_theme_stylebox_override("background",_style(Color("254361"),Color("527b9d")))
	bar.add_theme_stylebox_override("fill",_style(color.darkened(0.42),color))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	theme.set_stylebox("panel","PanelContainer",_style(Color(0.085,0.16,0.29,0.94),Color("527b9d")))
	for type_name in ["Button","OptionButton"]:
		theme.set_stylebox("normal",type_name,_style(Color("254361"),Color("527b9d")))
		theme.set_stylebox("hover",type_name,_style(Color("315b7c"),MINT))
		theme.set_stylebox("pressed",type_name,_style(Color("315b7c"),MINT))
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
	light_layer.size = size
	microscope_layer.size = size
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

func set_bloom(on: bool) -> void:
	preferences.bloom = on
	microscope_layer.material.set_shader_parameter("bloom_enabled",on)
	bloom_check.set_pressed_no_signal(on)
	preferences.save_settings()

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
	if absf(world.evolution.light_factor-light_factor_shown) > 0.02:
		_refresh_light_texture()
		light_factor_shown = world.evolution.light_factor
	genome_button.text = "Genome" + (" •" if not world.evolution.chosen else "")
	if build_open: evolution_panel.refresh()
	if acidity_texture.get_width() > 0: acidity_texture.update(Image.create_from_data(64,40,false,Image.FORMAT_RF,world.acidity.values.to_byte_array()))
	stats_label.text = "Biomass %s · %d AP · Tide %d · %d:%02d" % [_quantity(cell.biomass),world.evolution.points,mini(6,world.evolution.tide+1),int(world.time)/60,int(world.time)%60]
	camera_button_control.text = "Unlock view [Space]" if camera_locked else "Follow cell [Space]"
	health_bar.max_value = 100
	health_bar.value = cell.health
	atp_bar.max_value = cell.energy_capacity()
	atp_bar.value = cell.energy
	health_text.text = "Health %d%%" % roundi(cell.health)
	atp_text.text = "ATP %s / %s" % [_quantity(cell.energy),_quantity(cell.energy_capacity())]
	var status: String = cell.state
	if cell.reserve_activity > 0: status += " · USING BIOMASS FOR ATP"
	if cell.fermentation_activity > 0: status += " · FERMENTING · LOW OXYGEN"
	if cell.organs.any(func(o): return o.blocked > 0.05): status += " · RECEPTORS CLEARING"
	if cell.acid_stress > 0.1: status += " · ACID STRESS %d%%" % roundi(cell.acid_stress*100)
	if world.evolution.terminal(): status = ("LINEAGE ESTABLISHED" if world.won else "LINEAGE ENDED")+" · R to start again"
	elif cell.dead: status = "LIFE ENDED · R to start again"
	elif build_open: status = "ASSEMBLY PAUSED"
	elif settings_panel.visible: status = "SETTINGS · PAUSED"
	status_label.text = status+(" · "+cell.feeding_feedback if cell.feeding_feedback != "" else "")
	detail_label.text = world.evolution.ending if world.evolution.terminal() else notice if notice_timer > 0 else world.evolution.forecast()+"\nTab to adapt · Light %d%% · Acid %d%% · Oxygen %.1f" % [roundi(world.light_at(cell.position)*100),roundi(world.acidity.sample(cell.position)*100),cell.oxygen]
	if not world.evolution.chosen and not world.evolution.terminal(): detail_label.text += "\nBlueprint ready · Tab → Genome"
	if not world.evolution.terminal() and world.evolution.tide < 6:
		var quote: Dictionary = world.offspring_quote()
		detail_label.text += "\nLineage reserve %.0f / %.0f biomass · %.0f / 60 ATP · due 12:00" % [cell.brood_mass,quote.material,cell.brood_energy]
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label.visible = show_debug
	var viewport_size := get_viewport_rect().size
	var fitted_zoom := minf(viewport_size.x/Simulation.VIEW.x,viewport_size.y/Simulation.VIEW.y)
	var effective_zoom := zoom/maxf(fitted_zoom,0.001)
	var zoom_text := "Zoom %.1f%%" % (effective_zoom*100)
	if absf(effective_zoom-manual_zoom) >= 0.0005: zoom_text += " (selected %.1f%%)" % (manual_zoom*100)
	debug_label.text = "%s · %d FPS · %s · sim %.2f ms · prepare %.2f ms · %d active cells / %d particles" % ["GPU experiment" if world.gpu_transport != null else "Native CPU" if world.kernels != null else "GDScript",Engine.get_frames_per_second(),zoom_text,simulation_ms,render_ms,world.active_cells,world.active_particles]
	debug_label.tooltip_text = "Zoom is relative to the default view (100%). Selected is your wheel setting; growth or the build panel can widen the actual view."
	if selected >= 0:
		help_label.text = HELP[selected]+"\n\nSize %.2f× · Cost %.1f tissue + %d AP\nWheel over the cell to resize." % [placement_scale,Simulation.Cell.organ_cost(Simulation.KINDS[selected],placement_scale),world.Evolution.install_price(placement_scale)]
	else: help_label.text = "Choose an organ, then click the membrane. Drag between membrane or microtubule points to shape your cell; hover a link and scroll for tension."
	growth_label.text = "Biomass %s · Radius %.1f · Surface %.0f%% occupied\nGrowth has no size cap." % [_quantity(cell.biomass),cell.radius,100*cell.occupied()/cell.perimeter()]
	for i in cards.size():
		cards[i].modulate = MINT if selected == i else Color.WHITE
		var size: float = placement_scale if selected == i else 1.0
		var title: String = TITLES[i]
		cards[i].configure("%d  %s\n%.1f tissue · %d AP · %.2f×" % [(i+1)%10,title,Simulation.Cell.organ_cost(Simulation.KINDS[i],size),world.Evolution.install_price(size),size],Simulation.KINDS[i],"graze",preferences.hud_scale)

func _quantity(value: float) -> String:
	if value >= 1000000: return "%.2fM" % (value/1000000)
	if value >= 10000: return "%.1fk" % (value/1000)
	return "%.0f" % value

func _toggle_build() -> void:
	if world.player.dead or world.evolution.terminal(): return
	if build_open: world.cancel_build()
	else: world.begin_build()
	build_open = not build_open
	evolution_panel.signature = ""
	evolution_panel.moving = false
	shape_preview_ticks = 0
	settings_panel.hide()
	if not build_open:
		shape_preview_ticks = 0
		tube_group = -1
		selected = -1
		tube_start.clear()
	_layout()
	_update_hud()

func _select(index: int) -> void:
	if world.player.dead or world.evolution.terminal(): return
	world.begin_build()
	build_open = true
	organ_items.show()
	evolution_panel.hide()
	evolution_panel.existing_id = -1
	evolution_panel.moving = false
	selected = index
	settings_panel.hide()
	_layout()
	_update_hud()
	tube_start.clear()
	_scroll_selected.call_deferred()

func _scroll_selected() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not build_open: return
	if selected >= 0: build_scroll.ensure_control_visible(cards[selected])

func _restart(profile: int = -1) -> void:
	if world.gpu_transport != null: world.gpu_transport.close()
	world = Simulation.new(world.seed_value,world.habitat if profile < 0 else profile)
	habitat_view.configure(world.habitat_geometry)
	_configure_backend()
	_refresh_light_texture()
	selected = -1
	camera_locked = true
	free_camera = world.player.position
	camera_dragging = false
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
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == camera_button: camera_dragging = false
		if event.button_index == MOUSE_BUTTON_LEFT and not tube_start.is_empty():
			if not _can_edit_tubules() or get_viewport().gui_get_hovered_control() != null: tube_start.clear()
			else: _unhandled_input(event)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB: _toggle_build()
			KEY_SPACE: _toggle_camera()
			KEY_ESCAPE: _toggle_settings()
			KEY_F11: set_fullscreen(not preferences.fullscreen)
			KEY_F3: show_debug = not show_debug
			KEY_S: show_senses = not show_senses
			KEY_F: _select(4)
			KEY_C: _select(5)
			KEY_0: _select(9)
			KEY_H: _restart((world.habitat+1)%3)
			KEY_R: _restart()
			_:
				if event.keycode >= KEY_1 and event.keycode <= KEY_9: _select(event.keycode-KEY_1)
				else: return
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _can_edit_tubules(): tube_start.clear()
	if settings_panel.visible or world.player.dead or world.evolution.terminal(): return
	if event is InputEventMouseMotion and camera_dragging and not camera_locked:
		free_camera = Simulation.Medium.wrap_position(free_camera-event.relative/zoom)
		world.camera_position = free_camera
		currents.queue_redraw()
		return
	if not event is InputEventMouseButton: return
	var relative := _player_relative(event.position)
	var local := relative.rotated(-world.player.angle)
	if not event.pressed:
		if event.button_index == camera_button: camera_dragging = false
		if event.button_index == MOUSE_BUTTON_LEFT and not tube_start.is_empty():
			var endpoint := _tubule_anchor(local)
			if not endpoint.is_empty():
				tube_group = world.player.membrane.skeleton.connect_points(tube_start,endpoint,tube_tension,world.player.membrane,world.player.radius)
				if tube_group >= 0:
					shape_preview_ticks = 60
					_message("Microtubule placed · hover and scroll to set tension.")
			tube_start.clear()
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var hit := _nearest_tubule(local) if _can_edit_tubules() else {}
		if not hit.is_empty():
			var link: Dictionary = world.player.membrane.skeleton.link_by_id(hit.id)
			tube_group = link.group
			tube_tension = clampf(link.tension+(0.05 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.05),0,1)
			world.player.membrane.skeleton.set_tension(tube_group,tube_tension)
			shape_preview_ticks = 60
			_message("Microtubule tension %d%%" % roundi(tube_tension*100))
			return
		if build_open and selected >= 0:
			placement_scale = maxf(0.5,placement_scale*(1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/1.1))
			_update_hud()
			return
		manual_zoom = clampf(manual_zoom*(1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/1.12),0.15,3)
		currents.queue_redraw()
		return
	if event.button_index == MOUSE_BUTTON_LEFT and build_open and evolution_panel.moving:
		var a: float = world.player.surface_parameter(local.angle())
		if absf(relative.length()-world.player.support(relative.angle())) > maxf(26/zoom,12): return
		world.player.move_organ(evolution_panel.existing_id,a)
		evolution_panel.moving = false
		_message("Move planned. Apply to commit.")
		return
	if event.button_index == MOUSE_BUTTON_LEFT and build_open and selected >= 0:
		var a: float = world.player.surface_parameter(relative.angle()-world.player.angle)
		if absf(relative.length()-world.player.support(relative.angle())) > maxf(26/zoom,12): return
		if world.install(Simulation.KINDS[selected],a,"flee" if selected == 5 else "graze",placement_scale):
			_message("Attachment planned. Apply commits; Tab cancels the plan.")
		else: _message("Needs enough AP, tissue and total membrane area. Neighbors move aside.")
		return
	if event.button_index == MOUSE_BUTTON_LEFT and _can_edit_tubules():
		var anchor := _tubule_anchor(local)
		if not anchor.is_empty(): tube_start = anchor; return
	if event.button_index == MOUSE_BUTTON_RIGHT and build_open:
		if not tube_start.is_empty(): tube_start.clear(); return
		if build_open:
			for i in world.player.organs.size():
				var organ: Dictionary = world.player.organs[i]
				if relative.distance_to(Simulation.Medium.offset(world.player.position,world.player.organ_position(organ))) < maxf(22/zoom,20*organ.scale):
					world.remove(i)
					return
		var hit := _nearest_tubule(local)
		if not hit.is_empty():
			world.player.membrane.skeleton.remove_group(world.player.membrane.skeleton.link_by_id(hit.id).group)
			tube_group = -1
			shape_preview_ticks = 60
		return
	if not camera_locked and (event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_LEFT):
		camera_dragging = true
		camera_button = event.button_index

func _nearest_tubule(local: Vector2) -> Dictionary:
	var membrane = world.player.membrane
	var best: Dictionary = {}
	var distance := 8.0/zoom
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
	var hit := _nearest_tubule(local)
	if not hit.is_empty(): return hit
	if local.length() < cell.visible_support(local.angle()): return {"kind":"point","p":local}
	return {}

func _set_tubule_tension(value: float) -> void:
	if not _can_edit_tubules(): return
	tube_tension = clampf(value,0,1)
	if tube_group >= 0: world.player.membrane.skeleton.set_tension(tube_group,tube_tension)
	shape_preview_ticks = 60

func _draw_tubule_preview() -> void:
	if not _can_edit_tubules(): return
	var membrane = world.player.membrane
	var skeleton = membrane.skeleton
	var hit := _nearest_tubule(_player_relative(get_global_mouse_position()).rotated(-world.player.angle))
	for link in skeleton.links:
		if hit.is_empty() or hit.id != link.id: continue
		var a: Vector2 = skeleton.point(link.a,membrane).rotated(world.player.angle)
		var b: Vector2 = skeleton.point(link.b,membrane).rotated(world.player.angle)
		preview.draw_line(a,b,GOLD if link.group == tube_group else Color("b7d9e8"),2/zoom,true)
		preview.draw_circle(a,4/zoom,MINT)
		preview.draw_circle(b,4/zoom,MINT)
	if not tube_start.is_empty() and skeleton.valid(tube_start):
		var a: Vector2 = skeleton.point(tube_start,membrane).rotated(world.player.angle)
		var cursor := _player_relative(get_global_mouse_position())
		preview.draw_line(a,cursor,GOLD,2/zoom,true)
		preview.draw_circle(a,6/zoom,GOLD)

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("CAPTURE ",screenshot_path," result=",result)
	get_tree().quit(result)

func _configure_backend() -> void:
	if "--gpu-transport" not in OS.get_cmdline_user_args(): return
	var gpu = load("res://scripts/gpu_transport.gd").new()
	if gpu.initialize(): world.gpu_transport = gpu
	else: push_warning("GPU transport unavailable; keeping the CPU backend. Use --rendering-method mobile for the experiment.")

func _exit_tree() -> void:
	if world.gpu_transport != null: world.gpu_transport.close()

func _apply_build() -> void:
	world.commit_build()
	build_open = false
	selected = -1
	tube_start.clear()
	evolution_panel.moving = false
	shape_preview_ticks = 0
	_message("Anatomy applied. The ecological clock resumes.")
	_layout()

func _build_section(name: String) -> void:
	organ_items.hide()
	evolution_panel.show()
	evolution_panel.show_section(name)
	build_scroll.scroll_vertical = 0

func _undo_build() -> void:
	world.undo_build()
	tube_start.clear()
	tube_group = -1
	shape_preview_ticks = 0
	evolution_panel.existing_id = -1
	evolution_panel.moving = false
	evolution_panel.signature = ""
	_update_hud()
