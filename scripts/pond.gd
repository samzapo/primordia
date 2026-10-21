extends Node2D
var debug_census_cache: Dictionary={}
var debug_census_usec:=0
const Simulation = preload("res://scripts/simulation.gd")
const FlowView = preload("res://scripts/flow_view.gd")
const ReactionSparks = preload("res://scripts/reaction_sparks.gd")
var family_portraits: Dictionary={} # Current owned-family thumbnail data, separate from camera/simulation cells.
const CellView = preload("res://scripts/cell_view.gd")
const Preferences = preload("res://scripts/preferences.gd")
const Visuals = preload("res://scripts/visuals.gd")
const ParticleArt = preload("res://scripts/particle_art.gd")
const MIN_ZOOM := 0.8
const MAX_ZOOM := 12.0
const PARTICLE_SHADER = preload("res://shaders/particle.gdshader")
const MINT := Color("80efce")
const GOLD := Color("f5d47b")
const TEXT := Color("e5f5ec")
const MUTED := Color("a3bfc5")
const TITLES := ["Flagellum","Protective cortex","Pore-forming gland","Buffer / repair gland","Oral groove","Flight receptor","Photosynthesis","Toxin gland","Toxin neutralizer","Acid gland","Hunting receptor","Cilia","Mitochondrion","Counterattack gland","Toxin sac","Toward family receptor","Away from family receptor","Feeding proboscis"]
const HELP := ["Flagella provide thrust. Anatomy chooses travel direction.","Protects the membrane directly beneath it. Coverage follows its membrane attachment.","Spends tissue and ATP to emit surface tags and pore subunits toward a local pheromone report. Four aligned subunits assemble a membrane pore; inhibitors and repair can stop it.","Uses biomass and ATP to repair organs and close punctures faster. Releases buffers that neutralize local acidity and accelerates receptor cleaning.","Senses and pumps nutrients into its opening. Secretes reusable enzymes that turn waste into food when aligned.","Reads nearby pheromones reporting armed non-family cells and retreats from their last reported location. Also moves away from locally sensed toxin particles. It also senses harmful acidity; an actual hit can trigger a short escape reflex.","Seeks brighter water, or soft light with the Shade adaptation. Light fixes dissolved CO2 into biomass and food, releasing oxygen. Works best in bright habitat patches.","Spends ATP and biomass to fire toxins and receptor-blocking decoys toward a pheromone report received by a hunting or flight receptor.","Releases complementary particles that bind toxin into harmless waste. Costs small amounts of biomass and ATP.","Releases acidifying particles. Moderate acidity helps nutrients bind for higher ATP yield and favors digestive enzymes; excess acidity costs ATP and damages cells. Repair bodies release buffers.","Reads local pheromones from any non-family cell, regardless of size or defenses. Faces and pursues the last reported location. Pair with secretory attack glands.","A short beating ciliary band provides propulsion and a strong local feeding current from the receptor-selected direction. Draws all particles with the water, including hazards; a grazing pore still consumes food.","An internal organelle that gets more ATP from food when oxygen is available. Each healthy mitochondrion adds50% baseline aerobic ATP without reducing biomass, using finite food fuel.","Responds to locally received chemical warnings from armed cells. Its toxin spares cells without offensive organs.","Stores toxin using surplus biomass and ATP. Bursts into a cloud of ordinary toxin particles when the cell dies. Does not steer or fire at targets.","Follows locally detected family pheromone trails. Survival needs take priority; movement organs provide thrust.","Steers away from locally detected family pheromone trails. Survival needs take priority; movement organs provide thrust.","Draws food from a living cell touched by its tip. Transfers up to 2 biomass/s as finite food, costing 0.5 ATP per unit. Pair with a hunting receptor and movement. A visible puncture and a round particle moving back to its base show active feeding."]
var music := preload("res://scripts/music_director.gd").new()
var music_slider := HSlider.new()
var world: Simulation = Simulation.new()
var use_particle_pool := true
var resident_starting:=false
var resident_streaming:=true
var resident_controller
var resident_view: Node2D
var particle_backend:="cpu"
var archive_error := ""
var archive = preload("res://scripts/lineage_archive.gd").new()
var preferences = Preferences.new()
var world_layer := Node2D.new()
var habitat_view := preload("res://scripts/habitat_view.gd").new()
var currents := Node2D.new()
var flow_view := FlowView.new()
var reaction_view := ReactionSparks.new()
var merge_view := preload("res://scripts/merge_view.gd").new()
var death_view := preload("res://scripts/death_view.gd").new()
var death_focus_age := 2.0
var death_focus_at := Vector2.ZERO
var death_focus_extent:=1.0
var death_focus_rotation:=0.0
var death_seen := 0
var death_world
var death_frame_dt := 0.0
var show_reaction_sparks := true
var membrane_depth := true
var flow_streamers := true
var flow_wakes := true
var currents_origin := Vector2.ZERO
var preview := Node2D.new()
var placement_feedback=preload("res://scripts/placement_feedback.gd").new()
var ui := Control.new()
var player_help:=preload("res://scripts/player_help.gd").new()
var gameplay_menu_button: Button
var mechanics_menu_button: Button
var touch_zoom := preload("res://scripts/touch_zoom.gd").new()
var user_paused := false
var perception := "exteroception"
var perception_menu_button: Button
var perception_mask:=preload("res://scripts/perception_mask.gd").new()
var pause_control_ready := true
var cell_ui := preload("res://scripts/cell_interface.gd").new()
var inspector := preload("res://scripts/particle_inspector.gd").new()
var moving_id := -1
var placement_angle := 0.0
var placement_keyboard := false
var camera_offset := Vector2.ZERO
var camera_zoom := 1.0
var camera_rotation := 0.0
var intero_rotation:=0.0
var follow_heading:=0.0
var follow_origin:=Vector2.ZERO
var focus_animating := false
var observation_view: Dictionary = {}
var merge_selection: Dictionary={}
var merge_candidates: Dictionary={}
var merge_available: Dictionary={} # Ephemeral authoritative eligibility, never saved anatomy.
var scale_bar := preload("res://scripts/scale_bar.gd").new()
var settings_panel := PanelContainer.new()
var lineage_confirmation := ConfirmationDialog.new()
var lineage_confirming:=false
var feedback:=preload("res://scripts/feedback_form.gd").new()
var feedback_menu_button: Button
var profile:=preload("res://scripts/player_profile.gd").new()
var palette:=preload("res://scripts/lineage_palette.gd").new()
var proboscis_feeding_art=preload("res://scripts/proboscis_feeding_art.gd").new()
var player_color:=""
var palette_menu_button: Button
var nameplates:=preload("res://scripts/player_nameplates.gd").new()
var profile_menu_button: Button
var player_name:=""
var favorite_name:=""
var lineage_names: Array=[]
var settings_help: Label
var debug_label := Label.new()
var tube_hint := Label.new()
var scale_select := OptionButton.new()
var fullscreen_check := CheckButton.new()
var bloom_check := CheckButton.new()
var ripple_check := CheckButton.new()
var current_style_choices:=GridContainer.new()
var crest_style_button: Button
var streamline_style_button: Button
var batches: Array[MultiMeshInstance2D] = []
var buffers: Array[PackedFloat32Array] = []
var views: Dictionary = {}
var tube_start: Dictionary = {}
var tube_group := -1
var tube_tension := 0.3
var shape_preview_ticks := 0
var selected := -1
var camera_locked := true
var free_camera := Vector2.ZERO
var camera_dragging := false
var camera_button := 0
var quit_button := Button.new()
var session_controls:=VBoxContainer.new()
var light_layer := ColorRect.new()
var water_target: SubViewport
var water_display: TextureRect
var water_cache_enabled:=true
var microscope_layer := ColorRect.new()
var acidity_texture := ImageTexture.new()
var light_texture := ImageTexture.new()
var light_factor_shown := -1.0
var particle_lod := PackedByteArray()
var build_open := false
var show_senses := false
var show_debug := false
var manage_catchup := true
var diagnostic_tick_cost_ms := 0.0 # benchmark-only injected latency
var frame_ticks := 0
var frame_tick_usec := 0
var last_frame_ticks := 0
var last_frame_sim_ms := 0.0
var last_frame_ms := 0.0
var perf_previous_usec := 0
var perf_wall_seconds := 0.0
var perf_sim_seconds := 0.0
var simulation_rate := 1.0
var ui_time := 0.0
var hud_clock := 0.0
var detail_pixel_ratio:=1.0
var detail_canvas_scale:=1.0
var pending_cell_rasters: Dictionary={}
var zoom := 1.0
var manual_zoom := 1.0
# Explicit test harness switch for historical stress fixtures; no gameplay control.
var diagnostic_zoom := false
var preview_radius := -1.0
var camera_screen := Vector2.ZERO
var render_camera := Vector2.ZERO
var render_rotation:=0.0
var camera_has_pose:=false
var camera_followed_id:=-1
var camera_motion=preload("res://scripts/camera_motion.gd").new()
var frame_trace
var native_geometry := true
var simulation_ms := 0.0
var render_ms := 0.0
var screenshot_path := ""
var capture_frame := 0
var notice := ""
var notice_timer := 0.0

