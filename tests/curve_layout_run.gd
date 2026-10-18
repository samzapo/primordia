extends SceneTree
const Layout=preload("res://scripts/current_curve_layout.gd")
class Oracle:
 extends RefCounted
 var gap: float
 var segments: Array=[]
 func _init(clearance: float) -> void:gap=clearance
 func reserve(points: PackedVector2Array,owner: int=-1) -> void:
  if owner>=0:segments=segments.filter(func(edge):return edge.owner!=owner)
  for i in range(1,points.size()):segments.append({"a":points[i-1],"b":points[i],"owner":owner})
 func accept(points: PackedVector2Array,owner: int=-1) -> bool:
  for i in range(1,points.size()):
   var a:=points[i-1];var b:=points[i]
   if not a.is_finite() or not b.is_finite():return false
   for j in range(1,i-1):
    if Geometry2D.segment_intersects_segment(a,b,points[j-1],points[j])!=null:return false
   for edge in segments:
    if owner>=0 and edge.owner==owner:continue
    if Geometry2D.segment_intersects_segment(a,b,edge.a,edge.b)!=null:return false
    for pair in [[a,edge.a,edge.b],[b,edge.a,edge.b],[edge.a,a,b],[edge.b,a,b]]:
     if pair[0].distance_to(Geometry2D.get_closest_point_to_segment(pair[0],pair[1],pair[2]))<gap:return false
  reserve(points,owner)
  return true
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var random:=RandomNumberGenerator.new();random.seed=73153
 for gap in [0.0,.01,1.0,5.0,20.0,150.0]:
  var fast=Layout.new(gap);var exact=Oracle.new(gap)
  for trial in 180:
   var points:=PackedVector2Array()
   var origin:=Vector2(random.randf_range(-400,400),random.randf_range(-400,400))
   var count:=33 if trial%19==0 else random.randi_range(2,9)
   var direction:=Vector2.from_angle(random.randf()*TAU)
   for i in count:
    if trial%3==0:points.append(origin+direction*i*12+direction.orthogonal()*sin(i*.15)*9)
    else:points.append(origin+Vector2(random.randf_range(-40,40),random.randf_range(-40,40)))
   var owner:=trial%13 if trial%4!=0 else -1
   if trial%7==0:
    fast.reserve(points,owner);exact.reserve(points,owner)
   else:
    check(fast.accept(points,owner)==exact.accept(points,owner),"Indexed curve admission matches all-pairs geometry at gap %s, sample %d" % [gap,trial])
  var bad:=PackedVector2Array([Vector2.ZERO,Vector2(NAN,1)])
  check(not fast.accept(bad),"Non-finite geometry is rejected")
 var layout=Layout.new(2)
 check(layout.accept(PackedVector2Array([Vector2(-10,0),Vector2(10,0)]),7),"First complete path is accepted")
 check(layout.accept(PackedVector2Array([Vector2(-10,100),Vector2(10,100)]),7),"An owner can move its reserved path")
 check(layout.accept(PackedVector2Array([Vector2(0,-10),Vector2(0,10)]),8),"The replaced old path leaves no stale obstacle")
 check(not layout.accept(PackedVector2Array([Vector2(0,90),Vector2(0,110)]),9),"The replacement still prevents crossings")
 check(not Layout.new(1).accept(PackedVector2Array([Vector2(0,0),Vector2(10,10),Vector2(0,10),Vector2(10,0)])),"Self-crossing complete paths are rejected")
 var budget=preload("res://scripts/current_curve_budget.gd").new()
 check(budget.limits()==Vector2i(64,32),"Desktop starts at full current-art density")
 for tick in 10:budget.observe(100000,tick)
 check(budget.limits()==Vector2i(64,32),"Desktop does not adapt its density")
 check(budget.configure(true) and budget.limits()==Vector2i(24,12),"Mobile begins with a bounded full-length curve budget")
 check(not budget.observe(100000,0),"A single expensive rebuild does not change quality")
 check(budget.observe(100000,.1) and budget.limits()==Vector2i(16,8),"Sustained costly rebuilds lower mobile work")
 check(not budget.observe(100000,.2),"A second quality change is rate limited")
 check(budget.observe(100000,.4) and budget.limits()==Vector2i(8,4),"Persistent cost reaches a small nonzero mobile budget")
 for tick in 10:budget.observe(100000,1+tick)
 check(budget.limits()==Vector2i(8,4),"Current art never disappears under repeated overload")
 check(not budget.observe(2000,30) and not budget.observe(2000,37.9),"Recovery waits for sustained inexpensive rebuilding")
 check(budget.observe(2000,38) and budget.limits()==Vector2i(16,8),"Recovery restores one quality step")
 check(budget.observe(2000,46) and budget.limits()==Vector2i(24,12),"Stable headroom restores the initial mobile quality")
 check(budget.configure(false) and budget.limits()==Vector2i(64,32),"Leaving touch mode restores desktop density")
 budget.configure(true);budget.observe(100000,0);budget.observe(100000,.1);budget.observe(100000,.2);budget.observe(100000,.4)
 var flow=preload("res://scripts/flow_view.gd").new();root.add_child(flow);flow.curve_budget=budget
 for id in 18:flow.crest_tracks[id]={"input":id>=12,"retiring":false,"opacity":.75}
 flow._budget_tracks()
 check(flow.crest_tracks.values().filter(func(sample):return not sample.retiring and not sample.input).size()==8 and flow.crest_tracks.values().filter(func(sample):return not sample.retiring and sample.input).size()==4,"Only the target number of ordinary/gold tracks continue updating")
 check(flow.crest_tracks.size()==18 and flow.crest_tracks.values().all(func(sample):return sample.opacity==.75),"Excess curves retain their artwork for the existing fade, without popping away")
 flow.free()
 print("CURVE LAYOUT: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
