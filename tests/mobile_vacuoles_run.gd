extends SceneTree
var failures:=0
var assertions:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var Cell=preload("res://scripts/cell.gd")
	var cell=Cell.new()
	cell.chemistry.receive(0,2,2,cell.position+cell.local_point(0))
	var mass: float=cell.organic_mass()
	var initial: Vector2=cell.chemistry.particles[0].p
	for i in 90:cell.chemistry.advance(cell,.1)
	check(cell.substrate>0 and cell.chemistry.particles[0].p.distance_to(initial)>1,"A finite food vacuole remains moving after nine seconds")
	var food: Dictionary=cell.chemistry.particles.filter(func(stock):return stock.species=="food")[0]
	check(cell.chemistry.particles.filter(func(stock):return stock.species=="waste").all(func(stock):return stock.p==food.p and stock.v==food.v),"Food and waste are stocks in exactly one moving carrier")
	check(absf(cell.organic_mass()-mass)<.000001,"Long residence preserves represented material")
	cell.chemistry.advance(cell,1.1)
	check(cell.substrate<.000001 and cell.waste>0,"After residence digestion leaves a finite waste-filled carrier")
	var restored=preload("res://scripts/network/state_codec.gd").new().restore(preload("res://scripts/network/state_codec.gd").new().capture(cell))
	check(restored.chemistry.particles[0].age==cell.chemistry.particles[0].age,"Checkpoint recovery retains the carrier residence clock")
	root.size=Vector2i(1170,2100)
	var game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false
	root.add_child(game);game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
	game.touch_zoom.enabled=true;game.touch_zoom.pixels=3
	game.world.player.angle=.7;game.world.player.previous_angle=.7
	game._toggle_perception()
	check(game.camera_locked and absf(game.camera_rotation+.7)<.001,"Interoception follows both the position and orientation of the rendered cell")
	game._zoom_at(game.camera_screen,10000)
	check(game.manual_zoom==game.MAX_ZOOM*10,"Interoception provides ten times the normal closest magnification")
	game._zoom_at(game.camera_screen,.05)
	var a:=Vector2(-12,3);var b:=Vector2(12,3);var mid: Vector2=game.camera_screen+Vector2(40,-20)
	var span:=Vector2(90,0).rotated(.4)
	game._camera_gesture(a,b,mid-span,mid+span)
	var error: float=maxf(game._world_screen(game.follow_origin+a.rotated(game.follow_heading)).distance_to(mid-span),game._world_screen(game.follow_origin+b.rotated(game.follow_heading)).distance_to(mid+span))
	check(error<.02 and game.camera_locked,"Combined internal pan/twist/pinch keeps both cell-frame anchors under the fingers")
	var offset: Vector2=game.camera_offset;var rotation: float=game.intero_rotation
	game.world.player.angle=1.2;game.world.player.previous_angle=1.2
	game.world.player.position+=Vector2(60,-20);game.world.player.previous_position=game.world.player.position
	game._update_world(1)
	check(game.camera_locked and game.camera_offset==offset and game.intero_rotation==rotation and absf(game.camera_rotation-(rotation-1.2))<.001,"The manipulated camera stays attached as the cell translates and rotates")
	game.world.player.angle=0;game.world.player.previous_angle=0
	game.manual_zoom=game.MIN_ZOOM;game.intero_rotation=0;game.camera_offset=Vector2(0,900);game._update_world(1)
	var upper: Vector2=game.camera_screen-Vector2(0,600);var lower: Vector2=game.camera_screen+Vector2(0,600)
	game.touch_zoom.fingers={0:upper,1:lower};game.touch_zoom._anchor_pair()
	check(is_equal_approx(game.manual_zoom,game.MIN_ZOOM) and game.camera_offset.distance_to(Vector2(0,900))<.01,"A wide internal gesture crossing the torus seam retains its unwrapped cell-frame anchors")
	game.touch_zoom.cancel()
	game._toggle_build();game.cell_ui.open_context({"kind":"assembly"})
	await process_frame
	game.cell_ui.sync(0)
	check(game.cell_ui.choices.size()==7 and game.cell_ui.choices.all(func(choice):return choice.get_parent()==game.cell_ui.mobile_flow),"Mobile assembly exposes every available organ in the top tray")
	check(game.touch_zoom.pause_button.get_global_rect().position.y>=game.cell_ui.mobile_menu_height,"Opening a top tray moves the utility controls below it immediately")
	check(game.cell_ui.mobile_menu_height>0 and game.cell_ui.mobile_tray.position.y<30,"Mobile action menus are attached to the top of the screen")
	check(game.cell_ui.mobile_resources.visible and game.cell_ui.mobile_stocks.text.contains("AP") and game.cell_ui.mobile_stocks.text.contains("ATP"),"Mobile stock display is visible without hovering")
	game.cell_ui.mobile_hide.pressed.emit();game.cell_ui.sync(0)
	check(not game.cell_ui.mobile_stocks.visible and game.cell_ui.mobile_hide.visible,"A small button hides and restores mobile resource readouts")
	game.cell_ui.mobile_hide.pressed.emit();game.cell_ui.sync(0)
	check(game.cell_ui.mobile_stocks.visible,"The same resource button restores current numerical stocks")
	game.cell_ui.open_context({"kind":"chemistry"});await process_frame;game.cell_ui.sync(0)
	check(game.cell_ui.choices.size()==6 and game.cell_ui.choices.all(func(choice):return choice.get_parent()==game.cell_ui.mobile_flow),"Mobile chemistry factory exposes all glands and food inspection in the top tray")
	check(game.cell_ui.describe({"kind":"chemistry"}).contains("buffer/repair") and game.cell_ui.describe({"kind":"chemistry"}).to_lower().contains("photosynthesis"),"Factory description matches the active simplified chemistry")
	game.world.player.biomass=100;game.world.player.update_geometry();game.world.evolution.points=8
	for index in [7,9,3,8]:
		game.cell_ui.open_context({"kind":"chemistry"});game.cell_ui.sync(0)
		var options: Array=game.cell_ui.choices.filter(func(choice):return choice.kind==game.Simulation.KINDS[index])
		check(options.size()==1,"Each requested chemical gland has one unambiguous factory choice")
		var before_biomass: float=game.world.player.biomass;var before_ap: int=game.world.evolution.points
		options[0].pressed.emit();game.cell_ui.sync(0)
		check(game.selected==index and not game.cell_ui.mobile_tray.visible and game.cell_ui.mobile_stocks.text.contains("Cost"),"Choosing each gland enters the existing placement flow with visible resource cost")
		var price: float=game.Simulation.Cell.organ_cost(game.Simulation.KINDS[index])
		check(game._place_at(1.0+[7,9,3,8].find(index)),"Each restored gland can be placed on the membrane")
		check(game.world.player.biomass==before_biomass and before_ap-game.world.evolution.points==1,"Gland placement charges AP exactly once without debiting biomass")
	game._select(6);game.cell_ui.sync(0)
	check(game.cell_ui.cancel_icon.visible and game.cell_ui.cancel_icon.kind=="photosynthesis" and game.cell_ui.cancel_icon.position.x<30,"Selected organ remains as a circular top-left cancel action")
	game.cell_ui.cancel_icon.pressed.emit();game.cell_ui.sync(0)
	check(game.selected<0 and game.moving_id<0 and not game.cell_ui.cancel_icon.visible,"Tapping the selected icon cancels placement")
	game.touch_zoom.pause_button.pressed.emit()
	check(game.user_paused and game.settings_panel.visible,"Mobile Pause opens settings and freezes only this displayed view")
	check(game.settings_panel.theme.default_font_size>=54 and game.settings_panel.size.x>1000,"Mobile settings use readable CSS-sized text and the available width")
	check(not game.settings_panel.get_global_rect().intersects(game.touch_zoom.pause_button.get_global_rect()) and not game.touch_zoom.follow_button.visible,"Settings scrolling cannot capture Resume taps or overlap duplicate controls")
	game.touch_zoom.pause_button.pressed.emit()
	check(not game.user_paused and not game.settings_panel.visible,"Mobile Resume closes settings and returns to the world")
	game.cell_ui.close_context()
	game._message("Needs an adaptation point.");game.cell_ui.sync(0)
	check(game.cell_ui.message.get_theme_font_size("font_size")>=66 and game.cell_ui.message.get_theme_font("font").get_font_name().contains("Comic"),"Mobile feedback uses readable CSS-sized comic typography")
	game.cell_ui.sync(0)
	check(game.cell_ui.tip_box.visible and game.cell_ui.tip_box.position.y>root.size.y*.65 and game.cell_ui.tip.max_lines_visible==3,"Mobile feedback occupies one compact bottom strip")
	var retained_zoom: float=clampf(game.manual_zoom,game.MIN_ZOOM,game.MAX_ZOOM)
	game._toggle_perception()
	check(game.perception=="exteroception" and game.manual_zoom==retained_zoom and game.camera_locked,"Leaving interoception retains zoom within exterior bounds")
	game.world.evolution.points=10000;game.cell_ui.interior.sync()
	check(game.cell_ui.interior.ecology.parcels.size()<=16 and game.world.evolution.points==10000,"A long-lived lineage keeps exact AP with bounded decorative tokens")
	game.queue_free();await process_frame
	print("MOBILE VACUOLES: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
