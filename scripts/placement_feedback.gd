extends Node2D
## Bounded local previews/ripples. Never mutate anatomy, biomass or collision state.
const Visuals=preload("res://scripts/visuals.gd")
var game
var next_id:=0
var entries: Array=[]
func begin(cell,kind: String,angle: float,pending: bool=true) -> int:
 if entries.size()>=16:_retire(entries[0])
 next_id+=1
 var item: Dictionary={"id":next_id,"cell":cell.id,"kind":kind,"angle":angle,"started":game.ui_time,"pending":pending,"edit":-1,"accepted":not pending,"revision":-1}
 item.root=Node2D.new();add_child(item.root)
 item.ghost=Node2D.new();item.ghost.modulate=Color(1,1,1,.45);item.root.add_child(item.ghost)
 item.ghost.visible=pending;item.ghost.draw.connect(_draw_ghost.bind(item))
 item.ripple=Node2D.new();item.root.add_child(item.ripple);item.ripple.draw.connect(_draw_ripple.bind(item))
 entries.append(item);sync()
 return next_id
func result(identity: int,ok: bool,edit: int) -> void:
 for item in entries:
  if item.id!=identity:continue
  item.accepted=ok;item.edit=edit
  if not ok:
   item.pending=false;item.ghost.hide();item.started=game.ui_time;item.rejected=true;item.ripple.show()
func reconcile(edit: int) -> void:
 for item in entries:
  if item.accepted and item.edit>=0 and edit>=item.edit:item.pending=false;item.ghost.hide()
func clear() -> void:
 for item in entries.duplicate():_retire(item)
func _retire(item: Dictionary) -> void:
 entries.erase(item);item.root.queue_free()
func sync() -> void:
 for item in entries.duplicate():
  var view=game.views.get(item.cell)
  var elapsed: float=game.ui_time-item.started
  if view==null or game.world.player.id!=item.cell or view.cell.dead or elapsed>15 or (not item.pending and elapsed>.65):
   _retire(item);continue
  item.root.position=view.position;item.root.rotation=view.rotation
  var organ: Dictionary={"kind":item.kind,"a":item.angle,"scale":1.0}
  item.point=view.visible_point(view.cell.organ_local_position(organ))
  item.ripple.position=item.point
  if item.pending:
   item.ghost.queue_redraw();item.revision=view.cell.render_revision
  if elapsed<=.65:item.ripple.queue_redraw()
  else:item.ripple.hide()
func _draw_ghost(item: Dictionary) -> void:
 var view=game.views.get(item.cell)
 if view==null:return
 var cell=view.cell
 if item.kind=="feeding":
  Visuals.oral_groove(item.ghost,cell,{"a":item.angle,"consume_flash":0},game.ui_time,false)
 else:
  Visuals.icon(item.ghost,item.point,item.kind,view.visible_normal(cell.organ_local_position({"kind":item.kind,"a":item.angle,"scale":1.0}),cell.local_normal(item.angle)).angle(),1,game.ui_time)
func _draw_ripple(item: Dictionary) -> void:
 var t: float=clampf((game.ui_time-item.started)/.65,0,1)
 var pixels: float=maxf(.001,game.zoom*game.detail_canvas_scale/game.detail_pixel_ratio)
 var color:=Color("fc8c90") if item.get("rejected",false) else Color("9ff8df")
 color.a=(1-t)*(1-t)*.85
 item.ripple.draw_arc(Vector2.ZERO,(7+30*t)/pixels,0,TAU,40,color,2/pixels,true)
