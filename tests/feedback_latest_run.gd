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
