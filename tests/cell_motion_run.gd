extends SceneTree
const Motion=preload("res://scripts/cell_motion.gd")
const Layout=preload("res://scripts/factory_layout.gd")
const Cell=preload("res://scripts/cell.gd")
const Offline=preload("res://tests/status_ui_run.gd")
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var cell=Cell.new()
 var points: PackedVector2Array=cell.membrane.points.duplicate()
 var stocks:=Vector3(cell.energy,cell.biomass,cell.age)
 var motion=Motion.new();motion.sync(cell,.2,Transform2D.IDENTITY)
 var scale: Vector2=motion.deformation.get_scale()
 check(absf(motion.deformation.determinant()-1)<.000001,"Squash/stretch preserves represented area")
 check(scale.x>1 and scale.y<1,"One axis stretches while the perpendicular axis compresses")
 check(absf(scale.x-1)<.0061 and absf(scale.y-1)<.0061,"Cosmetic amplitude stays below seven tenths of one percent")
 check(motion.deformation.origin==Vector2.ZERO,"The body does not oscillate away from its center")
 var anchor:=Vector2(30,8);var before:=motion.point(anchor)
 motion.sync(cell,.45,Transform2D.IDENTITY)
 check(before.distance_to(motion.point(anchor))>.001,"Anchor motion advances locally between server snapshots")
 check(cell.membrane.points==points and Vector3(cell.energy,cell.biomass,cell.age)==stocks,"Cosmetic motion cannot mutate physics or resources")
 var held:=motion.point(anchor);motion.sync(cell,.45,Transform2D.IDENTITY)
 check(held==motion.point(anchor),"A held cosmetic clock freezes anchors and body together")
 var normal:=Vector2(.4,.9).normalized();var tangent:=normal.orthogonal()
 check(absf(motion.normal(anchor,normal).dot(motion.deformation.basis_xform(tangent)))<.00001,"External mounts keep the correct transformed membrane normal")
 var state:=Motion.spring(10,15,3,.08);var next:=Motion.spring(state.x,15,state.y,.13)
 check(next.distance_to(Motion.spring(10,15,3,.21))<.00001,"Layout easing is independent of frame subdivision")
 check(Motion.spring(10,15,0,.2).x<15 and absf(Motion.spring(10,15,0,5).x-15)<.00001,"Factory slots settle without oscillatory overshoot")
 var layout:=Layout.layout(cell)
 check(layout.radius==48 and Layout.NUCLEUS==9.5 and Layout.FACTORY==8,"Nucleus and factories retain fixed artwork sizes")
 var fitted:=true;var spread:=true
 for mass in [30,60]:
  var empty=Cell.new();empty.body=mass;empty.biomass=0;empty.substrate=0;empty.oxygen=0;empty.carbon=0;empty.waste=0
  empty.radius=Cell.tissue_radius(empty.storage_volume());empty.membrane=preload("res://scripts/membrane.gd").new(empty.radius,0)
  var small:=Layout.layout(empty)
  for key in Layout.KEYS:
   var at: Vector2=small[key];var clearance:=INF
   for i in empty.membrane.points.size():clearance=minf(clearance,at.distance_to(Geometry2D.get_closest_point_to_segment(at,empty.membrane.points[i],empty.membrane.points[(i+1)%empty.membrane.points.size()])))
   fitted=fitted and clearance>=Layout.footprint(key)
  for i in empty.membrane.points.size():empty.membrane.points[i]*=3
  empty.membrane.invalidate();var large:=Layout.layout(empty)
  for key in Layout.KEYS:spread=spread and (large[key] as Vector2).length()>(small[key] as Vector2).length()+1
 check(fitted,"Every control outline fits inside empty-reserve founder and minimal daughter cells")
 check(spread,"All control anchors spread with body growth while their artwork stays fixed")
 var old: PackedVector2Array=cell.membrane.outline();motion.capture_raster(old);motion.cached=true
 for i in cell.membrane.points.size():cell.membrane.points[i]*=1.1
 cell.membrane.invalidate();motion.sync(cell,.5,Transform2D.IDENTITY)
 check(motion.point(Vector2(cell.radius*1.1,0)).distance_to(motion.deformation*Vector2(cell.radius,0))<.1,"Outside-cache mounts use the displayed cached membrane rather than a newer server boundary")
 root.size=Vector2i(393,740)
 var game=Offline.OfflineClient.new();game.use_particle_pool=false;root.add_child(game)
 game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
 game.connected=true;game.connection_stage="ready";game.loading_world=false;game.login.hide()
 var actual=game.world.player
 for kind in ["mitochondrion","toxin_sac","propulsion","cilia","poreforming"]:actual.add_organ(kind,actual.organs.size()*.8,"graze",false)
 game.manual_zoom=3;game.ui_time=.4;game._update_world(1);game.cell_ui.interior.sync()
 var view=game.views[actual.id]
 check(view.internal_organs.size()==2,"Both installed internal organ kinds live outside the stretched artwork")
 var coherent:=true;var fixed:=true
 for i in 8:
  game.ui_time=.4+i*.1;game._update_world(1);game.cell_ui.interior.sync()
  coherent=coherent and view.body_ink.transform.is_equal_approx(view.motion.deformation)
  for organ in actual.organs:
   if not actual.internal_organ(organ.kind):continue
   var ink: Node2D=view.internal_organs[organ.id]
   coherent=coherent and ink.position.distance_to(view.motion.point(actual.organ_local_position(organ)))<.00001
   fixed=fixed and ink.scale.is_equal_approx(Vector2.ONE)
  coherent=coherent and game.cell_ui.interior.anchors.nucleus.distance_to(view.nucleus_center)<.00001
 check(coherent,"The real body, organ centers, nucleus and clickable controls share the same deformation")
 check(fixed,"Installed internal artwork keeps its dimensions throughout the oscillation")
 view.motion.deformation=Transform2D(0,Vector2(1.25,.8),0,Vector2.ZERO)
 view.body_ink.transform=view.motion.deformation;view._sync_anchor_art();game.cell_ui.interior.sync()
 var stress:=true
 for organ in actual.organs:
  if not actual.internal_organ(organ.kind):continue
  var ink: Node2D=view.internal_organs[organ.id]
  stress=stress and ink.position.distance_to(view.motion.deformation*actual.organ_local_position(organ))<.00001 and ink.scale==Vector2.ONE
 check(stress,"Even an exaggerated diagnostic stretch moves internal centers without stretching their artwork")

 check(view.cytoplasm.get_parent()==view,"Vacuole artwork stays outside the stretched membrane layer")
 var removed: int=actual.organs.filter(func(o):return o.kind=="mitochondrion")[0].id
 actual.organs=actual.organs.filter(func(o):return o.id!=removed);actual.render_revision+=1
 game._update_world(1)
 check(not view.internal_organs.has(removed),"Removed internal organs cannot leave a floating visual behind")
 game.queue_free();await process_frame
 print("CELL MOTION/LAYOUT: %d assertions, %d failures" % [assertions,failures])
 quit(0 if failures==0 else 1)
