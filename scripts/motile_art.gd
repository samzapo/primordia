extends MultiMeshInstance2D
## Local cosmetic clock, independent of authoritative snapshot cadence.
## Geometry and organ existence still come from the current server cell.
static var strip: ArrayMesh
static var ink: ShaderMaterial
static func set_clock(clock: float) -> void:
 if ink!=null:ink.set_shader_parameter("clock",clock)
var revision:=-1
var detail:=false
func _ready() -> void:
 if strip==null:
  strip=ArrayMesh.new()
  var vertices:=PackedVector3Array();var uv:=PackedVector2Array();var indices:=PackedInt32Array()
  for i in 33:
   for side in 2:vertices.append(Vector3(i/32.0,side,0));uv.append(Vector2(i/32.0,side))
  for i in 32:
   var n:=i*2
   indices.append_array(PackedInt32Array([n,n+1,n+2,n+1,n+3,n+2]))
  var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
  arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
  strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 if ink==null:
  ink=ShaderMaterial.new();ink.shader=preload("res://shaders/motile_art.gdshader")
 material=ink
 multimesh=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_2D
 multimesh.use_custom_data=true;multimesh.mesh=strip
func sync(cell,full_detail: bool,_clock: float,world) -> void:
 if revision==cell.render_revision and detail==full_detail:return
 revision=cell.render_revision;detail=full_detail
 var strokes: Array=[]
 for organ in cell.organs:
  if organ.kind in ["propulsion","cilia"]:
   var at: Vector2=cell.organ_local_position(organ)
   var heading: float=cell.organ_normal(organ).angle()
   var depleted: bool=preload("res://scripts/organelle_status.gd").state(world,cell,organ).depleted
   var shade: float=-1 if depleted else 1
   var phase: float=fposmod(cell.id*.731+organ.id*.9,TAU)
   if organ.kind=="propulsion":
    strokes.append([Transform2D(heading,Vector2.ONE*organ.scale,0,at),Color(0,phase,43,8*shade)])
   else:
    var count:=5 if detail else 3
    for strand in count:
     var base: Vector2=Vector2(0,(strand-(2 if detail else 1))*5.0).rotated(heading)*organ.scale
     strokes.append([Transform2D(heading,Vector2.ONE*organ.scale,0,at+base),Color(1,strand*.9+phase,24,3.5*shade)])
  elif organ.kind=="feeding" and detail:
   var lip:=preload("res://scripts/visuals.gd").oral_path(cell,organ.a)
   var reach: float=minf(6,cell.radius*.13)
   var width: float=minf(5,cell.radius*.10)*.24
   for i in range(2,23,3):
    var heading: float=cell.local_normal(organ.a-.5+i/24.0).angle()
    strokes.append([Transform2D(heading,lip[i]),Color(2,fposmod(i+cell.id*.731,TAU),reach,width)])
 var bound: float=cell.extent()+100
 multimesh.custom_aabb=AABB(Vector3(-bound,-bound,-1),Vector3(bound*2,bound*2,2))
 multimesh.instance_count=strokes.size()
 for i in strokes.size():
  multimesh.set_instance_transform_2d(i,strokes[i][0])
  multimesh.set_instance_custom_data(i,strokes[i][1])
