extends Control
signal changed(color: Color)
var hue:=0.0
var saturation:=.7
var value:=.8
var drag_mode:=""
var background:=ColorRect.new()
func _ready() -> void:
 size_flags_horizontal=Control.SIZE_SHRINK_CENTER
 custom_minimum_size=Vector2(260,260);mouse_filter=Control.MOUSE_FILTER_STOP
 background.show_behind_parent=true
 background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE
 background.material=ShaderMaterial.new();background.material.shader=preload("res://shaders/lineage_palette.gdshader")
 add_child(background);set_color(Color.from_hsv(hue,saturation,value))
func color() -> Color:return Color.from_hsv(hue,saturation,value)
func set_color(next: Color) -> void:
 hue=next.h;saturation=next.s;value=next.v
 if background.material!=null:background.material.set_shader_parameter("hue",hue)
 queue_redraw()
static func square_to_disc(point: Vector2) -> Vector2:
 return point*maxf(absf(point.x),absf(point.y))/maxf(.000001,point.length())
static func disc_to_square(point: Vector2) -> Vector2:
 return point*point.length()/maxf(.000001,maxf(absf(point.x),absf(point.y)))
func choose(at: Vector2,begin: bool=false) -> void:
 var p: Vector2=(at-size*.5)/(minf(size.x,size.y)*.5)
 if begin:drag_mode="hue" if p.length()>=.79 else "sv"
 if drag_mode=="hue":hue=fposmod(p.angle()/TAU,1.0)
 elif drag_mode=="sv":
  var square:=disc_to_square((p/.72).limit_length(1))
  saturation=clampf((square.x+1)*.5,0,1);value=clampf((1-square.y)*.5,0,1)
 background.material.set_shader_parameter("hue",hue);queue_redraw();changed.emit(color())
func _gui_input(event: InputEvent) -> void:
 if event is InputEventScreenTouch and event.index==0:
  if event.pressed:choose(event.position,true)
  else:drag_mode=""
  accept_event()
 elif event is InputEventScreenDrag and event.index==0 and drag_mode!="":choose(event.position);accept_event()
 elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
  if event.pressed:choose(event.position,true)
  else:drag_mode=""
  accept_event()
 elif event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT and drag_mode!="":choose(event.position);accept_event()
func _draw() -> void:
 var radius:=minf(size.x,size.y)*.5
 draw_arc(size*.5+Vector2.from_angle(hue*TAU)*radius*.91,radius*.04,0,TAU,24,Color.WHITE,2,true)
 var sv:=square_to_disc(Vector2(saturation*2-1,1-value*2))*.72*radius+size*.5
 draw_arc(sv,radius*.045,0,TAU,24,Color.BLACK,3,true);draw_arc(sv,radius*.045,0,TAU,24,Color.WHITE,1.5,true)
