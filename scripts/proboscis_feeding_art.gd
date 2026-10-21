extends Node2D
## Cosmetic contact cues, outside cached cell art. Never adds physical particles.
const Medium=preload("res://scripts/medium.gd")
const Art=preload("res://scripts/particle_art.gd")
const Colors=preload("res://scripts/signal_colors.gd")
var game
const MAX_CONTACTS:=256
var contacts: Array=[]
static func anchor(outline: PackedVector2Array,contact: Dictionary) -> Vector2:
 if outline.is_empty():return Vector2.ZERO
 var edge:=posmod(int(contact.get("edge",0)),outline.size())
 return outline[edge].lerp(outline[(edge+1)%outline.size()],clampf(float(contact.get("t",0)),0,1))
static func progress(clock: float,identity: int) -> float:
 return fposmod(clock*1.35+posmod(identity*73,997)/997.0,1.0)
func sync() -> void:
 contacts.clear()
 if game==null:visible=false;return
 for view in game.views.values():
  if contacts.size()>=MAX_CONTACTS:break
  if view.cell.dead:continue
  for organ in view.cell.organs:
   if contacts.size()>=MAX_CONTACTS:break
   if organ.kind!="proboscis" or organ.hp<=0 or not organ.feeding:continue
   var contact: Dictionary=organ.get("proboscis_contact",{})
   if not game.views.has(int(contact.get("cell",-1))):continue
   var donor=game.views[contact.cell]
   if donor.cell.dead:continue
   var base: Vector2=view.transform*view.cell.organ_local_position(organ)
   var hole: Vector2=donor.transform*anchor(donor.cell.membrane.outline(),contact)
   hole=base+Medium.offset(base,hole)
   if hole.distance_to(base)>preload("res://scripts/proboscis.gd").reach(view.cell,organ)+30*organ.scale:continue
   var color:=Colors.family(game,donor.cell.lineage_id())
   contacts.append({"base":base,"hole":hole,"scale":organ.scale,"color":color,"phase":progress(game.ui_time,view.cell.id*31+organ.id)})
 visible=not contacts.is_empty() and not game.merge_selecting()
 if visible:queue_redraw()
func _draw() -> void:
 for contact in contacts:
  var hole: Vector2=contact.hole;var base: Vector2=contact.base;var scale: float=contact.scale
  var angle: float=(base-hole).angle()
  draw_set_transform(hole,angle,Vector2(.72,1.0)*scale)
  draw_circle(Vector2.ZERO,7,Color(1,.57,.64,.24))
  draw_circle(Vector2.ZERO,5,Color("ef9da7"))
  draw_circle(Vector2.ZERO,3.5,Color("18273b"))
  draw_set_transform(Vector2.ZERO)
  draw_line(hole,base,Color(1,.91,.68,.23),2*scale,true)
  var phase: float=contact.phase
  var at:=hole.lerp(base,phase)
  var color: Color=contact.color.lightened(.4)
  color.a=.95*clampf(minf(phase,1-phase)*8,0,1)
  var diameter:=12*scale
  draw_texture_rect(Art.texture(3),Rect2(at-Vector2.ONE*diameter*.5,Vector2.ONE*diameter),false,color)
