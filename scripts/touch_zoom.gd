extends RefCounted
## Raw multi-touch is used on the web; GUI controls retain native mouse emulation.
var game
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
	pause_button.pressed.connect(game._toggle_user_pause)
	minus_button.text="−";bar.add_child(minus_button)
	plus_button.text="+";bar.add_child(plus_button)
	minus_button.pressed.connect(func():game._zoom_at(game.camera_screen,1/1.25))
	plus_button.pressed.connect(func():game._zoom_at(game.camera_screen,1.25))
	follow_button.z_index=80;follow_button.toggle_mode=true;game.ui.add_child(follow_button)
	follow_button.pressed.connect(game._toggle_camera)
	layout()

func layout() -> void:
	if game==null:return
	var size: Vector2=game.get_viewport_rect().size
	if size!=viewport_size:
		cancel();viewport_size=size
		if OS.has_feature("web"):pixels=size.x/maxf(1,float(JavaScriptBridge.eval("window.innerWidth")))
	bar.visible=enabled and game.touch_controls_available()
	bar.add_theme_constant_override("separation",6*pixels)
	for button in [pause_button,minus_button,plus_button]:
		button.add_theme_font_size_override("font_size",roundi(18*pixels))
		button.custom_minimum_size=Vector2(100 if button==pause_button else 48,48)*pixels
	bar.reset_size()
	bar.position=Vector2(size.x-220*pixels,12*pixels)
	pause_button.text="Resume" if game.user_paused else "Pause"
	pause_button.disabled=not game.pause_control_ready
	follow_button.visible=bar.visible
	follow_button.add_theme_font_size_override("font_size",roundi(18*pixels))
	follow_button.custom_minimum_size=Vector2(208,48)*pixels
	follow_button.size=follow_button.custom_minimum_size
	follow_button.position=Vector2(size.x-220*pixels,66*pixels)
	follow_button.text="Following cell" if game.camera_locked else "Free view"
	follow_button.set_pressed_no_signal(game.camera_locked)
	state_label.visible=bar.visible and game.user_paused
	state_label.text="View paused · world continues" if game.world.remote_client else "Game paused"
	state_label.add_theme_font_size_override("font_size",roundi(14*pixels))
	state_label.position=Vector2(size.x-220*pixels,120*pixels);state_label.size=Vector2(208,44)*pixels


	if OS.has_feature("web") and enabled:
		var conversion:=Vector2(float(JavaScriptBridge.eval("window.innerWidth")),float(JavaScriptBridge.eval("window.innerHeight")))/size
		var bounds: Dictionary={}
		for pair in [["pause",pause_button],["zoom_out",minus_button],["zoom_in",plus_button],["follow",follow_button]]:
			var rect: Rect2=pair[1].get_global_rect()
			bounds[pair[0]]=[rect.position.x*conversion.x,rect.position.y*conversion.y,rect.size.x*conversion.x,rect.size.y*conversion.y]
		JavaScriptBridge.eval("window.primordiaTouchControls="+JSON.stringify({"visible":bar.visible,"paused":game.user_paused,"zoom":game.manual_zoom,"editing":game.build_open,"locked":game.camera_locked,"rotation":game.camera_rotation,"camera":[game.render_camera.x,game.render_camera.y],"player_screen":_player_screen(conversion),"bounds":bounds,"buffered_tick":game.paused_snapshot.get("tick",0) if game.world.remote_client else 0}))

func _player_screen(conversion: Vector2) -> Array:
	var view=game.views.get(game.world.player.id)
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
	fingers.clear();moved=false
	if game!=null:game.tube_start.clear();game.camera_dragging=false

func _tap(at: Vector2) -> void:
	if game.user_paused:return
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
			if fingers.size()==1:start=event.position;moved=false
			elif fingers.size()==2:
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
	anchor_b=anchor_a+(points[1]-points[0]).rotated(-game.camera_rotation)/game.zoom
	game.camera_dragging=true
	game._camera_gesture(anchor_a,anchor_b,points[0],points[1])