func _ready() -> void:
	if OS.has_feature("web"):detail_pixel_ratio=maxf(1,float(JavaScriptBridge.eval("window.primordiaRenderPixelRatio || window.devicePixelRatio || 1")))
	world.enable_ambient_carbon()
	world.enable_perception_domains()
	if manage_catchup: Engine.max_physics_steps_per_frame = 2
	var args := OS.get_cmdline_user_args()
	preferences.persist = DisplayServer.get_name() != "headless" and not Array(args).any(func(a): return a.begins_with("--capture=") or a == "--benchmark")
	preferences.load_settings()
	archive.persist = preferences.persist
	archive.load_history()
	archive.begin()
	for arg in args:
		if arg.begins_with("--capture="):
			screenshot_path = arg.trim_prefix("--capture=")
			set_physics_process(false)
		elif arg.begins_with("--hud-scale="): preferences.hud_scale = clampf(float(arg.trim_prefix("--hud-scale=")),0.85,1.75)
		elif arg.begins_with("--habitat="): world = Simulation.new(world.seed_value,int(arg.trim_prefix("--habitat=")))
		elif arg.begins_with("--advance="):
			for i in int(arg.trim_prefix("--advance=")): world.step(1.0/60)
		elif arg == "--senses": show_senses = true
	world.enable_ambient_carbon()
	light_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var light_material := ShaderMaterial.new()
	light_material.shader = preload("res://shaders/light.gdshader")
	light_layer.material = light_material
	light_material.set_shader_parameter("water_ripples",preferences.water_ripples)
	microscope_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var microscope_material := ShaderMaterial.new()
	microscope_material.shader = preload("res://shaders/microscope.gdshader")
	microscope_layer.material = microscope_material
	perception_mask.initialize(self)
	microscope_layer.z_index = 4
	microscope_material.set_shader_parameter("bloom_enabled",preferences.bloom)
	acidity_texture = ImageTexture.create_from_image(Image.create_from_data(64,40,false,Image.FORMAT_RF,world.acidity.values.to_byte_array()))
	light_material.set_shader_parameter("acidity_map",acidity_texture)
	_refresh_light_texture()
	add_child(light_layer)
	free_camera = world.player.position
	add_child(world_layer)
	world_layer.add_child(flow_view)
	flow_view.use_crests=preferences.current_style=="crests"
	world_layer.add_child(reaction_view)
	merge_view.game=self;merge_view.z_index=10;world_layer.add_child(merge_view)
	death_view.z_index = 11
	world_layer.add_child(death_view)
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
		instance.z_index = 2 if kind == Simulation.PHEROMONE else 0
		world_layer.add_child(instance)
		batches.append(instance)
		particle_lod.append(0)
		var data := PackedFloat32Array()
		data.resize(256*12)
		buffers.append(data)
	proboscis_feeding_art.game=self;proboscis_feeding_art.z_index=7;world_layer.add_child(proboscis_feeding_art)
	world_layer.add_child(preview)
	preview.z_index = 9
	preview.draw.connect(_draw_preview)
	placement_feedback.game=self;placement_feedback.z_index=12;world_layer.add_child(placement_feedback)
	add_child(microscope_layer)
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(scale_bar)
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
	if "--assembly" in args:
		_toggle_build()
		camera_zoom = manual_zoom
		focus_animating = false
		_update_world(1.0)
		cell_ui.open_context({"kind":"assembly"})
	add_child(music)
	music.initialize(self)
	if OS.has_feature("web"):_finish_web_startup.call_deferred()

func _finish_web_startup() -> void:
	await RenderingServer.frame_post_draw
	JavaScriptBridge.eval("window.primordiaLoadingReady?.()")

static func catchup_limit(tick_ms: float, current: int) -> int:
	# When one tick already exhausts the 60 Hz budget, extra catch-up steps
	# cannot recover real time. Leave a presentation/input opportunity instead.
	if tick_ms > 16.0: return 1
	if tick_ms < 12.0: return 2
	return clampi(current,1,2)

func _physics_process(dt: float) -> void:
	if is_paused(): return
	var started := Time.get_ticks_usec()
	var identity: int = world.player.id
	world.interoceptive_cells.clear()
	if perception=="interoception" and can_follow():
		var focus=_follow_cell()
		if Simulation.Medium.visibility(focus.position,render_camera,world.view_half+Vector2.ONE*focus.extent())>0:world.interoceptive_cells[focus.id]=true
	world.external_offscreen=perception=="interoception"
	if world.kernels!=null:world.kernels.set_activity_views([],world.external_offscreen)
	if world.resident!=null:world.resident.gpu.set_activity_views([],world.external_offscreen)
	world.step(dt)
	_track_player_death()
	if identity != world.player.id:
		cell_ui.close_context()
		camera_locked = true
		camera_offset = Vector2.ZERO
		free_camera = world.player.position
	var tick_usec := Time.get_ticks_usec()-started
	frame_ticks += 1
	frame_tick_usec += tick_usec
	perf_sim_seconds += dt
	if frame_trace != null: frame_trace.tick(tick_usec,dt)
	simulation_ms = lerpf(simulation_ms,tick_usec/1000.0,0.15)
	if manage_catchup: Engine.max_physics_steps_per_frame = catchup_limit(simulation_ms+diagnostic_tick_cost_ms,Engine.max_physics_steps_per_frame)
	var music_start := Time.get_ticks_usec()
	if music.refill_between_ticks: music.refill()
	if frame_trace != null: frame_trace.work("music",Time.get_ticks_usec()-music_start)
	if not flow_streamers and world.revision%4 == 0: currents.queue_redraw()

func is_paused() -> bool:
	if world.server_mode: return resident_starting
	return user_paused or resident_starting or build_open or settings_panel.visible or cell_ui.context.get("kind","") in ["lineage","archive","past"] or world.evolution.terminal()

func _can_edit_tubules() -> bool:
	return false # Microtubules are sampled anatomy, never edited by a player.

func _process(dt: float) -> void:
	var now := Time.get_ticks_usec()
	last_frame_ticks = frame_ticks
	last_frame_sim_ms = frame_tick_usec/1000.0
	frame_ticks = 0;frame_tick_usec = 0
	last_frame_ms = (now-perf_previous_usec)/1000.0 if perf_previous_usec > 0 else 0.0
	perf_previous_usec = now
	if is_paused(): perf_wall_seconds = 0;perf_sim_seconds = 0
	else:
		perf_wall_seconds += last_frame_ms/1000.0
		if perf_wall_seconds >= 1.0:
			simulation_rate = perf_sim_seconds/perf_wall_seconds
			perf_wall_seconds = 0;perf_sim_seconds = 0
	var process_start := Time.get_ticks_usec() if frame_trace != null else 0
	if not user_paused:ui_time += dt
	if merge_selecting() and (world.player.id!=merge_selection.cell or world.player.dead or user_paused):_end_merge_selection()
	camera_motion.advance(dt,user_paused)
	if lineage_confirming and OS.has_feature("web"):
		var action=JSON.parse_string(str(JavaScriptBridge.eval("window.primordiaReaders.take('lineage')")))
		if action is Dictionary:
			lineage_confirming=false
			if action.get("confirmed",false):_start_new_lineage()
	death_frame_dt = 0.0 if is_paused() else dt
	death_focus_age += death_frame_dt
	if focus_animating and not user_paused:
		camera_zoom = lerpf(camera_zoom,manual_zoom,1-exp(-dt*10))
		if absf(camera_zoom-manual_zoom) < 0.002: focus_animating = false
	notice_timer = maxf(0,notice_timer-dt)
	# Relax edited geometry before drawing, without advancing biology or the run.
	if build_open and not is_equal_approx(preview_radius,world.player.radius):
		shape_preview_ticks = 60
	preview_radius = world.player.radius
	if is_paused():
		if shape_preview_ticks > 0:
			for i in mini(4,shape_preview_ticks):
				world.player.membrane.step(1.0/60,world.player.radius,Vector2.ZERO,world.player.age)
				shape_preview_ticks -= 1
			world.player.render_revision += 1
	var started := Time.get_ticks_usec()
	var alpha := 1.0 if is_paused() or screenshot_path != "" else Engine.get_physics_interpolation_fraction()
	_update_world(alpha)
	placement_feedback.sync()
	render_ms = lerpf(render_ms,(Time.get_ticks_usec()-started)/1000.0,0.15)
	var ui_start := Time.get_ticks_usec() if frame_trace != null else 0
	hud_clock += dt
	if hud_clock >= 0.1:
		hud_clock = 0
		archive.sync(world)
		if archive.last_error != archive_error:
			archive_error = archive.last_error
			if archive_error != "": _message(archive_error+"\nHistory remains in memory for this session; saving will retry.")
		_update_hud()
		_layout()
	cell_ui.interior.animate(0.0 if user_paused else dt)
	cell_ui.sync(dt)
	if frame_trace != null: frame_trace.work("ui",Time.get_ticks_usec()-ui_start)
	var music_start := Time.get_ticks_usec() if frame_trace != null else 0
	music.update_music(dt)
	if frame_trace != null: frame_trace.work("music",Time.get_ticks_usec()-music_start)

	var inspection_start := Time.get_ticks_usec() if frame_trace != null else 0
	var cursor := inspector.cursor_at(get_global_mouse_position())
	var inspect_allowed := death_focus_age >= 1.8 and get_viewport_rect().has_point(cursor) and not settings_panel.visible and not camera_dragging and not merge_selecting() and selected < 0 and moving_id < 0 and tube_start.is_empty() and cell_ui.context.is_empty() and get_viewport().gui_get_hovered_control() == null
	inspector.update_lens(dt,cursor,alpha,inspect_allowed)
	preview.queue_redraw()
	var hover := _nearest_tubule(_player_relative(get_global_mouse_position()).rotated(-world.player.angle)) if _can_edit_tubules() and selected < 0 and moving_id < 0 and cell_ui.hit(get_global_mouse_position()).is_empty() else {}
	tube_hint.visible = not settings_panel.visible and not hover.is_empty() and get_viewport().gui_get_hovered_control() == null
	if tube_hint.visible:
		var link: Dictionary = world.player.membrane.skeleton.link_by_id(hover.id)
		tube_hint.text = "%d%% tension · scroll to adjust" % roundi(link.tension*100)
		tube_hint.position = (get_global_mouse_position()+Vector2(16,20)).clamp(Vector2(8,8),get_viewport_rect().size-tube_hint.size-Vector2(8,8))
	if frame_trace != null:
		frame_trace.work("inspection",Time.get_ticks_usec()-inspection_start)
		frame_trace.work("process",Time.get_ticks_usec()-process_start)
	if screenshot_path != "":
		capture_frame += 1
		if capture_frame == 30: _capture.call_deferred()

