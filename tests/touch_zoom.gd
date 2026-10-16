extends RefCounted
## Gesture routing and presentation correctness; no balance or survival checks.
class IsolatedClient:
	extends "res://scripts/network/network_client.gd"
	func _load_identity() -> void:pass
	func _save_identity() -> void:pass

var game
func touch(index: int,at: Vector2,pressed: bool,canceled: bool=false) -> void:
	var event:=InputEventScreenTouch.new();event.index=index;event.position=at;event.pressed=pressed;event.canceled=canceled
	game._input(event)
func drag(index: int,at: Vector2) -> void:
	var event:=InputEventScreenDrag.new();event.index=index;event.position=at
	game._input(event)
func run(suite) -> void:
	game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false
	suite.root.add_child(game);game.set_physics_process(false);game.set_process(false)
	game.music.enabled=false;game.music.player.stop()
	game.touch_zoom.enabled=false;game.touch_zoom.layout()
	suite.expect(not game.touch_zoom.perception_button.visible,"Desktop keeps the perception overlay hidden without touch input")
	game.preferences.fullscreen=true
	var menu_key:=InputEventKey.new();menu_key.keycode=KEY_M;menu_key.pressed=true;game._input(menu_key)
	suite.expect(game.settings_panel.visible and game.perception_menu_button.is_visible_in_tree() and game.perception_menu_button.text=="Interoception [I]","M menu exposes the perception action and keyboard shortcut")
	var desktop_time: float=game.world.time;var desktop_rng: int=game.world.rng.state
	var shortcut:=InputEventKey.new();shortcut.keycode=KEY_I;shortcut.pressed=true;game._input(shortcut)
	suite.expect(game.perception=="interoception" and game.perception_menu_button.text=="Exteroception [I]" and game.perception_mask.enabled,"I switches perception from the M menu and updates its return action")
	game.perception_menu_button.pressed.emit()
	suite.expect(game.perception=="exteroception" and game.perception_menu_button.text=="Interoception [I]" and not game.perception_mask.enabled and game.world.time==desktop_time and game.world.rng.state==desktop_rng,"The menu action returns outside without changing simulation time or randomness")
	game._input(menu_key)
	suite.expect(not game.settings_panel.visible and game.preferences.fullscreen,"M closes the menu without toggling fullscreen")
	var reserved:=InputEventKey.new();reserved.keycode=KEY_ESCAPE;reserved.pressed=true;game._input(reserved)
	suite.expect(not game.settings_panel.visible,"Escape is reserved for the browser rather than opening the game menu")
	game.preferences.fullscreen=false
	game.touch_zoom.enabled=true;game.manual_zoom=2;game.touch_zoom.layout();game._update_world(1)
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
	suite.expect(game.touch_zoom.fingers.is_empty() and not game.camera_dragging,"Canceled touch clears the entire gesture")
	game.manual_zoom=2;game.camera_locked=false;game.free_camera=Vector2(4090,2550);game.camera_rotation=0;game._update_world(1)
	var anchor_time: float=game.world.time;var anchor_rng: int=game.world.rng.state
	var first:=middle+Vector2(-70,25);var second:=middle+Vector2(90,25)
	touch(2,first,true);touch(9,second,true)
	var anchor_a: Vector2=game.touch_zoom.anchor_a;var anchor_b: Vector2=game.touch_zoom.anchor_b
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
	suite.expect(game.camera_locked and game.camera_rotation==0 and game.views.has(game.world.player.id) and game.views[game.world.player.id].position.length()<.005,"Follow toggle restores an upright view centered on the rendered cell")
	camera=game.render_camera;touch(4,middle,true);drag(4,middle+Vector2(80,20));touch(4,middle+Vector2(80,20),false)
	suite.expect(game.camera_locked and game.render_camera==camera,"One-finger dragging cannot pan the camera")
	game.touch_zoom.pixels=3;game.touch_zoom.layout()
	suite.expect(game.touch_zoom.plus_button.custom_minimum_size.y>=100.7 and game.touch_zoom.minus_button.custom_minimum_size.y>=100.7,"Zoom targets use the requested 70% size at a scaled canvas")
	var gui: Vector2=game.touch_zoom.plus_button.get_global_rect().get_center()
	var event:=InputEventScreenTouch.new();event.index=0;event.position=gui;event.pressed=true
	suite.expect(not game.touch_zoom.handle(event),"A touch button retains ordinary GUI event routing")
	game._toggle_user_pause()
	var paused_time: float=game.world.time
	var transport_time: float=game.world.transport_clock
	var paused_random: int=game.world.rng.state
	game._physics_process(1.0/60)
	suite.expect(game.user_paused and game.world.time==paused_time and game.world.transport_clock==transport_time and game.world.rng.state==paused_random,"Native Pause freezes actual biology and particle transport without changing random streams")
	game._zoom_at(middle,1.25)
	suite.expect(game.user_paused and game.world.time==paused_time,"Zoom remains available while paused")
	game._toggle_user_pause();game._physics_process(1.0/60)
	suite.expect(not game.user_paused and game.world.time>paused_time,"Native Resume advances actual simulation again")
	var client=IsolatedClient.new()
	suite.root.add_child(client);client.set_process(false);client.set_physics_process(false)
	client.music.enabled=false;client.music.player.stop()
	client.epoch=2;client.user_paused=true
	client.world.revision=10;client.world.time=10
	client._snapshot({"epoch":2,"tick":11,"warming":false})
	client._snapshot({"epoch":2,"tick":12,"warming":false})
	suite.expect(client.world.revision==10 and client.world.time==10 and client.paused_snapshot.tick==12,"Paused browser keeps one latest snapshot while preserving its displayed time")
	client._snapshot({"epoch":1,"tick":99,"warming":false})
	suite.expect(client.paused_snapshot.tick==12,"An old authority epoch cannot replace the buffered live state")
	client._queue_command("install",{"kind":"propulsion","angle":0})
	suite.expect(client.commands.is_empty(),"Paused browser cannot submit edits from a frozen view")
	client.paused_snapshot={};client.connected=true;client.received_usec=Time.get_ticks_usec()
	client.world.player.previous_position=client.world.player.position-Vector2(10,0)
	client.settings_panel.show()
	client._toggle_user_pause()
	suite.expect(not client.settings_panel.visible,"Browser Resume closes its settings menu")
	suite.expect(not client.user_paused and client.received_usec==0,"Quick Resume cannot rewind interpolation before a new snapshot arrives")
	client.connected=false;client.invitation="accepted-fixture-key";client.invite_input.text=client.invitation
	client._welcome({"token":"a".repeat(64),"epoch":2,"sequence":0,"edit":0,"seed":9,"habitat":preload("res://scripts/network/state_codec.gd").new().capture(client.world.habitat_geometry)})
	suite.expect(client.connected and client.loading_world and client.login.visible and not client.invite_input.visible and not client.join_button.visible and client.invitation=="","Accepted authentication becomes a loading status with no key entry or sign-in button")
	var attempts: int=client.connection_attempts;client._connect()
	suite.expect(client.connection_attempts==attempts and client.connected,"Repeated sign-in cannot restart an authenticated camera preparation")
	var incoming=preload("res://scripts/simulation.gd").new(9,0,false)
	incoming.cells=[incoming.player];incoming.player.id=client.world.player.id
	incoming.player.position=Vector2(3000,1200);incoming.player.previous_position=Vector2(1800,1200);incoming.player.activity=0
	var message={"epoch":2,"tick":20,"time":20,"graph":preload("res://scripts/network/state_codec.gd").new().capture({"cells":incoming.cells,"player":incoming.player,"lineage":incoming.lineage,"evolution":incoming.evolution}),"flow":incoming.fluid.velocity,"acid":incoming.acidity.values,"sounds":incoming.sound_events,"sound_sequence":0,"sparks":incoming.reaction_sparks,"sequence":0,"edit":0,"particles":PackedByteArray(),"world_id":"camera-fixture"}
	var warming: Dictionary=message.duplicate();warming.warming=true;client._snapshot(warming)
	suite.expect(client.loading_world and client.login.visible and not client.invite_input.visible and not client.join_button.visible,"Initial camera preparation preserves accepted sign-in presentation")
	client.camera_locked=false;client.camera_rotation=1;client.camera_offset=Vector2(80,30);client._snapshot(message)
	suite.expect(not client.login.visible and not client.loading_world and client.connection_stage=="ready","First complete world snapshot dismisses loading automatically")
	client._update_world(1)
	suite.expect(client.camera_initialized and client.camera_locked and client.camera_rotation==0,"First real snapshot resets stale free-view state even if the server cell ID matches the local placeholder")
	suite.expect(client.views.has(client.world.player.id) and client.views[client.world.player.id].position.length()<.005,"A coarse server cell stays rendered at the follow center throughout browser interpolation")
	client._toggle_camera();client.free_camera=Vector2(600,600);message.tick=21;client._snapshot(message)
	suite.expect(not client.camera_locked and client.free_camera==Vector2(600,600),"Later snapshots preserve the user's unlocked free view")
	message.tick=22;message.graph=preload("res://scripts/network/state_codec.gd").new().capture({"cells":[],"player":incoming.player,"lineage":incoming.lineage,"evolution":incoming.evolution})
	client._snapshot(message);client._toggle_camera()
	suite.expect(client.camera_locked and client.views.has(client.world.player.id) and client.views[client.world.player.id].position.length()<.005,"Refocus immediately draws the owned cell even when the prior camera snapshot omitted it")
	var observer=preload("res://scripts/cell.gd").new(71);observer.position=Vector2(800,1400);observer.previous_position=observer.position
	incoming.player.dead=true;message.tick=23;message.graph=preload("res://scripts/network/state_codec.gd").new().capture({"cells":[observer],"player":incoming.player,"focus":observer,"lineage":incoming.lineage,"evolution":incoming.evolution})
	client._snapshot(message)
	if not client.camera_locked:client._toggle_camera()
	client._update_world(1)
	suite.expect(client.world.player.dead and client._follow_cell().id==71 and client.views[71].position.length()<.005,"A dead owned lineage follows an existing living observer body without changing ownership")
	client._queue_command("install",{"kind":"propulsion","angle":0})
	suite.expect(client.commands.is_empty(),"Camera observation grants no authority to edit the observed body")
	client.touch_zoom.enabled=true;client.touch_zoom.layout()
	suite.expect(client.touch_zoom.follow_button.text=="Follow" and client.touch_zoom.follow_button.button_pressed and client.touch_zoom.follow_button.self_modulate.a==1,"Follow has a fixed label and highlighted active state")
	client._toggle_camera();client.touch_zoom.layout()
	suite.expect(not client.touch_zoom.follow_button.button_pressed and client.touch_zoom.follow_button.self_modulate.a<1,"Inactive Follow is dim without changing its label")
	var host=preload("res://scripts/network/world_host.gd").new();host.world=incoming;host.world.cells=[observer]
	host.accounts={"private-fixture-account":{"selected":incoming.player.id,"current":incoming.player,"root":incoming.player.lineage_id(),"lineage":incoming.lineage}}
	var peer={"account":"private-fixture-account"}
	var chosen=host._focus(peer)
	suite.expect(chosen==observer and host.accounts[peer.account].selected==incoming.player.id and host.world.cells.size()==1,"Authority chooses an existing live camera target without adopting, creating or reviving a body")
	host.free()
	client.queue_free()
	game.queue_free();await suite.process_frame
