extends RefCounted
## Raw multi-touch is used on the web; GUI controls retain native mouse emulation.
var game
var last_tap_family := -1
var last_tap_time := -10000
var last_tap_at := Vector2.ZERO
var enabled := false
var pixels := 1.0
var viewport_size := Vector2.ZERO
var fingers: Dictionary={}
var moved := false
var anchor_a := Vector2.ZERO
var anchor_b := Vector2.ZERO
var start := Vector2.ZERO
var bar:=HBoxContainer.new()
var pause_button:=Button.new()
var minus_button:=Button.new()
var plus_button:=Button.new()
var state_label:=Label.new()
var follow_button:=Button.new()
var perception_button:=Button.new()
var music_button:=Button.new()
var music_volume:=HSlider.new()

func initialize(owner_game) -> void:
	game=owner_game
	enabled=DisplayServer.is_touchscreen_available()
	if OS.has_feature("web"):
		enabled=bool(JavaScriptBridge.eval("navigator.maxTouchPoints>0 || 'ontouchstart' in window"))
		if enabled:JavaScriptBridge.eval("document.getElementById('canvas').style.touchAction='none'")
	state_label.z_index=80;state_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;state_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	game.ui.add_child(state_label)
	bar.z_index=80;game.ui.add_child(bar)
	pause_button.text="Pause";bar.add_child(pause_button)
	pause_button.pressed.connect(game._mobile_pause_menu)
	minus_button.text="−";bar.add_child(minus_button)
	plus_button.text="+";bar.add_child(plus_button)
	minus_button.pressed.connect(func():game._zoom_button(1/1.25))
	plus_button.pressed.connect(func():game._zoom_button(1.25))
	follow_button.z_index=80;follow_button.toggle_mode=true;game.ui.add_child(follow_button)
	follow_button.pressed.connect(game._toggle_camera)
	perception_button.z_index=80;game.ui.add_child(perception_button)
	perception_button.pressed.connect(game._toggle_perception)
	music_button.z_index=80;music_button.toggle_mode=true;game.ui.add_child(music_button)
	music_button.pressed.connect(func():
		if music_button.text=="Enable music":game.music.enable_music()
		else:game.music.toggle())
	music_volume.z_index=80;music_volume.max_value=100;music_volume.step=1;music_volume.tooltip_text="Music volume";game.ui.add_child(music_volume)
	music_volume.value_changed.connect(func(value):
		game.preferences.music_volume=value/100.0;game.preferences.save_settings()
		if game.music.web_audio!=null:game.music.web_audio.volume(game.preferences.music_volume))
	layout()