func _track_player_death() -> void:
	if death_world != world:
		death_world = world
		camera_motion.cancel();camera_has_pose=false;camera_followed_id=-1
		death_seen = 0
		death_focus_age = 2.0
	for event in world.death_bursts:
		if event.serial <= death_seen: continue
		death_seen = event.serial
		if not event.player or not death_view.recent(event,world.time): continue
		_ease_camera()
		death_focus_age = 0
		death_focus_at = event.at
		death_focus_extent=float(event.radius)
		for point in event.outline:death_focus_extent=maxf(death_focus_extent,point.length())
		death_focus_rotation=render_rotation
		cell_ui.close_context()
		inspector.update_lens(0,get_global_mouse_position(),1,false)
		camera_locked = true
		camera_offset = Vector2.ZERO

func _follow_cell():
	return world.player

func internal_visible(cell) -> bool:
	return perception=="interoception" and cell.id==_follow_cell().id

func _maximum_zoom() -> float:
	return MAX_ZOOM*10 if perception=="interoception" else MAX_ZOOM

func _toggle_perception() -> void:
	if merge_selecting():_end_merge_selection(false)
	_ease_camera()
	perception="interoception" if perception=="exteroception" else "exteroception"
	camera_locked=true;camera_offset=Vector2.ZERO;intero_rotation=0;camera_rotation=0
	manual_zoom=clampf(manual_zoom,MIN_ZOOM,_maximum_zoom());camera_zoom=manual_zoom;focus_animating=false
	if build_open:observation_view={"zoom":manual_zoom,"locked":true,"free":_follow_cell().position,"offset":Vector2.ZERO}
	if perception=="interoception" and world.resident!=null and can_follow() and _follow_cell().chemistry.accelerator==null:
		world.resident.gpu.attach_cytoplasm(_follow_cell().chemistry,_follow_cell())
	touch_zoom.cancel()
	for view in views.values():view.seen_revision=-1;view._queue_body_redraw()
	_update_world(1.0 if is_paused() else Engine.get_physics_interpolation_fraction())
	touch_zoom.layout();_update_perception_menu()

func can_follow() -> bool:
	return _follow_cell()!=null and not _follow_cell().dead

func _cell_render_alpha(cell,alpha: float) -> float:
	# Server activity tiers do not determine the browser's snapshot interpolation.
	return alpha if cell.activity>0 or world.remote_client else 1.0

func _update_world(alpha: float) -> void:
	preload("res://scripts/motile_art.gd").set_clock(ui_time)
	var canvas_scale:=get_viewport().get_final_transform().get_scale().abs()
	detail_canvas_scale=maxf(.001,minf(canvas_scale.x,canvas_scale.y))
	var sync_start := Time.get_ticks_usec() if frame_trace != null else 0
	var size := get_viewport_rect().size
	var base_zoom := minf(size.x/Simulation.VIEW.x,size.y/Simulation.VIEW.y)
	_track_player_death()
	if not diagnostic_zoom: manual_zoom = clampf(manual_zoom,MIN_ZOOM,_maximum_zoom())
	if not focus_animating: camera_zoom = manual_zoom
	zoom = base_zoom*camera_zoom
	if diagnostic_zoom: zoom *= minf(1.0,150.0/world.player.radius)
	if not diagnostic_zoom: zoom = maxf(zoom,base_zoom*MIN_ZOOM)
	scale_bar.configure(size,zoom,preferences.hud_scale)
	camera_screen = size*0.5
	var followed=_follow_cell()
	if camera_followed_id!=-1 and followed.id!=camera_followed_id:_ease_camera()
	camera_followed_id=followed.id
	follow_heading=lerp_angle(followed.previous_angle,followed.angle,_cell_render_alpha(followed,alpha))
	follow_origin=followed.previous_position+Simulation.Medium.offset(followed.previous_position,followed.position)*_cell_render_alpha(followed,alpha)
	if perception=="interoception":
		camera_locked=true;camera_rotation=intero_rotation-follow_heading
	if death_focus_age<death_view.LIFETIME:
		var blend: float=smoothstep(1.15,death_view.LIFETIME,death_focus_age)
		var fit: float=minf(size.x,size.y)/(3.6*maxf(1,death_focus_extent))
		zoom=lerpf(minf(zoom,fit),zoom,blend)
		camera_rotation=lerp_angle(death_focus_rotation,camera_rotation,blend)
		scale_bar.configure(size,zoom,preferences.hud_scale)
	world.view_half = _camera_bounds(size/(2*zoom))
	if world.resident!=null:
		world.resident.detail_half=_camera_bounds(size/(2*base_zoom*MIN_ZOOM))
		if world.resident.streaming!=null:
			zoom=maxf(zoom,world.resident.streaming.minimum_zoom(size))
			world.view_half=_camera_bounds(size/(2*zoom))
			scale_bar.configure(size,zoom,preferences.hud_scale)

	render_camera=follow_origin+(camera_offset.rotated(follow_heading) if perception=="interoception" else camera_offset) if camera_locked else free_camera

	if death_focus_age < 1.8:
		var blend: float = smoothstep(1.15,1.8,death_focus_age)
		render_camera = Simulation.Medium.wrap_position(death_focus_at+Simulation.Medium.offset(death_focus_at,render_camera)*blend)
	var pose: Dictionary=camera_motion.sample(render_camera,camera_rotation,zoom)
	render_camera=pose.at;render_rotation=pose.heading;zoom=pose.zoom;camera_has_pose=true
	world.view_half=_camera_bounds(size/(2*zoom))
	scale_bar.configure(size,zoom,preferences.hud_scale)
	world.camera_follows_player = camera_locked and death_focus_age >= 1.8 and camera_offset.length_squared() < 0.001 and not camera_motion.active
	if world.resident!=null and world.resident.streaming!=null:
		var prepared: Vector2=world.resident.streaming.request_view(render_camera)
		if Simulation.Medium.offset(render_camera,prepared).length_squared()>.01: world.camera_follows_player=false
		render_camera=prepared
	world.camera_position = render_camera
	light_layer.material.set_shader_parameter("clock",world.time)
	light_layer.material.set_shader_parameter("camera",render_camera)
	light_layer.material.set_shader_parameter("camera_rotation",render_rotation)
	light_layer.material.set_shader_parameter("view_size",size/zoom)
	light_layer.material.set_shader_parameter("screen_center",camera_screen/size)
	microscope_layer.material.set_shader_parameter("camera",render_camera)
	microscope_layer.material.set_shader_parameter("camera_rotation",render_rotation)
	microscope_layer.material.set_shader_parameter("view_size",size/zoom)
	microscope_layer.material.set_shader_parameter("screen_center",camera_screen/size)
	preview.position = Simulation.Medium.offset(render_camera,world.player.position)
	world_layer.position = camera_screen
	world_layer.scale = Vector2.ONE*zoom
	world_layer.rotation = render_rotation
	currents.position = Simulation.Medium.offset(render_camera,currents_origin)
	habitat_view.sync(render_camera,world.view_half)
	currents.visible = not flow_streamers
	flow_view.mobile_quality=touch_zoom.enabled
	flow_view.sync(world,render_camera,world.view_half,zoom,flow_streamers,flow_wakes)
	reaction_view.sync(world,render_camera,world.view_half,zoom,show_reaction_sparks and perception=="exteroception")
	merge_view.sync(world,render_camera,death_frame_dt,alpha)
	death_view.sync(world,render_camera,zoom,death_frame_dt)
	death_frame_dt = 0
	# Cached glyph variants preserve facing while dropping subpixel embellishment.
	for kind in batches.size():
		var simplified := int(2*Simulation.particle_radius(kind)*zoom < 6)
		if particle_lod[kind] != simplified:
			particle_lod[kind] = simplified
			batches[kind].texture = ParticleArt.texture(kind,bool(simplified))
	if frame_trace != null: frame_trace.work("field_sync",Time.get_ticks_usec()-sync_start)
	var particle_start := Time.get_ticks_usec() if frame_trace != null else 0
	_sync_particles(alpha)
	if frame_trace != null: frame_trace.work("particle_sync",Time.get_ticks_usec()-particle_start)
	var cells_start := Time.get_ticks_usec() if frame_trace != null else 0
	var alive_ids: Dictionary = {}
	_refresh_merge_candidates()
	for cell in world.cells:
		if cell.dead: continue
		var fraction: float = _cell_render_alpha(cell,alpha)
		var p: Vector2 = cell.previous_position+Simulation.Medium.offset(cell.previous_position,cell.position)*fraction
		var offset: Vector2 = Simulation.Medium.offset(render_camera,p)
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
		views[cell.id].z_index=8 if merge_selecting() and cell==world.player else 9 if merge_selecting() and merge_candidates.has(cell.id) else 2 if merge_selecting() else 6 if cell == world.player or internal_visible(cell) else 4 if cell.lineage_id() == world.lineage.root_id else 2
		views[cell.id].cell = cell
		var heading := lerp_angle(cell.previous_angle,cell.angle,fraction)
		views[cell.id].sync(Simulation.Medium.offset(render_camera,p),heading,zoom,world.activity_for_cell(cell))
	for identity in views.keys():
		if not alive_ids.has(identity):
			views[identity].queue_free()
			views.erase(identity)
	proboscis_feeding_art.sync()
	_flush_cell_rasters()
	# Local factories remain above membrane attachments in either perception.
	cell_ui.interior.z_index=8
	cell_ui.interior.sync()
	perception_mask.sync()
	nameplates.sync(alpha)
	if frame_trace != null: frame_trace.work("cell_sync",Time.get_ticks_usec()-cells_start)

