extends RefCounted
## Small, read-only anatomy portraits; no chemistry poses or extra simulated cells.
const Art=preload("res://scripts/cell_art.gd")
const Visuals=preload("res://scripts/visuals.gd")
static func capture(cell) -> Dictionary:
 var organs: Array=[]
 var synergy: Dictionary=preload("res://scripts/synergy_art.gd").capture(cell)
 var extent: float=cell.extent()
 for organ in cell.organs:
  var at: Vector2=cell.organ_local_position(organ)
  var inherent: bool=organ.kind=="feeding"
  organs.append({"kind":organ.kind,"at":at,"heading":cell.organ_normal(organ).angle(),
   "scale":organ.scale,"mode":organ.mode,"hp":organ.hp/organ.max_hp,
   "inherent":inherent,"mouth":Visuals.oral_path(cell,organ.a) if inherent else PackedVector2Array(),
   "reach":preload("res://scripts/proboscis.gd").reach(cell,organ)/organ.scale if organ.kind=="proboscis" else 27.0,"pulse":organ.consume_flash,"stored":preload("res://scripts/toxin_sac.gd").fraction(organ) if organ.kind=="toxin_sac" else 0.0,"depleted":organ.hp<=0 or (organ.kind in ["feeding","propulsion","cilia","hunting","toxin","poreforming","counterattack","acidifying","neutralizing","regenerative"] and cell.work_capacity()<1)})
  if not inherent:
   var reach:=52.0 if organ.kind=="propulsion" else 32.0 if organ.kind=="cilia" else 30.0 if organ.kind=="hunting" else float(organs[-1].reach) if organ.kind=="proboscis" else 26.0
   extent=maxf(extent,at.length()+reach*organ.scale)
 for i in synergy.roots.size():extent=maxf(extent,preload("res://scripts/synergy_art.gd").hair(synergy,i,cell.radius,cell.age)[-1].length()+cell.radius*.05)
 return {"synergy":synergy,"id":cell.id,"lineage":cell.lineage_id(),"outline":cell.membrane.outline(),
  "radius":cell.radius,"extent":maxf(1,extent),"age":cell.age,"angle":cell.angle,
  "health":cell.health,"hurt":cell.hurt_flash,"organs":organs,"holes":cell.holes.map(func(hole):return {"at":cell.local_point(hole.a),"size":hole.size})}

static func family(sim,ledger) -> Dictionary:
 var result: Dictionary={}
 for cell in ledger.active_family(sim):
  if not cell.dead and cell.health>0 and cell.lineage_id()==ledger.root_id:result[cell.id]=capture(cell)
 return result

static func body(model: Dictionary,art: Dictionary) -> ArrayMesh:
 # Explicit radial triangles retain dents without unsafe polygon triangulation.
 var outline: PackedVector2Array=model.outline
 var points:=PackedVector2Array([Vector2.ZERO])
 var colors:=PackedColorArray([art.colors[2]])
 var indices:=PackedInt32Array()
 for factor in [.84,1.0]:
  for point in outline:
   points.append(point*factor)
   colors.append(art.colors[1].lerp(Color.WHITE,float(model.hurt)*.55) if factor<1 else art.colors[3])
 var n:=outline.size()
 for i in n:
  var next: int=(i+1)%n
  indices.append_array(PackedInt32Array([0,1+i,1+next,1+i,1+n+i,1+n+next,1+i,1+n+next,1+next]))
 var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 return mesh

static func draw(canvas: Node2D,model: Dictionary,art: Dictionary,mesh: ArrayMesh,radius: float) -> void:
 if model.is_empty():return
 var scale: float=radius/model.extent
 var rotation: float=model.angle
 canvas.draw_set_transform(Vector2.ZERO,rotation,Vector2.ONE*scale)
 canvas.draw_mesh(mesh,null)
 preload("res://scripts/synergy_art.gd").draw(canvas,model.get("synergy",{}),model.outline,model.radius,art.colors[1],model.age)
 var safe: float=model.radius
 for point in model.outline:safe=minf(safe,point.length())
 Visuals.nucleus_art(canvas,Vector2(-.12,-.10)*safe,safe*.28*preload("res://scripts/factory_layout.gd").INTERNAL_SCALE,art.core,art.colors,false)
 for hole in model.holes:canvas.draw_circle(hole.at,3+hole.size*6,Color("27325e"))
 for organ in model.organs:
  if organ.inherent:
   canvas.draw_set_transform(Vector2.ZERO,rotation,Vector2.ONE*scale)
   canvas.draw_polyline(organ.mouth,Color("6ee6d4"),minf(5,model.radius*.10),true)
  else:
   var at: Vector2=organ.at.rotated(rotation)*scale
   Visuals.icon(canvas,at,organ.kind,organ.heading+rotation,organ.scale*scale*(preload("res://scripts/factory_layout.gd").INTERNAL_SCALE if organ.kind in ["mitochondrion","toxin_sac"] else 1.0),model.age,organ.mode,organ.pulse,false,0,organ.depleted,float(organ.get("stored",0)),float(organ.get("reach",27)))
   if organ.hp<1:
    canvas.draw_arc(at,19*organ.scale*scale*(preload("res://scripts/factory_layout.gd").INTERNAL_SCALE if organ.kind in ["mitochondrion","toxin_sac"] else 1.0),-PI/2,-PI/2+TAU*maxf(.001,organ.hp),16,Color("fc8c90"),maxf(.7,scale),true)
 canvas.draw_set_transform(Vector2.ZERO)