func layout() -> void:
	if game==null:return
	var size: Vector2=game.get_viewport_rect().size
	if size!=viewport_size:
		cancel();viewport_size=size
		if OS.has_feature("web"):pixels=size.x/maxf(1,float(JavaScriptBridge.eval("window.innerWidth")))
	bar.visible=enabled and game.touch_controls_available()
	bar.add_theme_constant_override("separation",6*pixels*.7)
	for button in [pause_button,minus_button,plus_button]:
		button.add_theme_font_size_override("font_size",roundi(18*pixels*.7))
		button.custom_minimum_size=Vector2(100 if button==pause_button else 48,48)*pixels*.7
	bar.reset_size()
	var tray_offset: float=game.cell_ui.mobile_menu_height if enabled else 0.0
	bar.position=Vector2(size.x-220*pixels*.7,12*pixels*.7+tray_offset)
	pause_button.text="Resume" if game.user_paused else "Pause"
	pause_button.disabled=not game.pause_control_ready
	follow_button.visible=bar.visible and not game.settings_panel.visible
	follow_button.add_theme_font_size_override("font_size",roundi(18*pixels*.7))
	follow_button.custom_minimum_size=Vector2(208,48)*pixels*.7
	follow_button.size=follow_button.custom_minimum_size
	follow_button.position=Vector2(size.x-220*pixels*.7,66*pixels*.7+tray_offset)
	follow_button.text="Follow"
	follow_button.tooltip_text="Recenter the cell-frame view" if game.perception=="interoception" else "Toggle follow / free view"
	follow_button.self_modulate=Color.WHITE if game.camera_locked and game.can_follow() else Color(1,1,1,.60)
	follow_button.set_pressed_no_signal(game.camera_locked and game.can_follow())
	follow_button.disabled=not game.can_follow()
	perception_button.visible=bar.visible and not game.settings_panel.visible
	perception_button.text="Interoception" if game.perception=="exteroception" else "Exteroception"
	perception_button.add_theme_font_size_override("font_size",roundi(18*pixels*.7))
	perception_button.custom_minimum_size=Vector2(208,48)*pixels*.7;perception_button.size=perception_button.custom_minimum_size
	perception_button.position=Vector2(size.x-220*pixels*.7,120*pixels*.7+tray_offset)
	music_button.visible=bar.visible and not game.settings_panel.visible;music_volume.visible=music_button.visible
	var sounding: bool=game.preferences.music_volume>0
	var locked_audio: bool=game.music.web_audio!=null and game.music.web_audio.cached.get("state","")!="running"
	music_button.text="Music off" if not sounding else "Enable music" if locked_audio else "Music"
	music_button.set_pressed_no_signal(sounding and not locked_audio)
	music_button.self_modulate=Color.WHITE if sounding and not locked_audio else Color(1,1,1,.6)
	music_button.add_theme_font_size_override("font_size",roundi(16*pixels*.7))
	music_button.custom_minimum_size=Vector2(120,48)*pixels*.7;music_button.size=music_button.custom_minimum_size;music_button.position=Vector2(size.x-220*pixels*.7,174*pixels*.7+tray_offset)
	music_volume.custom_minimum_size=Vector2(82,48)*pixels*.7;music_volume.size=music_volume.custom_minimum_size;music_volume.position=Vector2(size.x-94*pixels*.7,174*pixels*.7+tray_offset)
	music_volume.set_value_no_signal(game.preferences.music_volume*100)
	state_label.visible=bar.visible and not game.settings_panel.visible and (game.user_paused or game.world.player.dead)
	state_label.text="View paused · world continues" if game.world.remote_client else "Game paused"
	if not game.user_paused and game.world.player.dead:
		var received_recovery=game.get("family_recovery") if game.world.remote_client else {}
		var recovery: Dictionary=received_recovery if received_recovery is Dictionary else {}
		state_label.text="Preparing your new lineage" if recovery.get("state","")=="restarting_lineage" else "Waiting for a new cell" if recovery.get("state","")=="waiting_for_space" else "Lineage exhausted · observing" if game.can_follow() and recovery.get("state","")=="extinct" else "Lineage exhausted · no stored successor" if recovery.get("state","")=="extinct" else "Observing a living cell" if game.can_follow() else "No living cell to follow"
	state_label.add_theme_font_size_override("font_size",roundi(14*pixels*.7))
	state_label.position=Vector2(size.x-220*pixels*.7,228*pixels*.7+tray_offset);state_label.size=Vector2(208,44)*pixels*.7


	if OS.has_feature("web") and enabled:
		var conversion:=Vector2(float(JavaScriptBridge.eval("window.innerWidth")),float(JavaScriptBridge.eval("window.innerHeight")))/size
		var bounds: Dictionary={}
		for pair in [["pause",pause_button],["feedback",game.feedback_menu_button],["profile",game.profile_menu_button],["palette",game.palette_menu_button],["gameplay",game.gameplay_menu_button],["mechanics",game.mechanics_menu_button],["zoom_out",minus_button],["zoom_in",plus_button],["follow",follow_button],["perception",perception_button],["music",music_button],["music_volume",music_volume]]:
			var rect: Rect2=pair[1].get_global_rect()
			bounds[pair[0]]=[rect.position.x*conversion.x,rect.position.y*conversion.y,rect.size.x*conversion.x,rect.size.y*conversion.y]
		JavaScriptBridge.eval("window.primordiaTouchControls="+JSON.stringify({"visible":bar.visible,"paused":game.user_paused,"zoom":game.manual_zoom,"editing":game.build_open,"locked":game.camera_locked,"rotation":game.render_rotation,"camera":[game.render_camera.x,game.render_camera.y],"player_screen":_body_screen(game.world.player,conversion),"focus_screen":_body_screen(game._follow_cell(),conversion),"focus_alive":game.can_follow(),"perception":game.perception,"internal_packets":game._follow_cell().chemistry.particle_count(),"mask_enabled":game.perception_mask.enabled,"bounds":bounds,"cell_ui":game.cell_ui.mobile_diagnostics(conversion),"buffered_tick":game.paused_snapshot.get("tick",0) if game.world.remote_client else 0}))