func _flush_cell_rasters() -> void:
	# Coalesce changing anatomy to its newest appearance and spread texture work.
	# Body transforms, input, masks and authoritative state never wait here.
	var budget:=6
	for identity in pending_cell_rasters.keys():
		var view=pending_cell_rasters[identity].get_ref()
		pending_cell_rasters.erase(identity)
		if not is_instance_valid(view) or view.is_queued_for_deletion() or not view.raster_active:continue
		view.refresh_raster()
		budget-=1
		if budget==0:break

func _sync_particles(alpha: float = 1.0) -> void:
	if perception=="interoception":
		for batch in batches:batch.visible=false
		if resident_view!=null:resident_view.visible=false
		return
	for batch in batches:batch.visible=true
	if world.resident!=null and resident_view!=null:
		for batch in batches: batch.visible=false
		resident_view.visible=true;resident_view.camera(render_camera)
		return
	if resident_view!=null: resident_view.visible=false
	for batch in batches: batch.visible=true
	if world.native_render:
		var capacities := PackedInt32Array()
		for batch in batches: capacities.append(batch.multimesh.instance_count)
		var result: Array = world.kernels.render_particles(world.particles,world.visible_particle_ids(30),world.cells,render_camera,world.view_half,alpha,world.revision,capacities,world.native_particle_render_cache and not is_paused(),preload("res://scripts/signal_colors.gd").native_style(self))
		for kind in Simulation.SPECIES_COUNT:
			buffers[kind] = result[kind]
			var count: int = result[-1][kind]
			var capacity: int = result[kind].size()/12
			if batches[kind].multimesh.instance_count != capacity: batches[kind].multimesh.instance_count = capacity
			if count > 0: batches[kind].multimesh.buffer = buffers[kind]
			batches[kind].multimesh.visible_instance_count = count
		return
	if world.spatial_queries: world.cell_index.rebuild(world.cells)
	var counts := PackedInt32Array()
	counts.resize(Simulation.SPECIES_COUNT)
	for index in world.visible_particle_ids(30):
		var p: Dictionary = world.particle_snapshot(index)
		if not p.alive: continue
		var at: Vector2 = p.p
		if p.get("updated",-1) == world.revision: at = p.previous+Simulation.Medium.offset(p.previous,p.p)*alpha
		if p.kind != Simulation.PHEROMONE: at = _visible_particle_position(at,alpha)
		at = Simulation.Medium.offset(render_camera,at)
		if absf(at.x)>world.view_half.x+20 or absf(at.y)>world.view_half.y+20: continue
		var kind: int = p.kind
		var slot: int = counts[kind]
		if slot >= batches[kind].multimesh.instance_count:
			batches[kind].multimesh.instance_count *= 2
			buffers[kind].resize(batches[kind].multimesh.instance_count*12)
		var color := Color.WHITE
		color.a = 0.6 if kind==Simulation.OXYGEN else 1.0
		if kind==Simulation.PHEROMONE:color=preload("res://scripts/signal_colors.gd").family(self,preload("res://scripts/signal_colors.gd").root(p))
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
		var fraction: float = _cell_render_alpha(cell,alpha)
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
	if not build_open or (selected < 0 and moving_id < 0): return
	var cell = world.player
	var heading:=_player_heading()
	if views.has(cell.id):preview.position=views[cell.id].position
	var relative := _player_relative(get_global_mouse_position())
	var a: float = placement_angle if placement_keyboard else cell.surface_parameter(relative.angle()-heading)
	var local: Vector2 = cell.local_point(a)
	var organ: Dictionary = cell.organ_by_id(moving_id)
	var size: float = organ.scale if not organ.is_empty() else 1.0
	var kind: String = organ.kind if not organ.is_empty() else Simulation.KINDS[selected]
	var normal: Vector2 = cell.local_normal(a)
	var point: Vector2 = cell.organ_local_position({"kind":kind,"a":a,"scale":size}).rotated(heading)
	var fits: bool = moving_id >= 0 or (cell.can_fit(kind,a,1,false) and world.player.biomass >= cell.construction_price(kind))
	Visuals.icon(preview,point,kind,normal.angle()+heading,size,ui_time)
	preview.draw_arc(point,22*size,0,TAU,32,MINT if fits else Color("fc8c90"),2/zoom,true)
	if selected >= 0:
		var outline: PackedVector2Array = cell.membrane.outline()
		var contour := PackedVector2Array()
		for vertex in outline: contour.append(vertex.rotated(heading))
		contour.append(contour[0])
		preview.draw_polyline(contour,Color(0.6,1,0.85,0.6) if fits else Color(1,0.6,0.65,0.65),1.5/zoom,true)

func _size_touch_settings(node: Node,height: float) -> void:
	for child in node.get_children():
		if child is Button or child is Slider:child.custom_minimum_size.y=height
		_size_touch_settings(child,height)

func _refresh_light_texture() -> void:
	const LightField=preload("res://scripts/light_field.gd")
	var values:=PackedByteArray();values.resize(LightField.COLS*LightField.ROWS)
	for y in LightField.ROWS:
		for x in LightField.COLS:
			values[y*LightField.COLS+x]=roundi(world.light_at(Vector2(x+0.5,y+0.5)*LightField.SIZE)*255)
	# Normalized R8 keeps linear filtering portable on phone WebGL renderers.
	light_texture=ImageTexture.create_from_image(Image.create_from_data(LightField.COLS,LightField.ROWS,false,Image.FORMAT_R8,values))
	light_layer.material.set_shader_parameter("light_map",light_texture)
	var illumination_scale: float=(0.5 if world.habitat==1 else 1.25 if world.habitat==2 else 1.0)*float(world.environment.get("light",world.evolution.light_factor))
	light_layer.material.set_shader_parameter("illumination_scale",illumination_scale)
	microscope_layer.material.set_shader_parameter("light_map",light_texture)


func _player_heading() -> float:
	return views[world.player.id].rotation if views.has(world.player.id) else world.player.angle

func _player_relative(screen: Vector2) -> Vector2:
	var origin: Vector2=views[world.player.id].position if views.has(world.player.id) else Simulation.Medium.offset(render_camera,world.player.position)
	return (screen-camera_screen).rotated(-render_rotation)/zoom-origin

func _ease_camera() -> void:
	if camera_has_pose:camera_motion.begin(render_camera,render_rotation,zoom)

func _direct_camera() -> void:
	if not camera_motion.active:return
	if perception=="interoception":
		camera_offset=Simulation.Medium.offset(follow_origin,render_camera).rotated(-follow_heading)
		intero_rotation=render_rotation+follow_heading
	elif camera_locked:camera_offset=Simulation.Medium.offset(follow_origin,render_camera)
	else:free_camera=render_camera
	camera_rotation=render_rotation
	var size:=get_viewport_rect().size
	manual_zoom=zoom/maxf(.0001,minf(size.x/Simulation.VIEW.x,size.y/Simulation.VIEW.y));camera_zoom=manual_zoom
	camera_motion.cancel();focus_animating=false

func _toggle_camera() -> void:
	_ease_camera()
	if perception=="interoception":
		camera_locked=true;camera_offset=Vector2.ZERO;intero_rotation=0
		_update_world(1);touch_zoom.layout();return
	if not camera_locked and not can_follow():
		_message("There is currently no living cell to follow.");touch_zoom.layout();return
	if camera_locked:
		free_camera=Simulation.Medium.wrap_position(render_camera);camera_rotation=render_rotation;camera_motion.cancel()
	camera_locked = not camera_locked
	if camera_locked: camera_offset = Vector2.ZERO;camera_rotation=0
	camera_dragging = false
	touch_zoom.cancel()
	_update_world(1.0 if is_paused() else Engine.get_physics_interpolation_fraction())
	touch_zoom.layout()
	currents.queue_redraw()
	_update_hud()

