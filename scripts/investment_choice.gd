extends Button
## Illustrative anatomy only: these pictures never create simulated cells.
const Art=preload("res://scripts/visuals.gd")
const SELECTION_MARK=preload("res://assets/ui/selection-mark.svg")
const FONT=preload("res://assets/fonts/ComicNeue-Regular.ttf")
var strategy:="hunter"
var active:=false
var text_scale:=1.0
var picture:=Node2D.new()
const DETAILS={"hunter":"Offense + movement","producer":"Sunlight + defense","grazer":"Feeding + movement"}
func _ready() -> void:
 add_child(picture);picture.draw.connect(_picture)
 for state in ["normal","hover","pressed","focus","disabled"]:add_theme_stylebox_override(state,StyleBoxEmpty.new())
 mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
 resized.connect(queue_redraw);mouse_entered.connect(queue_redraw);mouse_exited.connect(queue_redraw);focus_entered.connect(queue_redraw);focus_exited.connect(queue_redraw)
func _draw() -> void:
 var rect:=Rect2(Vector2.ONE*2*text_scale,size-Vector2.ONE*4*text_scale)
 var box:=StyleBoxFlat.new();box.bg_color=Color("2d615f") if active else Color("1b304f")
 box.border_color=Color("a9ffe1") if active else Color("618d9b")
 box.set_border_width_all(roundi((3 if active or has_focus() else 1)*text_scale));box.set_corner_radius_all(roundi(10*text_scale));draw_style_box(box,rect)
 if active:draw_texture_rect(SELECTION_MARK,Rect2(Vector2(size.x-25*text_scale,10*text_scale),Vector2.ONE*16*text_scale),false)
 var font_size:=roundi(16*text_scale)
 draw_string(FONT,Vector2(4*text_scale,size.y-31*text_scale),strategy.capitalize(),HORIZONTAL_ALIGNMENT_CENTER,size.x-8*text_scale,font_size,Color("e6fff6"))
 draw_string(FONT,Vector2(4*text_scale,size.y-12*text_scale),DETAILS[strategy],HORIZONTAL_ALIGNMENT_CENTER,size.x-8*text_scale,roundi(11*text_scale),Color("c3d8e4"))
 picture.position=Vector2(size.x*.5,(size.y-43*text_scale)*.5);picture.queue_redraw()
func _picture() -> void:
 var scale:=minf((size.x-14*text_scale)/110.0,(size.y-46*text_scale)/100.0)
 picture.draw_set_transform(Vector2.ZERO,0,Vector2.ONE*scale)
 var color: Color={"hunter":Color("e64491"),"producer":Color("487dd9"),"grazer":Color("a77ce2")}[strategy]
 var outline:=PackedVector2Array()
 var axis:=-.35;var mouth:=axis-PI/2 if strategy=="hunter" else 0.0
 var model: Dictionary={"role":strategy,"spine":PackedVector2Array(),"roots":PackedVector2Array(),"normals":PackedVector2Array()}
 for i in 80:
  var angle:=i*TAU/80
  var reach:=32.0*(1+.06*sin(angle*3+.4))
  if strategy=="hunter":reach=26*preload("res://scripts/membrane.gd").hunter_profile(angle-axis)
  elif strategy=="producer":
   var normal:=Vector2.from_angle(angle).abs()
   reach=28/pow(pow(normal.x,8)+pow(normal.y,8),1.0/8)
  outline.append(Vector2.from_angle(angle)*reach)
 if strategy=="hunter":
  for i in 6:
   model.spine.append(Vector2.ZERO);model.spine.append(Vector2.from_angle(axis+i*TAU/6)*44)
 elif strategy=="grazer":
  for i in 10:
   var a:=.62+(TAU-1.24)*(i+.5)/10
   model.roots.append(Vector2.from_angle(a)*32*(1+.06*sin(a*3+.4)));model.normals.append(Vector2.from_angle(a))
 picture.draw_colored_polygon(outline,Color("2cdac0"))
 picture.draw_colored_polygon(Transform2D(0,Vector2.ONE*.91,0,Vector2.ZERO)*outline,color)
 preload("res://scripts/synergy_art.gd").draw(picture,model,outline,32,color,0)
 picture.draw_circle(Vector2(-6,-4),9,Color("803f65"));picture.draw_circle(Vector2(-7,-5),6,Color("ffc452"))
 var organs: Array={"hunter":[["hunting",axis],["toxin",.9],["poreforming",2.0],["propulsion",axis+PI]],
 "producer":[["photosynthesis",-.8],["photosynthesis",.7],["mitochondrion",2.6]],
 "grazer":[["cilia",PI],["protection",-.8],["cilia",1.7]]}[strategy]
 for organ in organs:
  var angle: float=organ[1]
  var point: Vector2=outline[posmod(roundi(angle/TAU*outline.size()),outline.size())]
  if organ[0]=="mitochondrion":point=Vector2(8,9)
  Art.icon(picture,point*scale,organ[0],angle,.43*scale)
 picture.draw_set_transform(Vector2.ZERO,0,Vector2.ONE*scale)
 if strategy!="producer":
  var phase:=fposmod(mouth-.3,TAU)/TAU*outline.size();var oral:=PackedVector2Array()
  for i in 9:oral.append(outline[posmod(roundi(phase+i*.65/TAU*outline.size()/8),outline.size())]*.96)
  picture.draw_polyline(oral,Color("b8ffcf"),3,true)
 picture.draw_set_transform(Vector2.ZERO)
