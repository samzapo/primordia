extends Node2D
## The visible shaft shares its exact path with the puncture/transfer cue.
const Probe=preload("res://scripts/proboscis.gd")
const Cue=preload("res://scripts/proboscis_feeding_art.gd")
const Visuals=preload("res://scripts/visuals.gd")
var view
var detail:=true
func sync(context,full_detail: bool) -> void:
 view=context;detail=full_detail
 visible=view.cell.count("proboscis")>0
 if visible:queue_redraw()
func _draw() -> void:
 if view==null:return
 for organ in view.cell.organs:
  if organ.kind!="proboscis":continue
  var path:=Cue.geometry(view.game,view,organ)
  var base: Vector2=view.visible_point(Probe.local_segment(view.cell,organ)[0])
  var tip: Vector2=view.transform.affine_inverse()*path.tip
  var depleted: bool=preload("res://scripts/organelle_status.gd").state(view.game.world,view.cell,organ).depleted
  Visuals.icon(self,base,"proboscis",(tip-base).angle(),organ.scale,view.game.ui_time,organ.mode,organ.consume_flash,detail,0,depleted,0,(tip-base).length()/organ.scale)