func _screen_world(screen: Vector2) -> Vector2:
	return Simulation.Medium.wrap_position(render_camera+(screen-camera_screen).rotated(-render_rotation)/zoom)

func _world_screen(at: Vector2) -> Vector2:
	return camera_screen+Simulation.Medium.offset(render_camera,at).rotated(render_rotation)*zoom

func _camera_bounds(half: Vector2) -> Vector2:
	var c:=absf(cos(render_rotation));var s:=absf(sin(render_rotation))
	return Vector2(c*half.x+s*half.y,s*half.x+c*half.y).min(Simulation.Medium.WORLD*.5)

func _cell_frame_point(at: Vector2) -> Vector2:
	return Simulation.Medium.offset(follow_origin,at).rotated(-follow_heading)

func _camera_gesture(anchor_a: Vector2,anchor_b: Vector2,screen_a: Vector2,screen_b: Vector2) -> void:
	var source:=anchor_b-anchor_a;var target:=screen_b-screen_a
	if source.length_squared()<.000001 or target.length_squared()<1:return
	camera_motion.cancel()
	focus_animating=false
	var turn:=wrapf(target.angle()-source.angle(),-PI,PI)
	var size:=get_viewport_rect().size
	var base:=minf(size.x/Simulation.VIEW.x,size.y/Simulation.VIEW.y)
	manual_zoom=clampf(target.length()/source.length()/base,MIN_ZOOM,_maximum_zoom())
	var center: Vector2=(anchor_a+anchor_b)*.5
	var screen_center: Vector2=(screen_a+screen_b)*.5
	var offset: Vector2=center-(screen_center-size*.5).rotated(-turn)/(base*manual_zoom)
	if perception=="interoception":
		camera_locked=true;intero_rotation=turn;camera_offset=offset
	else:
		camera_locked=false;camera_offset=Vector2.ZERO;camera_rotation=turn
		free_camera=Simulation.Medium.wrap_position(offset)
	_update_world(1.0 if is_paused() else Engine.get_physics_interpolation_fraction())
	currents.queue_redraw()

func _update_perception_menu() -> void:
	if perception_menu_button!=null:
		perception_menu_button.text=("Internal" if perception=="exteroception" else "External")+" [I]"

func lineage_color(root_id: int) -> String:
	for row in lineage_names:
		if row.root==root_id:return str(row.get("color",""))
	return ""
func _submit_lineage_color(_color: String) -> String:
	return "Connect to the shared pond to save a lineage color."

func _submit_profile(_name: String,_favorite: String="") -> String:
	return "Connect to the shared pond to save a player name."

func _submit_feedback(_report: Dictionary) -> String:
	return "Connect to the shared pond to submit feedback. Your draft is kept."

func _toggle_settings() -> void:
	if merge_selecting():_end_merge_selection()
	_update_perception_menu()
	settings_panel.visible = not settings_panel.visible
	tube_start.clear()
	camera_dragging = false
	if settings_panel.visible: cell_ui.close_context()
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
	ui.add_child(cell_ui)
	cell_ui.initialize(self)
	ui.add_child(inspector)
	inspector.initialize(self)
	inspector.z_index = 30
	ui.add_child(debug_label)
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.add_theme_color_override("font_outline_color",Color("142540"))
	debug_label.add_theme_constant_override("outline_size",5)
	feedback.initialize(self);profile.initialize(self);palette.initialize(self);nameplates.initialize(self);player_help.initialize(self)
	var options_box := _panel_box(settings_panel)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_box.add_child(settings_scroll)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation",12)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(options)
	_label(options,"SETTINGS [M]",MINT)
	profile_menu_button=_button(options,"Player name",profile.open)
	palette_menu_button=_button(options,"Lineage color",palette.open)
	feedback_menu_button=_button(options,"Feature request / Bug report",feedback.open)
	gameplay_menu_button=_button(options,"Gameplay",player_help.open.bind("gameplay"))
	mechanics_menu_button=_button(options,"Mechanics",player_help.open.bind("mechanics"))
	_label(options,"Current display")
	var current_styles:=current_style_choices;current_styles.columns=2;options.add_child(current_styles)
	var current_group:=ButtonGroup.new()
	crest_style_button=_button(current_styles,"Wave crests",set_current_style.bind("crests"))
	streamline_style_button=_button(current_styles,"Streamlines",set_current_style.bind("streamlines"))
	for button in [crest_style_button,streamline_style_button]:
		button.toggle_mode=true;button.button_group=current_group;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	crest_style_button.set_pressed_no_signal(preferences.current_style=="crests")
	streamline_style_button.set_pressed_no_signal(preferences.current_style=="streamlines")
	_label(options,"Text and interaction size")
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
	options.add_child(ripple_check)
	ripple_check.text = "Background shimmer"
	ripple_check.set_pressed_no_signal(preferences.water_ripples)
	ripple_check.toggled.connect(set_water_ripples)
	var music_label := _label(options,"Music volume · %d%%" % roundi(preferences.music_volume*100))
	music_slider.max_value = 100
	music_slider.step = 1
	music_slider.value = preferences.music_volume*100
	options.add_child(music_slider)
	music_slider.value_changed.connect(func(value):
		preferences.music_volume = value/100
		music_label.text = "Music volume · %d%%" % roundi(value)
		preferences.save_settings())
	perception_menu_button=_button(options,"Internal [I]",_toggle_perception)
	perception_menu_button.tooltip_text="Switch between the cell interior and the surrounding water"
	_button(options,"Sense view [S]",func(): show_senses = not show_senses)
	_button(options,"Performance overlay [F3]",func(): show_debug = not show_debug)
	if not world.remote_client:_button(options,"Next habitat [H]",func(): _restart((world.habitat+1)%3))
	_button(options,"Family history",func():
		settings_panel.hide()
		cell_ui.open_context({"kind":"lineage"}))
	if world.remote_client:_button(options,"Start new lineage",_request_new_lineage)
	else:_button(options,"New expedition [R]",func(): _restart())
	ui.add_child(lineage_confirmation)
	lineage_confirmation.title="Start a new lineage?"
	lineage_confirmation.dialog_text="Your current family will stay in the pond and live under computer control. You will begin with a new cell. The shared pond will continue."
	lineage_confirmation.ok_button_text="Start new lineage"
	lineage_confirmation.confirmed.connect(_start_new_lineage)
	settings_help=_label(options,"Tab: enter cell / keep edits and resume\nClick factories, nucleus, bud or installed organs\nNew organs have a fixed size · no Undo\nRight-click: cancel a held organ or close choices\nMicrotubules are sampled per cell\nWheel elsewhere: zoom · middle-drag: pan\nSpace: follow/free outside · recenter inside\nM: open / close settings\nI: Internal / External · inside zoom up to 120×\n[ / ]: cycle cell targets · Enter: choose / place\nArrow keys: navigate choices or membrane placement\nHover particles: inspect through a local lens\nNo movement keys: anatomy steers.",MUTED)
	_button(options,"Resume / Close [M]",func():
		if touch_zoom.enabled and user_paused:_toggle_user_pause()
		else:_toggle_settings())
	options_box.add_child(HSeparator.new())
	options_box.add_child(session_controls)
	session_controls.add_child(quit_button)
	quit_button.text = "Close game"
	quit_button.pressed.connect(func(): get_tree().quit())
	settings_panel.hide()
	touch_zoom.initialize(self)

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
	var closest := 0
	for i in Preferences.SCALES.size():
		if absf(Preferences.SCALES[i]-preferences.hud_scale) < absf(Preferences.SCALES[closest]-preferences.hud_scale): closest = i
	scale_select.select(closest)
	preferences.save_settings()
	_update_hud()
	_layout()
	_layout.call_deferred()

func _layout_water(size: Vector2) -> void:
	if not OS.has_feature("web") or not touch_zoom.enabled or not water_cache_enabled:
		if water_target!=null:
			if light_layer.get_parent()!=self:light_layer.reparent(self,false);move_child(light_layer,world_layer.get_index())
			water_target.render_target_update_mode=SubViewport.UPDATE_DISABLED;water_display.hide()
		light_layer.size=size;return
	if water_target==null:
		water_target=SubViewport.new();water_target.disable_3d=true;water_target.world_2d=World2D.new()
		water_target.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(water_target)
		water_display=TextureRect.new();water_display.mouse_filter=Control.MOUSE_FILTER_IGNORE
		water_display.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		water_display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;water_display.texture=water_target.get_texture()
		add_child(water_display);move_child(water_display,world_layer.get_index())
		light_layer.reparent(water_target,false)
	if light_layer.get_parent()!=water_target:light_layer.reparent(water_target,false)
	water_display.show();water_target.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	# One sample per CSS pixel is enough for diffuse water, retaining full-resolution
	# foreground, controls and the exact approved shader/pH palette.
	water_target.size=Vector2i((size/maxf(1,touch_zoom.pixels)).ceil()).max(Vector2i.ONE)
	light_layer.size=Vector2(water_target.size);water_display.size=size