func _body_screen(body,conversion: Vector2) -> Array:
	var view=game.views.get(body.id)
	if view==null:return []
	var at: Vector2=view.get_global_transform_with_canvas().origin*conversion
	return [at.x,at.y]

func _over_gui(node: Node,at: Vector2) -> bool:
	for child in node.get_children():
		if not child is Control or not child.is_visible_in_tree():continue
		if child.clip_contents and not child.get_global_rect().has_point(at):continue
		if _over_gui(child,at):return true
		if child.mouse_filter!=Control.MOUSE_FILTER_IGNORE and child.get_global_rect().has_point(at):return true
	return false

func cancel() -> void:
	fingers.clear();moved=false;last_tap_family=-1
	if game!=null:game.tube_start.clear();game.camera_dragging=false

func _tap(at: Vector2) -> void:
	game.inspector.inspect_touch(at)
	if game.user_paused:return
	var now := Time.get_ticks_msec()
	var family: int = game._family_at(at)
	if family >= 0 and family == last_tap_family and now-last_tap_time <= 400 and at.distance_to(last_tap_at) <= 24*pixels:
		last_tap_family = -1
		if game._switch_family(family): return
	last_tap_family = family; last_tap_time = now; last_tap_at = at
	if family >= 0 and family != game.world.player.id and game.selected < 0 and game.moving_id < 0:
		game.cell_ui.close_context(); return # First tap must not recenter/edit another body.

	if game.cell_ui.hit(at).is_empty() and game.selected<0 and game.moving_id<0:
		game.cell_ui.close_context();return
	var event:=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true;game._unhandled_input(event)
	event.pressed=false;game._unhandled_input(event)

func handle(event: InputEvent) -> bool:
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:return false
	if not enabled:enabled=true;layout()
	if event is InputEventScreenTouch:
		if event.canceled:cancel();return true
		if event.pressed:
			if _over_gui(game.ui,event.position):return false
			fingers[event.index]=event.position
			if fingers.size()==1:
				start=event.position;moved=false;game.inspector.inspect_touch(event.position)
			elif fingers.size()==2:
				last_tap_family = -1
				game.inspector.touch_until=0
				moved=true;game.tube_start.clear();game.camera_dragging=false
				_anchor_pair()
			return true
		if not fingers.has(event.index):return false
		fingers.erase(event.index)
		if fingers.size()==2:_anchor_pair()
		if fingers.size()<2:game.camera_dragging=false
		if not moved and fingers.is_empty():_tap(event.position)
		return true
	if not fingers.has(event.index):return false
	fingers[event.index]=event.position
	if event.position.distance_to(start)>8*pixels:moved=true
	if fingers.size()==2:
		var points:=fingers.values()
		game.camera_dragging=true
		game._camera_gesture(anchor_a,anchor_b,points[0],points[1])
	return true

func _anchor_pair() -> void:
	var points:=fingers.values()
	anchor_a=game._screen_world(points[0])
	# Retain the unwrapped separation: a gesture may straddle a torus seam.
	anchor_b=anchor_a+(points[1]-points[0]).rotated(-game.render_rotation)/game.zoom
	if game.perception=="interoception":
		anchor_a=game._cell_frame_point(anchor_a)
		anchor_b=anchor_a+(points[1]-points[0]).rotated(-game.intero_rotation)/game.zoom
	game.camera_dragging=true
	game._camera_gesture(anchor_a,anchor_b,points[0],points[1])
