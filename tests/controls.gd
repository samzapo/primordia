extends RefCounted
## Input/camera invariants share an offline client, not a second native UI mode.
const Offline=preload("res://tests/status_ui_run.gd")
var game
func touch(index: int,at: Vector2,pressed: bool,canceled: bool=false) -> void:
 var event:=InputEventScreenTouch.new();event.index=index;event.position=at;event.pressed=pressed;event.canceled=canceled
 game._input(event)
func drag(index: int,at: Vector2) -> void:
 var event:=InputEventScreenDrag.new();event.index=index;event.position=at
 game._input(event)
func settle_camera(target) -> void:
 for frame in 45:
  target.camera_motion.advance(1.0/60);target._update_world(1)
func run(suite) -> void:
 var previous_size: Vector2i=suite.root.size;var previous_scale: Vector2i=suite.root.content_scale_size
 suite.root.size=Vector2i(1440,900);suite.root.content_scale_size=Vector2i.ZERO
 game=Offline.OfflineClient.new();game.use_particle_pool=false;suite.root.add_child(game)
 game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
 game.connected=true;game.connection_stage="ready";game.loading_world=false;game.login.hide()
 game._layout();game._update_world(1)
 game.controls.touch_enabled=true;game.manual_zoom=2;game.controls.layout();game._update_world(1)
 var original_time: float=game.world.time
 var random: int=game.world.rng.state
 var organ_scales: Array=game.world.player.organs.map(func(organ):return organ.scale)
 var middle: Vector2=game.camera_screen
 var before: float=game.manual_zoom
 touch(0,middle-Vector2(90,0),true);touch(1,middle+Vector2(90,0),true)
 suite.expect(not game.camera_locked,"Placing two fingers anchors the view immediately, before a drag or another server update")
 drag(0,middle-Vector2(150,0));drag(1,middle+Vector2(150,0))
 touch(0,middle-Vector2(150,0),false);touch(1,middle+Vector2(150,0),false)
 suite.expect(game.manual_zoom>before,"Two-finger spread zooms the rendered world")
 suite.expect(not game.build_open and game.selected<0 and game.tube_start.is_empty(),"Pinch on the cell cannot become an assembly click or a microtubule")
 suite.expect(game.world.time==original_time and game.world.rng.state==random and game.world.player.organs.map(func(organ):return organ.scale)==organ_scales,"Pinch changes no simulation time, chemical randomness or organ size")
 before=game.manual_zoom
 touch(3,middle-Vector2(150,0),true);touch(7,middle+Vector2(150,0),true)
 drag(3,middle-Vector2(60,0));drag(7,middle+Vector2(60,0))
 touch(3,middle-Vector2(60,0),false);touch(7,middle+Vector2(60,0),false)
 suite.expect(game.manual_zoom<before,"Two-finger pinch zooms out with arbitrary finger identities")
 game._zoom_at(middle,1000);suite.expect(game.manual_zoom==game.MAX_ZOOM,"Touch zoom retains maximum magnification")
 game._zoom_at(middle,.00001);suite.expect(game.manual_zoom==game.MIN_ZOOM,"Touch zoom retains the widest playable limit")
 touch(0,middle-Vector2(90,0),true);touch(1,middle+Vector2(90,0),true)
 touch(0,middle-Vector2(90,0),false,true)
 suite.expect(game.controls.fingers.is_empty() and not game.camera_dragging,"Canceled touch clears the entire gesture")
 game.manual_zoom=2;game.camera_locked=false;game.free_camera=Vector2(4090,2550);game.camera_rotation=0;game._update_world(1)
 var anchor_time: float=game.world.time;var anchor_rng: int=game.world.rng.state
 var first:=middle+Vector2(-70,25);var second:=middle+Vector2(90,25)
 touch(2,first,true);touch(9,second,true)
 var anchor_a: Vector2=game.controls.anchor_a;var anchor_b: Vector2=game.controls.anchor_b
 var final_mid:=middle+Vector2(45,-35);var half:=Vector2(115,0).rotated(.57)
 drag(2,final_mid-half);drag(9,final_mid+half)
 var error:=maxf(game._world_screen(anchor_a).distance_to(final_mid-half),game._world_screen(anchor_b).distance_to(final_mid+half))
 suite.expect(error<.005 and absf(game.camera_rotation-.57)<.001 and not game.camera_locked,"Both fixed world anchors remain beneath their fingers through combined seam-crossing pan, twist and zoom")
 suite.expect(game.world.time==anchor_time and game.world.rng.state==anchor_rng and not game.build_open,"Two-finger camera solving never edits the cell or advances biology/random streams")
 var coverage:=true
 for corner in [Vector2.ZERO,Vector2(game.get_viewport_rect().size.x,0),game.get_viewport_rect().size,Vector2(0,game.get_viewport_rect().size.y)]:
  var offset: Vector2=game.Simulation.Medium.offset(game.render_camera,game._screen_world(corner))
  coverage=coverage and absf(offset.x)<=game.world.view_half.x+.01 and absf(offset.y)<=game.world.view_half.y+.01
 suite.expect(coverage,"Detailed camera bounds cover all four rotated viewport corners across the world seam")
 var placed: Vector2=game._screen_world(final_mid-half)
 suite.expect(game.Simulation.Medium.offset(anchor_a,placed).length()<.005,"Rotated screen-to-world picking inverts world projection")
 touch(2,final_mid-half,false);var camera: Vector2=game.free_camera
 drag(9,final_mid+half+Vector2(40,20));touch(9,final_mid+half+Vector2(40,20),false)
 suite.expect(game.free_camera==camera,"Lifting one finger ends camera manipulation without a one-finger jump")
 game._toggle_camera()
 suite.expect(game.camera_motion.active,"Follow moves through a smooth camera transition")
 settle_camera(game)
 suite.expect(game.camera_locked and game.camera_rotation==0 and game.views.has(game.world.player.id) and game.views[game.world.player.id].position.length()<.005,"Follow toggle restores an upright view centered on the rendered cell")
 camera=game.render_camera;touch(4,middle,true);drag(4,middle+Vector2(80,20));touch(4,middle+Vector2(80,20),false)
 suite.expect(game.camera_locked and game.render_camera==camera,"One-finger dragging cannot pan the camera")
 game.controls.pixels=3;game.controls.layout()
 suite.expect(game.controls.plus_button.custom_minimum_size.y>=100.7 and game.controls.minus_button.custom_minimum_size.y>=100.7,"Zoom targets use the requested 70% size at a scaled canvas")
 var gui: Vector2=game.controls.plus_button.get_global_rect().get_center()
 var event:=InputEventScreenTouch.new();event.index=0;event.position=gui;event.pressed=true
 suite.expect(not game.controls.handle(event),"A touch button retains ordinary GUI event routing")
 game.controls.pause_button.pressed.emit()
 suite.expect(game.user_paused and game.settings_panel.visible,"The shared Pause button opens the paused view menu")
 game.controls.pause_button.pressed.emit()
 suite.expect(not game.user_paused and not game.settings_panel.visible,"The shared Resume action returns to the live view")
 game.queue_free();await suite.process_frame
 suite.root.content_scale_size=previous_scale;suite.root.size=previous_size