func _layout() -> void:
	var size := get_viewport_rect().size
	current_style_choices.columns=1 if touch_zoom.enabled else 2
	touch_zoom.layout()
	_layout_water(size)
	microscope_layer.size = size
	var density: float=touch_zoom.pixels if touch_zoom.enabled else 1.0
	var margin:=16*density
	var width := minf(530*preferences.hud_scale*density,size.x-margin*2)
	var top: float=60*density if touch_zoom.enabled else margin
	settings_panel.position = Vector2(size.x-width-margin,top)
	settings_panel.size = Vector2(width,size.y-top-margin)
	if touch_zoom.enabled and ui.theme!=null:
		var mobile_theme: Theme=ui.theme.duplicate()
		mobile_theme.default_font_size=roundi(18*preferences.hud_scale*density)
		settings_panel.theme=mobile_theme
		if settings_help!=null:settings_help.text="Tap factories, nucleus, bud or organelles.\nDouble-tap a family cell to switch to it.\nTwo fingers drag, twist and pinch the camera.\nTap the held icon at top left to cancel placement.\nTap particles for names and details below.\nPause opens settings; the shared pond continues.\nAnatomy steers the cell."
		_size_touch_settings(settings_panel,40*preferences.hud_scale*density)
	else:settings_panel.theme=null
	preview.queue_redraw()

func set_particle_collisions(on: bool) -> void:
	# Explicit profiling comparison only; ordinary starts/restarts keep collisions.
	world.particle_collisions = on

func set_current_style(style: String) -> void:
	if style not in ["crests","streamlines"]:return
	preferences.current_style=style
	flow_view.use_crests=style=="crests"
	crest_style_button.set_pressed_no_signal(style=="crests")
	streamline_style_button.set_pressed_no_signal(style=="streamlines")
	preferences.save_settings()

func set_water_ripples(on: bool) -> void:
	preferences.water_ripples = on
	light_layer.material.set_shader_parameter("water_ripples",on)
	ripple_check.set_pressed_no_signal(on)
	preferences.save_settings()

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

func _debug_population_lines() -> String:
	if world.resident!=null:
		var census: Dictionary=world.habitat_census()
		return "\nDetailed region: %d cells · Coarse: %d cells\nHabitat total: %d living cells / %d particles\nGPU resident: %d · Offscreen: %d · Queued: %d" % [world.active_cells,world.resident.coarse_cells,census.living_cells,census.total,census.gpu,census.cold,census.pending]
	var now:=Time.get_ticks_usec()
	if debug_census_cache.is_empty() or now-debug_census_usec>=1000000:
		debug_census_cache=world.habitat_census();debug_census_usec=now
	return "\nDetailed region: %d cells / %d particles\nHabitat total: %d living cells / %d particles" % [world.active_cells,world.active_particles,debug_census_cache.living_cells,debug_census_cache.total]

func _update_hud() -> void:
	var light: float=float(world.environment.get("light",world.evolution.light_factor))
	if absf(light-light_factor_shown) > 0.02:
		_refresh_light_texture()
		light_factor_shown = light
	if acidity_texture.get_width() > 0: acidity_texture.update(Image.create_from_data(64,40,false,Image.FORMAT_RF,world.acidity.values.to_byte_array()))
	debug_label.visible = show_debug and not settings_panel.visible
	var backend := "Resident GPU + native cells" if world.resident != null and world.kernels != null else "Resident GPU + SCRIPT cells" if world.resident != null else "GPU experiment" if world.gpu_transport != null else "Native CPU" if world.kernels != null else "GDScript"
	debug_label.text = "%s · %d FPS · frame %.1f ms\n%d ticks/frame · simulation %.1f ms/frame · tick %.2f ms\nSimulation/wall %.2f× · view sync %.2f ms" % [backend,Engine.get_frames_per_second(),last_frame_ms,last_frame_ticks,last_frame_sim_ms,simulation_ms,simulation_rate,render_ms]
	if show_debug:debug_label.text += _debug_population_lines()+"\nLocal water: pH %.1f" % world.acidity.ph_at(_follow_cell().position)
	if show_debug:
		var census: Dictionary = world.visible_particle_census()
		debug_label.text += "\nOn screen: %d material packets · %d chemical packets · %d signals\nCytoplasm (this cell): %d particles" % [census.material,census.chemicals,census.signals,world.player.chemistry.particle_count()]
	if world.resident != null:
		var p: Dictionary = world.profile_usec
		debug_label.text += "\nTick: flow %.1f · particles %.1f · biology %.1f · motion %.1f · exposure %.1f ms\nGPU receipts: prepare %.1f · handoff %.1f ms" % [p.get("fluid",0)/1000.0,p.get("particles",0)/1000.0,p.get("biology",0)/1000.0,p.get("motion",0)/1000.0,p.get("ecology",0)/1000.0,p.get("gpu_receipt_prepare",0)/1000.0,p.get("gpu_receipt_wait",0)/1000.0]
	if music.ready_bank: debug_label.text += "\nMusic mix %.2f ms · underruns %d" % [music.render_usec/1000.0,music.skips]
	debug_label.position = Vector2(16,16 if not build_open else 52*preferences.hud_scale)
	debug_label.add_theme_font_size_override("font_size",roundi(15*preferences.hud_scale))


func _toggle_build() -> void:
	if merge_selecting():_end_merge_selection()
	if user_paused:_message("Resume before editing the cell.");return
	if death_focus_age < 1.8: return
	if settings_panel.visible or world.player.dead or world.evolution.terminal(): return
	if build_open:
		_finish_build()
		return
	observation_view = {"zoom":manual_zoom,"locked":camera_locked,"free":free_camera,"offset":camera_offset}
	_ease_camera()
	world.begin_build()
	build_open = true
	camera_locked = true
	camera_offset = Vector2.ZERO
	var size := get_viewport_rect().size
	var fit := minf(size.x/Simulation.VIEW.x,size.y/Simulation.VIEW.y)
	camera_zoom = zoom/maxf(0.001,fit)
	manual_zoom = clampf(minf(size.x,size.y)*0.28/(world.player.radius*fit),MIN_ZOOM,_maximum_zoom())
	focus_animating = true
	selected = -1
	moving_id = -1
	shape_preview_ticks = 0
	tube_start.clear()
	cell_ui.close_context()
	cell_ui.keyboard_target.clear()
	_layout()

func _finish_build() -> void:
	_ease_camera()
	world.commit_build()
	build_open = false
	selected = -1
	moving_id = -1
	tube_start.clear()
	tube_group = -1
	shape_preview_ticks = 0
	cell_ui.close_context()
	cell_ui.keyboard_target.clear()
	if not observation_view.is_empty():
		manual_zoom = observation_view.zoom
		camera_locked = observation_view.locked
		free_camera = observation_view.free
		camera_offset = observation_view.offset
		focus_animating = true
		observation_view.clear()
	_layout()

func placement_status() -> String:
	if selected < 0: return ""
	if world.player.biomass < world.player.construction_price(Simulation.KINDS[selected]): return "Needs %d biomass." % world.player.construction_price(Simulation.KINDS[selected])
	if not world.player.can_fit(Simulation.KINDS[selected],0,1,false): return "Needs more membrane area."
	var place: String="inside the cell" if world.player.internal_organ(Simulation.KINDS[selected]) else "the membrane"
	return "Tap "+place+" · tap the held icon to cancel." if touch_zoom.enabled else "Click "+place+" · right-click cancels."

func _placement_hit(relative: Vector2) -> bool:
	var organ: Dictionary=world.player.organ_by_id(moving_id)
	var kind: String=organ.get("kind","") if moving_id>=0 else Simulation.KINDS[selected] if selected>=0 else ""
	var reach: float=world.player.support(relative.angle()-_player_heading()+world.player.angle)
	var pad: float=maxf(16,32*cell_ui.ui_scale()/zoom)
	if world.player.internal_organ(kind):return relative.length()<=reach+pad
	return absf(relative.length()-reach)<=pad

func _place_at(angle: float) -> bool:
	if moving_id >= 0:
		var moved: bool = world.edit("move",{"id":moving_id,"angle":angle})
		moving_id = -1
		if not moved and not world.remote_client:_message("That organ is no longer available.","error")
		return moved
	if selected < 0: return false
	var kind: String=Simulation.KINDS[selected]
	var placed: bool = world.install(kind,angle,"flee" if selected == 5 else "graze",1.0)
	if placed and not world.remote_client:placement_feedback.begin(world.player,kind,angle,false)
	if not placed and not world.remote_client:_message(placement_status(),"error")
	return placed

func _zoom_button(factor: float) -> void:
	_ease_camera()
	_zoom_at(camera_screen,factor)

func _zoom_at(screen: Vector2, factor: float) -> void:
	var before: Vector2=_cell_frame_point(_screen_world(screen)) if perception=="interoception" else _screen_world(screen)
	manual_zoom=clampf(manual_zoom*factor,MIN_ZOOM,_maximum_zoom());focus_animating=false
	if camera_locked and perception!="interoception":camera_offset=Vector2.ZERO
	_update_world(1.0 if is_paused() else Engine.get_physics_interpolation_fraction())
	var after: Vector2=_cell_frame_point(_screen_world(screen)) if perception=="interoception" else _screen_world(screen)
	if perception=="interoception":camera_offset+=before-after
	elif not camera_locked:free_camera=Simulation.Medium.wrap_position(free_camera+Simulation.Medium.offset(after,before))
	_update_world(1.0 if is_paused() else Engine.get_physics_interpolation_fraction())
	currents.queue_redraw()

