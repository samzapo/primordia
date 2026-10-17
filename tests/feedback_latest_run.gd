extends SceneTree
var assertions:=0
var failures:=0
func check(ok: bool,why: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var scene=load("res://scenes/pond.tscn").instantiate();root.add_child(scene)
 await process_frame;await process_frame
 scene.set_process(false);scene.set_physics_process(false);scene.preferences.music_volume=0
 var sim=scene.world;sim.server_mode=true;sim.automatic_reproduction=false
 await internal_and_investment(scene)
 var cell=sim.player
 scene.build_open=true;scene.cell_ui.context={};scene.cell_ui.sync(0)
 check(not scene.cell_ui.edit_hint.visible,"No irrelevant Tab hint remains after the interaction closes")
 check(scene.cell_ui.mobile_resources.visible and scene.cell_ui.mobile_stocks.text.contains("AP %d" % sim.evolution.points),"Desktop construction shows AP supply, not just its price")
 scene.build_open=false;scene.cell_ui.sync(0)
 check(not scene.cell_ui.mobile_resources.visible,"Desktop resource strip leaves the ordinary world uncluttered")
 var sibling=sim.Cell.new(777,cell.position+Vector2(600,0));sibling.lineage=cell.lineage_id();sim.cells.append(sibling)
 sim.lineage.register(sibling,cell.id,1,"living",sim.time)
 sim.remote_client=true;sim.command_sink=func(_action,_args):pass
 scene.camera_locked=false;scene.free_camera=cell.position+Vector2(300,200);scene._update_world(1)
 var camera: Vector2=scene.render_camera
 check(scene._switch_family(sibling.id),"A family switch can be queued through the normal command")
 check(sim.player==cell and not scene.camera_locked and scene.render_camera==camera,"Pending family switch keeps the displayed view instead of snapping to the old body")
 var organ: Dictionary={"kind":"toxin","hp":25.0,"max_hp":25.0,"scale":1.0,"mutation":"","blocked":0.0,"burst_clock":.375}
 cell.energy=100;cell.biomass=20
 var status=preload("res://scripts/organelle_status.gd").state(sim,cell,organ)
 check(absf(status.progress-.5)<.000001 and status.label.begins_with("Recharging"),"Readiness ring follows the actual organ cooldown")
 cell.energy=0
 status=preload("res://scripts/organelle_status.gd").state(sim,cell,organ)
 check(status.depleted and status.label.contains("ATP"),"Energy-starved glands have an explicit state and dimmed presentation")
 for point in [Vector2.ZERO,Vector2(1,1),Vector2(-1,1),Vector2(.5,-.2)]:
  var wheel=preload("res://scripts/lineage_color_wheel.gd")
  check(wheel.disc_to_square(wheel.square_to_disc(point)).distance_to(point)<.00001,"HSV disc reaches the complete saturation/value range")
 scene.palette.open();await process_frame;await process_frame
 check(scene.palette.opened and scene.palette.wheel.size.x==scene.palette.wheel.size.y,"Pause opens a circular color picker")
 scene.palette.close();scene.queue_free();await process_frame
 print("FEEDBACK LATEST: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)

func internal_and_investment(scene) -> void:
 var sim=scene.world
 for mobile in [false,true]:
  scene.touch_zoom.enabled=mobile
  scene.perception="exteroception";scene.build_open=false;scene.user_paused=false
  scene.manual_zoom=5;scene._update_world(1);scene.cell_ui.sync(0)
  check(scene.cell_ui.interior.visible and scene.cell_ui._hit_candidates(scene.cell_ui.screen_at({"kind":"chemistry"})).any(func(item):return item.target.kind=="chemistry"),"The factory remains clickable from outside on both platforms")
  scene.cell_ui.open_context({"kind":"chemistry"})
  scene._toggle_build();scene.cell_ui.open_context({"kind":"chemistry"})
  check(scene.build_open and scene.cell_ui.choices[0].kind=="mitochondrion" and scene.cell_ui.choices[1].kind=="photosynthesis","Internal organ choices remain available without a permanent screen label")
  scene._select(12)
  check(scene.perception=="interoception" and scene.selected==12 and scene.camera_locked,"Selecting mitochondria attaches the interior camera on either platform")
  check(scene.camera_motion.active,"Automatic interior entry uses the existing smooth camera transition")
  scene.cell_ui.sync(0)
  check(scene.placement_status().contains("inside") and (scene.cell_ui.cancel_icon.visible if mobile else scene.cell_ui.edit_hint.text.contains("inside")),"Placement guidance and cancellation match internal placement")
  scene._cancel_placement();scene.cell_ui.sync(0)
  check(scene.cell_ui.interior.visible,"The same factory remains visible from inside")
  scene.cell_ui.open_context({"kind":"chemistry"});scene._select(12)
  check(scene.perception=="interoception" and scene.selected==12,"Choosing an internal organ inside does not toggle back outside")
  scene._cancel_placement();scene.perception="exteroception";scene._select(6)
  check(scene.perception=="exteroception","Membrane organ choice does not force an interior view")
  scene._cancel_placement()
  scene.cell_ui.open_context({"kind":"investment"})
  var picker=scene.cell_ui.investment_picker
  check(picker.visible and picker.cards.size()==3 and picker.cards.all(func(card):return card.visible),"All three illustrated strategies appear together")
  check(picker.family.text=="Family" and picker.family.icon!=null and picker.body.icon==null,"Family scope uses a font-independent selection texture")
  for kind in ["grazer","producer","hunter"]:
   picker.choose(kind)
   check(sim.investment.lineages[sim.player.lineage_id()]==kind,"Family strategy is selected directly, never cycled")
  picker._scope("cell");picker.choose("producer")
  check(sim.investment.cells[sim.player.id]=="producer" and picker.inherit.visible,"Body strategy has its own direct choice")
  check(picker.body.text=="This cell" and picker.body.icon!=null and picker.family.icon==null,"Scope marker follows the selected body scope without a font glyph")
  picker.choose("inherit")
  check(not sim.investment.cells.has(sim.player.id) and picker.current()=="inherit","Inherit explicitly removes a body override")
  check(picker.inherit.text=="Inherit" and picker.inherit.icon!=null,"Inherited mode uses the same visible vector mark")
  picker._scope("lineage");picker.choose("manual")
  check(sim.investment.lineages[sim.player.lineage_id()]=="manual" and not picker.inherit.visible,"Manual is explicit and family scope cannot inherit")
  scene.cell_ui.close_context()
  check(not picker.visible,"Closing an interaction dismisses the strategy panel")
  var targets: Array=["assembly","chemistry","nucleus","atp","bud"].map(func(kind):return {"kind":kind})
  scene.cell_ui.open_context({"kind":"overlap","targets":targets})
  check(scene.cell_ui.choices.map(func(choice):return choice.kind)==["assembly_factory","internal_factory","cell_nucleus","atp_store","offspring_store"],"Overlap choices use matching pictures for every cell-local structure")
  check(scene.cell_ui.choices[2].structure_art.get("core")==scene.views[sim.player.id].art.core,"Nucleus picture uses this actual lineage's art")
  scene.cell_ui.close_context()
  var ledger=sim.lineage
  var departed=sim.Cell.new(9000+ledger.total_cells);departed.lineage=ledger.root_id
  ledger.register(departed,sim.player.id,4,"living",sim.time)
  var lifetime: int=ledger.total_cells;ledger.died(departed,sim)
  scene.cell_ui.open_context({"kind":"lineage"})
  check(scene.cell_ui.choices.all(func(choice):return choice.get_meta("family_id",-1)!=departed.id),"Desktop and mobile family menus never list deceased relatives")
  check(scene.cell_ui.choices[0].caption=="Generation 4" and scene.cell_ui.choices[0].description.contains("%d total" % lifetime),"Both platforms show generation and lifetime count after a death")
  scene.cell_ui.close_context()
  scene._finish_build()
 scene.touch_zoom.enabled=false;scene.build_open=false
