extends RefCounted
## Current shared interface contract; replaces retired desktop AP/resize overlays.
const Offline=preload("res://tests/status_ui_run.gd")
var host
func expect(ok: bool,text: String) -> void:host.expect(ok,text)
func pointer(game,at: Vector2,touch: bool,pressed: bool) -> void:
 var event: InputEvent
 if touch:
  event=InputEventScreenTouch.new();event.index=0
 else:
  event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
 event.position=at;event.pressed=pressed;game._input(event)
func layout_key(game) -> Array:
 var ui=game.cell_ui
 return [game.controls.bar.visible,game.controls.bar.get_global_rect(),game.controls.perception_button.text,
  ui.mobile_resources.visible,ui.mobile_resources.get_global_rect(),ui.mobile_hide.visible,ui.mobile_tray.visible,ui.mobile_tray.get_global_rect(),
  ui.choices.map(func(c):return [c.caption,c.kind,c.custom_minimum_size,c.get_global_rect()]),
  ui.family_picker.visible,ui.family_picker.get_global_rect(),ui.investment_picker.visible,ui.investment_picker.get_global_rect()]
func run(suite) -> void:
 host=suite
 var previous_size: Vector2i=suite.root.size;var previous_scale: Vector2i=suite.root.content_scale_size
 for name in ["cell_interface","family_picker","investment_picker","lineage_palette","particle_inspector","cell_interior"]:
  expect(not FileAccess.get_file_as_string("res://scripts/"+name+".gd").contains("touch_enabled"),"Shared UI cannot fork on input capability: "+name)
 var guide: Dictionary=preload("res://scripts/player_guide.gd").data()
 expect(guide.gameplay.touch.size()==1 and guide.gameplay.desktop.size()==1 and guide.gameplay.touch[0].id=="camera" and guide.gameplay.desktop[0].id=="camera","Only camera help differs; every world interaction uses one guide list")
 var reference: Dictionary={}
 for viewport in [Vector2i(393,740),Vector2i(1280,720)]:
  for touch in [false,true]:
   suite.root.size=viewport;suite.root.content_scale_size=Vector2i.ZERO
   var game=Offline.OfflineClient.new();game.use_particle_pool=false;suite.root.add_child(game)
   game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
   game.connected=true;game.connection_stage="ready";game.loading_world=false;game.login.hide()
   game.preferences.hud_scale=1;game.controls.touch_enabled=touch;game.controls.pixels=1
   game.world.player.biomass=300;game.world.player.energy=100;game.manual_zoom=3;game.ui_time=.3
   game._toggle_build();game._layout();game._update_world(1);game.cell_ui.sync(0)
   for context in ["nucleus","assembly","chemistry","receptors","bud","division","investment","lineage"]:
    game.cell_ui.open_context({"kind":context});game.cell_ui.sync(0)
    await suite.process_frame;await suite.process_frame;game.cell_ui.sync(0)
    var key: String=str(viewport)+context
    var state:=layout_key(game)
    if not touch:reference[key]=state
    else:expect(state==reference[key],"Identical mouse/touch widgets, actions and layout: "+context+" "+str(viewport))
    expect(game.controls.bar.visible and game.cell_ui.mobile_resources.visible,"Shared controls and resources stay available on both inputs")
    if context not in ["investment","lineage"]:expect(game.cell_ui.choices.all(func(c):return c.get_parent()==game.cell_ui.mobile_flow),"Every direct choice uses the one shared tray")
   game.cell_ui.open_context({"kind":"chemistry"});game.cell_ui.sync(0)
   var choices: Array=game.cell_ui.choices.filter(func(c):return c.kind=="mitochondrion")
   expect(choices.size()==1,"The shared factory offers internal organelles")
   choices[0].pressed.emit();game._update_world(1);game.cell_ui.sync(0)
   expect(game.selected==game.Simulation.KINDS.find("mitochondrion") and game.perception=="interoception","Selecting an internal organ enters the same placement mode")
   var at: Vector2=game.views[game.world.player.id].get_global_transform_with_canvas().origin+Vector2(4,3)
   pointer(game,at,touch,true);pointer(game,at,touch,false)
   expect(game.inflight.get("action","")=="install" and game.inflight.get("args",{}).get("kind","")=="mitochondrion","Mouse/touch placement sends the same immediate authoritative action")
   expect(game.placement_feedback.entries.size()==1,"Both inputs show the same pending placement and ripple")
   game.cell_ui.cancel_icon.pressed.emit();expect(game.selected==-1,"The shared held icon cancels placement")
   sequence_clear(game)
   if not touch:
    game.cell_ui.close_context();game._update_world(1);game.cell_ui.sync(0)
    at=game.views[game.world.player.id].get_global_transform_with_canvas().origin
    var offset: Vector2=game.camera_offset
    pointer(game,at,false,true)
    var drag:=InputEventMouseMotion.new();drag.position=at+Vector2(60,20);drag.relative=Vector2(60,20);game._input(drag)
    pointer(game,drag.position,false,false)
    expect(game.camera_offset!=offset and not game.camera_dragging and game.cell_ui.context.is_empty(),"Left-drag pans without activating an underlying factory")
    var zoom: float=game.manual_zoom
    var wheel:=InputEventMouseButton.new();wheel.position=at;wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;game._input(wheel)
    expect(game.manual_zoom>zoom,"Desktop wheel zoom remains available over the cell")
   if viewport.x==393:
    suite.root.size=Vector2i(393,400);game.preferences.hud_scale=1.75
    for i in 11:
     var relative=game.Simulation.Cell.new(100+i,game.world.player.position);relative.lineage=game.world.player.lineage_id()
     game.world.cells.append(relative);game.world.lineage.register(relative,game.world.player.id,1,"living",game.world.time)
    game._layout();game.cell_ui.open_context({"kind":"lineage"});game.cell_ui.sync(0)
    for i in 4:await suite.process_frame
    game.cell_ui.sync(0)
    var picker=game.cell_ui.family_picker
    var area: Rect2=picker.grid.get_child(0).get_global_rect().intersection(picker.scroll.get_global_rect())
    expect(area.has_area() and picker.scroll.get_v_scroll_bar().max_value>picker.scroll.get_v_scroll_bar().page,"A large family offers real scrolling in a short, enlarged-text view "+str({"choices":picker.grid.get_child_count(),"visible":picker.visible,"context":game.cell_ui.context,"build":game.build_open,"area":area,"scroll":picker.scroll.get_global_rect(),"max":picker.scroll.get_v_scroll_bar().max_value,"page":picker.scroll.get_v_scroll_bar().page}))
    var start:=area.get_center();pointer(game,start,touch,true)
    var motion: InputEvent=InputEventScreenDrag.new() if touch else InputEventMouseMotion.new()
    if touch:motion.index=0
    motion.position=start-Vector2(0,45);motion.relative=Vector2(0,-45);game._input(motion);pointer(game,motion.position,touch,false)
    expect(picker.scroll.scroll_vertical>0 and game.inflight.is_empty() and not game.camera_dragging,"Dragging a portrait scrolls the same list without selecting a relative or panning "+str({"value":picker.scroll.scroll_vertical,"inflight":game.inflight,"camera":game.camera_dragging}))
   game.queue_free();await suite.process_frame
 suite.root.content_scale_size=previous_scale;suite.root.size=previous_size
func sequence_clear(game) -> void:
 if not game.inflight.is_empty():game._command_result({"sequence":game.inflight.sequence,"ok":true,"edit":1,"message":"Applied"})