func _select(index: int) -> void:
	if settings_panel.visible or world.player.dead or world.evolution.terminal(): return
	if index<0 or index>=Simulation.KINDS.size():return
	if not build_open: _toggle_build()
	if not build_open:return
	cell_ui.close_context()
	cell_ui.keyboard_target.clear()
	moving_id = -1
	selected = index
	_prepare_placement(Simulation.KINDS[index])
	placement_keyboard = false
	tube_start.clear()

func _prepare_placement(kind: String) -> void:
	# Internal placement enters the existing attached/eased camera frame.
	if world.player.internal_organ(kind) and perception!="interoception":
		_toggle_perception()

func _request_new_lineage() -> void:
	if not world.remote_client or lineage_confirming:return
	if OS.has_feature("web"):
		JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/player_readers.js"),true)
		lineage_confirming=true;JavaScriptBridge.eval("window.primordiaReaders.openLineage()")
	else:
		lineage_confirmation.popup_centered(Vector2i(mini(520,int(get_viewport_rect().size.x)-32),220))

func _start_new_lineage() -> void:
	pass # Only the authenticated multiplayer client supplies this action.

func _restart(profile: int = -1) -> void:
	if merge_selecting():_end_merge_selection(false)
	user_paused=false;touch_zoom.cancel()
	archive.sync(world)
	archive.begin()
	if resident_controller!=null: resident_controller.close()
	elif world.resident!=null: world.resident.close()
	if world.gpu_transport != null: world.gpu_transport.close()
	resident_controller=null;resident_starting=false
	world = Simulation.new(world.seed_value,world.habitat if profile < 0 else profile)
	world.enable_ambient_carbon()
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
	camera_zoom = 1
	camera_rotation = 0
	focus_animating = false
	camera_offset = Vector2.ZERO
	observation_view.clear()
	moving_id = -1
	cell_ui.reset()
	music.reset()
	tube_start.clear()
	tube_group = -1
	shape_preview_ticks = 0
	_layout()
	_message("New expedition · family history and known blueprints retained.\nBuild, feed and grow your family.")

func waiting_for_world() -> bool:
	return false

func _message(value: String,tone: String="info") -> void:
	notice = value
	notice_timer = 1.0
	cell_ui.status_feed.push(value,tone)

func touch_controls_available() -> bool:
	return true

func _cancel_placement() -> void:
	selected=-1;moving_id=-1;tube_start.clear()
	cell_ui.close_context()

func _mobile_pause_menu() -> void:
	if not pause_control_ready:return
	if user_paused:
		_toggle_user_pause()
	else:
		_toggle_user_pause()
		if not settings_panel.visible:_toggle_settings()

func _toggle_user_pause() -> void:
	if not pause_control_ready:return
	user_paused=not user_paused
	if not user_paused:
		settings_panel.hide()
		if build_open:_finish_build()
		cell_ui.close_context()
	touch_zoom.cancel();touch_zoom.layout()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:touch_zoom.cancel()

