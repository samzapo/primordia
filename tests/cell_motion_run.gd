extends SceneTree
const Motion=preload("res://scripts/cell_motion.gd")
const Layout=preload("res://scripts/factory_layout.gd")
const Cell=preload("res://scripts/cell.gd")
var assertions:=0
var failures:=0
func check(ok: bool,description: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(description)
func _initialize() -> void:
 var cell=Cell.new()
 var points: PackedVector2Array=cell.membrane.points.duplicate()
 var stocks:=Vector3(cell.energy,cell.biomass,cell.age)
 var motion=Motion.new()
 motion.sync(cell,0,Transform2D.IDENTITY)
 var at:=Vector2(30,8)
 var initial:=motion.point(at)
 motion.sync(cell,.12,Transform2D.IDENTITY)
 check(initial.distance_to(motion.point(at))>.01,"Local gel animates while server cell and age are stationary")
 check(cell.membrane.points==points and Vector3(cell.energy,cell.biomass,cell.age)==stocks,"Cosmetic animation cannot mutate membrane, stocks or time")
 var frozen:=motion.point(at)
 motion.sync(cell,.12,Transform2D.IDENTITY)
 check(frozen==motion.point(at),"Pause-aware cosmetic clock freezes the complete visible shape")
 var prior_radius:=motion.radius_at(.7)
 for i in cell.membrane.points.size():cell.membrane.points[i]*=1.15
 cell.membrane.invalidate()
 motion.sync(cell,.12,Transform2D.IDENTITY)
 check(absf(prior_radius-motion.radius_at(.7))<.0001,"A new snapshot retargets from the current radius without a position jump")
 motion.sync(cell,.14,Transform2D.IDENTITY)
 check(absf(prior_radius-motion.radius_at(.7))>0 and absf(prior_radius-motion.radius_at(.7))<cell.radius*.15,"Shape correction develops between rendered frames")
 var state:=Motion.spring(10,15,3,.08)
 var next:=Motion.spring(state.x,15,state.y,.13)
 var whole:=Motion.spring(10,15,3,.21)
 check(next.distance_to(whole)<.00001,"Closed-form spring response is independent of rendered frame subdivision")
 var late:=Motion.spring(10,15,3,20)
 check(absf(late.x-15)<.00001 and absf(late.y)<.00001,"Long gaps settle safely without unstable catch-up steps")
 var complete:=true
 for i in 100:
  motion.sync(cell,.15+i/60.0,Transform2D(.3,Vector2(17,22)))
  for ray in 8:complete=complete and motion.point(Vector2.from_angle(ray*TAU/8)*cell.radius).is_finite()
 check(complete,"Local motion remains finite across sparse authority updates")
 var body_layout:=Layout.layout(cell)
 check(body_layout.radius==96 and Layout.NUCLEUS==19 and Layout.FACTORY==16,"Factory and nucleus artwork sizes are independent constants")
 var inside:=true;var separate:=true
 for key in Layout.KEYS:
  inside=inside and Geometry2D.is_point_in_polygon(body_layout[key],cell.membrane.points)
  for other in Layout.KEYS:
   if key!=other:separate=separate and body_layout[key].distance_to(body_layout[other])>3
 check(inside and separate,"Factory positions are distinct and fit inside the cytoplasm")
 var span:=Rect2(body_layout.nucleus,Vector2.ZERO)
 for key in Layout.KEYS:span=span.expand(body_layout[key])
 check(span.size.x>cell.radius*.75 and span.size.y>cell.radius*.75,"Factories spread through the cell instead of clustering around a shortest-radius circle")
 for i in cell.membrane.points.size():cell.membrane.points[i]*=2
 cell.radius*=2;cell.membrane.invalidate()
 var grown:=Layout.layout(cell)
 check(grown.radius==body_layout.radius and grown.chemistry.distance_to(grown.assembly)>body_layout.chemistry.distance_to(body_layout.assembly),"Growth distributes factories farther without scaling their artwork")
 cell.membrane.points[5]*=.45;cell.membrane.invalidate()
 check(Layout.layout(cell).radius==grown.radius,"A local membrane dent cannot shrink any factory")
 var mouth=cell.organs.filter(func(o):return o.kind=="feeding")
 var mesh:=Layout.grid()
 check(mesh.get_surface_count()==1 and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==289,"Distant cells use one reusable tessellated cached-art mesh")
 var outline: PackedVector2Array=cell.membrane.outline()
 motion.sync(cell,3,Transform2D.IDENTITY)
 motion.capture_raster(outline)
 check(motion.raster_radii.size()==64 and motion.outline(outline,true).size()==outline.size(),"Cached raster and detailed body expose the same animated boundary")
 var reference:=Motion.radii(outline)
 var saved: PackedByteArray=motion.texture.get_image().get_data()
 motion.sync(cell,3.1,Transform2D.IDENTITY)
 check(saved==motion.texture.get_image().get_data(),"Frame-local animation does not re-upload unchanged membrane geometry")
 check(reference.size()==64 and reference[0]>0,"Periodic radial lookup has a finite forward seam")
 var before_growth:=motion.radius_at(.4)
 for i in cell.membrane.points.size():cell.membrane.points[i]*=1.7
 cell.membrane.invalidate()
 motion.sync(cell,3.1,Transform2D.IDENTITY)
 check(absf(motion.radius_at(.4)-before_growth)<.001,"A large growth snapshot starts at the existing visible membrane instead of popping")

 print("CELL MOTION/LAYOUT: %d assertions, %d failures" % [assertions,failures])
 quit(0 if failures==0 else 1)
