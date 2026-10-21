extends SceneTree
var checks:=0
var failures:=0
class OfflineClient extends "res://scripts/network/network_client.gd":
 var sent: Array=[]
 func _load_identity() -> void:pass
 func _save_identity() -> void:pass
 func _poll_network() -> void:pass
 func _connect(_manual: bool=true) -> void:pass
 func _publish_login_geometry() -> void:pass
 func _send(value: Dictionary) -> void:sent.append(value)
 func _empty_remote_world() -> void:
  world=Simulation.new(29,0,false);world.server_mode=true;world.remote_client=true
  world.cells=[world.player];world.particles.clear();world.evolution.sandbox=true
  world.habitat_geometry=Simulation.Habitat.new(29,world.cells);world.habitat_geometry.enabled=false
  world.revision=1;world.command_sink=_queue_command;world.native_render=false;world.native_particle_render_cache=false
func check(ok: bool,text: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(393,740)
 var game=OfflineClient.new();game.use_particle_pool=false;root.add_child(game)
 game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
 root.content_scale_size=Vector2i.ZERO
 game.connected=true;game.connection_stage="ready";game.login.hide();game.loading_world=false
 game.touch_zoom.enabled=true;game.touch_zoom.pixels=1;game.preferences.show_instinct=true
 game.cell_ui.close_context();game.cell_ui.sync(0)
 var feed=game.cell_ui.status_feed
 check(feed.entries.is_empty(),"Initial view and family history do not replay routine notices")
 var relative=game.Simulation.Cell.new(91,game.world.player.position+Vector2(120,0));relative.lineage=game.world.player.lineage_id();relative.generation=1
 game.world.cells.append(relative);game.world.lineage.register(relative,game.world.player.id,1,"living",game.world.time);game.cell_ui.reset()
 check(game._switch_family(91) and feed.entries.is_empty() and game.waiting_for_world(),"The real family-switch path waits quietly with the busy indicator")
 var sequence: int=game.inflight.sequence
 game._command_result({"sequence":sequence,"ok":true,"edit":1,"message":"Applied"})
 game.cell_ui.sync(0)
 check(feed.entries.is_empty() and not game.waiting_for_world(),"A successful family-selection receipt stays silent and clears waiting")
 check(game._queue_command("install",{"kind":"propulsion","angle":1.0}),"Placement sends immediately through the real client queue")
 sequence=game.inflight.sequence
 game._command_result({"sequence":sequence,"ok":false,"edit":1,"message":"Not enough biomass."})
 game.cell_ui.sync(0)
 check(feed.entries.size()==1 and feed.entries[0].tone=="error","A rejected placement creates one actionable error notice")
 var pane: PanelContainer=feed.entries[0].panel
 var edge: Color=pane.get_theme_stylebox("panel").border_color
 check(edge.r>edge.g and pane.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Placement rejection has a red border and never captures taps")
 check(feed.instinct.visible,"Instinct stays in its own pane while a rejection is shown")
 game._message("Not enough biomass.","error")
 check(feed.entries.size()==1,"Repeated failures do not duplicate a notice or extend its life")
 game.cell_ui.sync(1.5)
 check(pane.modulate.a>.45 and pane.modulate.a<.55,"Each notice fades continuously over three seconds")
 game.cell_ui.sync(1.51)
 check(feed.entries.is_empty() and feed.instinct.visible,"Expired notices disappear without replacing Instinct")
 for attempt in 3:
  game.cell_ui.open_context({"kind":"division"})
  for choice in game.cell_ui.choices:
   if choice.has_meta("reproduction_mode"):choice.grab_focus();break
  game.cell_ui.sync(0)
  check(not game.cell_ui.tip_box.visible or not game.cell_ui.tip.text.contains("needs"),"Division readiness cannot reappear in a persistent focus tooltip")
  game.cell_ui._start_reproduction("mitosis")
  sequence=game.inflight.sequence
  game._command_result({"sequence":sequence,"ok":false,"edit":1,"message":"Mitosis needs 84 biomass and 56 ATP, including survival reserves."})
  game.cell_ui.sync(0)
  check(feed.entries.size()==1 and feed.entries[0].tone=="error","Every repeated division refusal uses the bordered feed")
  game.cell_ui.sync(3.01)
  check(feed.entries.is_empty() and not game.cell_ui.tip_box.visible,"Repeated division failure leaves no persistent old message pane")
 game.world.player.energy=0;game.world.player.biomass=0;game.preferences.show_instinct=false;game.cell_ui.sync(0)
 check(feed.starvation.visible and feed.starvation.get_theme_stylebox("panel").border_color.r>.9,"Starvation stays red even when the Instinct readout is hidden")
 game.world.player.energy=30;game.world.player.biomass=18;game.preferences.show_instinct=true;game.cell_ui.sync(0)
 check(not feed.starvation.visible,"Refuelling clears the starvation warning without a repeated message")
 game.settings_panel.show();game._message("One brief notice");game.cell_ui.sync(3.1)
 check(feed.entries.is_empty(),"Notices expire while menus are open instead of returning later")
 game.settings_panel.hide()
 for view in [Vector2i(393,740),Vector2i(1170,2100),Vector2i(740,393),Vector2i(1280,720)]:
  root.size=view;game.touch_zoom.enabled=view.x<1200;game.touch_zoom.pixels=3 if view.x==1170 else 1
  game._layout();game.cell_ui.sync(0);await process_frame;await process_frame;game.cell_ui.sync(0)
  game._queue_command("follow",{"id":92});game.cell_ui.sync(0)
  var visible_area:=Rect2(Vector2.ZERO,Vector2(view))
  check(visible_area.encloses(feed.instinct.get_global_rect()) and visible_area.encloses(feed.waiting.get_global_rect()),"Status and waiting amoeba fit "+str(view)+" actual="+str(game.get_viewport_rect())+" instinct="+str(feed.instinct.get_global_rect())+" waiting="+str(feed.waiting.get_global_rect()))
  check(feed.waiting.visible and not feed.waiting.get_global_rect().intersects(feed.instinct.get_global_rect()),"Bottom-right waiting stays clear of Instinct "+str(view))
  if game.touch_zoom.enabled:check(game.cell_ui.mobile_resources.visible and not game.cell_ui.mobile_resources.get_global_rect().intersects(feed.instinct.get_global_rect()),"Instinct stays above the active mobile resource bar "+str(view))
  sequence=game.inflight.sequence;game._command_result({"sequence":sequence,"ok":true,"edit":1,"message":"Applied"})
 game.connection_stage="connecting";game.connecting=true;game._show_connection("Connecting to the shared pond…")
 check(not game.login.visible and game.status.text.is_empty() and game.waiting_for_world(),"Simple connection progress uses the amoeba instead of a message")
 game.connection_stage="sign_in";game.connecting=false;game._show_connection("Access key rejected.",true)
 check(game.login.visible and game.status.text=="Access key rejected." and not game.waiting_for_world(),"An actionable sign-in failure remains readable")
 game.queue_free();await process_frame
 print("STATUS_UI: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