func _input(event: InputEvent) -> void:
	if feedback.opened or profile.opened or palette.opened or player_help.opened or lineage_confirming:return
	if cell_ui.family_picker.handle_touch(event):get_viewport().set_input_as_handled();return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if touch_zoom.handle(event):get_viewport().set_input_as_handled()
		return
	if touch_zoom.enabled and (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device==-1:return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and build_open and not settings_panel.visible:
		if selected >= 0 or moving_id >= 0 or not cell_ui.context.is_empty():
			selected = -1
			moving_id = -1
			cell_ui.close_context()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion: placement_keyboard = false
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == camera_button: camera_dragging = false
		if event.button_index == MOUSE_BUTTON_LEFT and not tube_start.is_empty():
			if not _can_edit_tubules() or get_viewport().gui_get_hovered_control() != null: tube_start.clear()
			else: _unhandled_input(event)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if settings_panel.visible and event.keycode not in [KEY_M,KEY_F11,KEY_F3,KEY_I]: return
		match event.keycode:
			KEY_TAB: _toggle_build()
			KEY_ENTER,KEY_KP_ENTER:
				if not build_open: return
				if selected >= 0 or moving_id >= 0:
					placement_keyboard = true
					_place_at(placement_angle)
				elif not cell_ui.activate_keyboard(): _finish_build()
			KEY_BRACKETLEFT,KEY_BRACKETRIGHT:
				if not build_open: return
				cell_ui.cycle_target(-1 if event.keycode == KEY_BRACKETLEFT else 1)
			KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN:
				if not build_open or (selected < 0 and moving_id < 0): return
				placement_keyboard = true
				placement_angle = fposmod(placement_angle+(-0.10 if event.keycode in [KEY_LEFT,KEY_UP] else 0.10),TAU)
			KEY_P: _toggle_user_pause()
			KEY_I: _toggle_perception()
			KEY_SPACE: _toggle_camera()
			KEY_M: _toggle_settings()
			KEY_F11: set_fullscreen(not preferences.fullscreen)
			KEY_F3: show_debug = not show_debug; _update_hud()
			KEY_S: show_senses = not show_senses
			KEY_F: _select(4)
			KEY_C: _select(5)
			KEY_V: _select(10)
			KEY_0: _select(9)
			KEY_H:
				if not world.remote_client:_restart((world.habitat+1)%3)
			KEY_R:
				if world.remote_client:_request_new_lineage()
				else:_restart()
			_:
				if event.keycode >= KEY_1 and event.keycode <= KEY_9: _select(event.keycode-KEY_1)
				else: return
		get_viewport().set_input_as_handled()

func merge_selecting() -> bool:return not merge_selection.is_empty()

func _refresh_merge_candidates() -> void:
	merge_candidates.clear()
	if not merge_selecting():return
	if world.remote_client:
		if int(merge_available.get("cell",-1))!=world.player.id:return
		for id in merge_available.get("targets",{}):
			if float(merge_available.targets[id])>world.time and world.cells.any(func(cell):return cell.id==int(id) and cell.id!=world.player.id and not cell.dead and cell.health>0 and cell.lineage_id()==world.player.lineage_id()):merge_candidates[int(id)]=true
	else:
		for id in world.FamilyMerging.candidates(world,world.player):merge_candidates[id]=true

func _merge_bright(cell) -> bool:
	return cell.id==world.player.id or merge_candidates.has(cell.id)

func _begin_merge_selection() -> void:
	if merge_selecting() or user_paused or settings_panel.visible or world.player.dead:return
	if build_open:_finish_build()
	cell_ui.close_context()
	merge_selection={"cell":world.player.id,"zoom":manual_zoom,"locked":camera_locked,"free":free_camera,"offset":camera_offset,"rotation":camera_rotation,"intero_rotation":intero_rotation,"perception":perception}
	_ease_camera()
	perception="exteroception";camera_locked=true;camera_offset=Vector2.ZERO;camera_rotation=0;intero_rotation=0
	var size:=get_viewport_rect().size
	var base: float=minf(size.x/Simulation.VIEW.x,size.y/Simulation.VIEW.y)
	var radius: float=world.FamilyMerging.neighborhood(world.player)
	manual_zoom=clampf(minf(size.x,size.y)/(2.4*radius*base),MIN_ZOOM,MAX_ZOOM);camera_zoom=manual_zoom;focus_animating=false
	touch_zoom.cancel();inspector.box.hide();inspector.touch_until=0
	_update_perception_menu();_update_world(1);touch_zoom.layout();cell_ui.sync(0)
	_message("No available relatives detected yet. Wait for a family trail, or Cancel." if merge_candidates.is_empty() else "Choose a bright relative to merge. Dim cells cannot be selected.")

func _end_merge_selection(restore: bool=true) -> void:
	if not merge_selecting():return
	var previous: Dictionary=merge_selection
	merge_selection={};merge_candidates.clear()
	_ease_camera()
	if restore and world.player.id==previous.cell and not world.player.dead:
		perception=previous.perception;camera_locked=previous.locked;free_camera=previous.free;camera_offset=previous.offset
		camera_rotation=previous.rotation;intero_rotation=previous.intero_rotation;manual_zoom=previous.zoom;camera_zoom=manual_zoom;focus_animating=false
	touch_zoom.cancel();_update_perception_menu();_update_world(1);touch_zoom.layout();cell_ui.sync(0)

func _merge_at(screen: Vector2) -> int:
	var selected_id:=-1;var top:=-1000;var distance:=INF
	for cell in world.cells:
		if not merge_candidates.has(cell.id) or not views.has(cell.id) or cell.dead:continue
		var view=views[cell.id]
		var local: Vector2=view.get_global_transform_with_canvas().affine_inverse()*screen
		if not Geometry2D.is_point_in_polygon(local,cell.membrane.outline()):continue
		var score: float=local.length()/maxf(1,cell.radius)
		if view.z_index>top or (view.z_index==top and score<distance):
			top=view.z_index;distance=score;selected_id=cell.id
	return selected_id if merge_candidates.has(selected_id) else -1

func _choose_merge_at(screen: Vector2) -> void:
	_refresh_merge_candidates()
	var identity: int=_merge_at(screen)
	if identity<0:
		_message("Choose a bright relative whose pheromones this cell can detect.");return
	if world.edit("merge",{"id":identity}):
		_end_merge_selection()
	else:_message("That relative is no longer available. Choose another bright cell.")

func _family_at(screen: Vector2) -> int:
	var nearest := -1
	var distance := INF
	for cell in world.lineage.active_family(world):
		if not views.has(cell.id): continue
		var view = views[cell.id]
		var local: Vector2 = view.get_global_transform_with_canvas().affine_inverse()*screen
		if not Geometry2D.is_point_in_polygon(local,cell.membrane.outline()): continue
		var score: float = local.length()/maxf(1,cell.radius)
		if score < distance:
			distance = score
			nearest = cell.id
	return nearest

func _switch_family(identity: int) -> bool:
	if merge_selecting():return false
	if identity < 0 or identity == world.player.id or selected >= 0 or moving_id >= 0: return false
	if world.remote_client:
		# Owned off-camera relatives have ledger/portrait data, not client bodies.
		var record: Dictionary=world.lineage.record_for(identity)
		if record.is_empty() or record.state!="living":return false
	elif not world.lineage.active_family(world).any(func(cell):return cell.id == identity): return false
	if build_open:
		world.commit_build();build_open=false;selected=-1;moving_id=-1 # Keep the displayed pose, not the old edit-entry camera.
	cell_ui.close_context()
	if not world.edit("follow",{"id":identity}): return false
	if world.remote_client:return true # Reframe only after the authoritative selected body arrives.
	_ease_camera()
	camera_locked = true; camera_offset = Vector2.ZERO; intero_rotation = 0
	touch_zoom.last_tap_family = -1
	_update_world(1)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if feedback.opened or profile.opened or palette.opened or player_help.opened or lineage_confirming:return
	if touch_zoom.enabled and (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device==-1:return
	if merge_selecting() and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:_end_merge_selection();return
		if event.button_index==MOUSE_BUTTON_LEFT:_choose_merge_at(event.position);return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not cell_ui.context.is_empty():
		cell_ui.close_context()
		return
	if not _can_edit_tubules(): tube_start.clear()
	if settings_panel.visible or world.evolution.terminal(): return
	if event is InputEventMouseMotion and camera_dragging:
		if camera_locked: camera_offset -= event.relative.rotated(-intero_rotation if perception=="interoception" else -camera_rotation)/zoom
		else: free_camera = Simulation.Medium.wrap_position(free_camera-event.relative.rotated(-camera_rotation)/zoom)
		currents.queue_redraw()
		return
	if not event is InputEventMouseButton: return
	var relative := _player_relative(event.position)
	var local := relative.rotated(-_player_heading())
	if not event.pressed:
		if event.button_index == camera_button: camera_dragging = false
		if event.button_index == MOUSE_BUTTON_LEFT and not tube_start.is_empty():
			var endpoint := _tubule_anchor(local)
			if not endpoint.is_empty():
				tube_group = world.edit("link_add",{"start":tube_start,"end":endpoint,"value":tube_tension})
				if tube_group >= 0:
					shape_preview_ticks = 60
			tube_start.clear()
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE and (merge_selecting() or build_open or not camera_locked or perception=="interoception"):
		_direct_camera()
		camera_dragging = true
		camera_button = event.button_index
		tube_start.clear()
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var hit := _nearest_tubule(local) if _can_edit_tubules() and selected < 0 and moving_id < 0 and cell_ui.hit(event.position).is_empty() else {}
		if not hit.is_empty():
			var link: Dictionary = world.player.membrane.skeleton.link_by_id(hit.id)
			tube_group = link.group
			tube_tension = clampf(link.tension+(0.05 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.05),0,1)
			world.edit("tension",{"id":tube_group,"value":tube_tension})
			shape_preview_ticks = 60
			return
		_zoom_at(event.position,1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/1.12)
		return
	if world.player.dead:
		if event.button_index==MOUSE_BUTTON_LEFT and not camera_locked:
			_direct_camera()
			camera_dragging=true;camera_button=event.button_index
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if selected >= 0 or moving_id >= 0:
			selected = -1
			moving_id = -1
			return
		if not tube_start.is_empty(): tube_start.clear(); return
		if not cell_ui.context.is_empty(): cell_ui.close_context(); return
		if _can_edit_tubules() and cell_ui.hit(event.position).is_empty():
			var hit := _nearest_tubule(local)
			if not hit.is_empty():
				world.edit("link_remove",{"id":world.player.membrane.skeleton.link_by_id(hit.id).group})
				tube_group = -1
				shape_preview_ticks = 60
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click and _switch_family(_family_at(event.position)): return
		if build_open and (selected >= 0 or moving_id >= 0):
			if _placement_hit(relative):
				_place_at(world.player.surface_parameter(local.angle()))
				return
		var target: Dictionary = cell_ui.pick(event.position)
		if not target.is_empty():
			if not build_open: _toggle_build()
			cell_ui.open_context(target)
			return
		if not cell_ui.context.is_empty(): cell_ui.close_context(); return
		if _can_edit_tubules() and selected < 0 and moving_id < 0:
			var anchor := _tubule_anchor(local)
			if not anchor.is_empty(): tube_start = anchor; return
		if not build_open and not camera_locked:
			_direct_camera()
			camera_dragging = true
			camera_button = event.button_index

func _nearest_tubule(local: Vector2) -> Dictionary:
	var membrane = world.player.membrane
	var best: Dictionary = {}
	var distance: float = 16.0*preferences.hud_scale/zoom
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
	if tube_group >= 0: world.edit("tension",{"id":tube_group,"value":tube_tension})
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
	var args := OS.get_cmdline_user_args()
	particle_backend=OS.get_environment("PRIMORDIA_PARTICLES")
	if particle_backend=="": particle_backend="resident"
	for arg in args:
		if arg.begins_with("--particle-backend="): particle_backend=arg.trim_prefix("--particle-backend=")
	if particle_backend=="resident":
		if "--benchmark" not in args: _start_resident()
		return
	if particle_backend=="cpu-matching" and world.kernels!=null: world.kernels.pair_matching_configure(true)
	# Benchmark fixtures configure after population/density setup.
	if "--benchmark" not in args:
		var engine := "current"
		var parcel_option := "off"
		for arg in args:
			if arg.begins_with("--particle-engine="): engine = arg.trim_prefix("--particle-engine=")
			if arg.begins_with("--parcels="): parcel_option = arg.trim_prefix("--parcels=")
		if engine != "current" or parcel_option != "off":
			var display_half: Vector2 = world.view_half
			world.view_half = get_viewport_rect().size/(2.0*0.8)
			var valid := "--gpu-transport" not in args and engine in ["current","uniform","liquidfun"] and parcel_option in ["on","off"]
			valid = valid and world.configure_particle_engine(engine)
			if valid and parcel_option == "on": valid = world.configure_parcels(true)
			world.view_half = display_half
			if not valid:
				push_error("Particle engine/parcel trial requires the native pool, CPU fluid and valid options")
				get_tree().quit(1)
	if use_particle_pool and "--gpu-transport" not in OS.get_cmdline_user_args(): world.enable_particle_pool()
	if "--gpu-transport" not in OS.get_cmdline_user_args(): return
	var gpu = load("res://scripts/gpu_transport.gd").new()
	if gpu.initialize(): world.gpu_transport = gpu
	else: push_warning("GPU transport unavailable; keeping the CPU backend. Use --rendering-method mobile for the experiment.")

func _start_resident() -> void:
	if world.resident!=null: return
	if resident_controller!=null: resident_controller.close()
	resident_starting=true
	resident_controller=load("res://scripts/resident_ecology.gd").new()
	resident_controller.streaming_enabled=resident_streaming
	resident_controller.initialized.connect(_resident_initialized.bind(resident_controller,world),CONNECT_ONE_SHOT)
	resident_controller.returned_to_cpu.connect(_resident_returned.bind(resident_controller))
	resident_controller.start(world)

func _resident_initialized(ok: bool,message: String,controller,starting_world) -> void:
	if not is_inside_tree() or resident_controller!=controller or world!=starting_world:
		controller.close();return
	resident_starting=false
	if ok:
		if resident_view!=null: resident_view.queue_free()
		resident_view=load("res://scripts/resident_view.gd").new()
		world_layer.add_child(resident_view);resident_view.z_index=1
		resident_view.game=self;resident_view.initialize(controller.gpu)
	else: _message("GPU particles unavailable; continuing on CPU. "+message)

func _resident_returned(message: String,controller) -> void:
	if controller==resident_controller: _message("Particle simulation switched to CPU. Your habitat is preserved.")

func _exit_tree() -> void:
	if frame_trace != null: frame_trace.stop()
	if resident_controller!=null: resident_controller.close()
	elif world.resident!=null: world.resident.close()
	if world.gpu_transport != null: world.gpu_transport.close()


func begin_frame_trace() -> void:
	if frame_trace != null: return
	frame_trace = preload("res://scripts/frame_trace.gd").new()
	frame_trace.start(self)

func end_frame_trace() -> Array[Dictionary]:
	if frame_trace == null: return []
	var rows: Array[Dictionary] = frame_trace.rows.duplicate(true)
	frame_trace.stop()
	frame_trace = null
	return rows
