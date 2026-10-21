extends RefCounted
## Fixed world-size landmarks. Fit positions to the whole cytoplasm, never shrink art.
const REFERENCE:=96.0
const NUCLEUS:=19.0
const FACTORY:=16.0
const KEYS:=["nucleus","assembly","chemistry","receptors","bud","atp"]
const PREFERRED:=[Vector2(-.08,-.05),Vector2(-.48,.35),Vector2(.5,.20),Vector2(.05,.63),Vector2(-.45,-.48),Vector2(.40,-.48)]
static var cache: Dictionary={}
static var cached_grid: ArrayMesh
static func radius(kind: String) -> float:return NUCLEUS if kind=="nucleus" else FACTORY
static func layout(cell) -> Dictionary:
 var id: int=cell.get_instance_id()
 var points: PackedVector2Array=cell.membrane.points
 if cache.has(id) and cache[id].points==points:return cache[id].layout.duplicate()
 var bound:=Rect2(points[0],Vector2.ZERO)
 for p in points:bound=bound.expand(p)
 var candidates: Array=[]
 for y in range(1,10):
  for x in range(1,10):
   var p: Vector2=bound.position+bound.size*Vector2(x/10.0,y/10.0)
   if not Geometry2D.is_point_in_polygon(p,points):continue
   var clearance:=INF
   for i in points.size():clearance=minf(clearance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,points[i],points[(i+1)%points.size()])))
   candidates.append({"p":p,"clearance":clearance})
 var result: Dictionary={"radius":REFERENCE}
 var used: Array=[]
 for k in KEYS.size():
  var preferred: Vector2=bound.get_center()+bound.size*PREFERRED[k]*.65
  var best:=Vector2.ZERO;var best_score:=-INF
  for c in candidates:
   var separation: float=c.clearance-radius(KEYS[k])*.8
   for prior in used:separation=minf(separation,c.p.distance_to(prior.p)-radius(KEYS[k])-prior.r-3)
   var score: float=minf(separation,8)*5-c.p.distance_to(preferred)*.55
   if score>best_score:best_score=score;best=c.p
  if k==0 and Geometry2D.is_point_in_polygon(Vector2(-6,-4),points):best=Vector2(-6,-4)
  result[KEYS[k]]=best
  used.append({"p":best,"r":radius(KEYS[k])})
 if cache.size()>=64:cache.clear()
 cache[id]={"points":points.duplicate(),"layout":result}
 return result.duplicate()

static func grid() -> ArrayMesh:
 if cached_grid!=null:return cached_grid
 # One reusable tessellated texture quad lets distant cached cells bend on GPU.
 var vertices:=PackedVector2Array();var uv:=PackedVector2Array();var indices:=PackedInt32Array()
 for y in 17:
  for x in 17:
   uv.append(Vector2(x,y)/16);vertices.append((Vector2(x,y)/16-Vector2.ONE*.5)*2)
 for y in 16:
  for x in 16:
   var a:=y*17+x
   indices.append_array(PackedInt32Array([a,a+1,a+18,a,a+18,a+17]))
 var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
 cached_grid=ArrayMesh.new();cached_grid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 return cached_grid
