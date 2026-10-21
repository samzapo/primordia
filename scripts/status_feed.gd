extends Control
## Local presentation only: bounded three-second notices and independent status panes.
const FONT=preload("res://assets/fonts/ComicNeue-Regular.ttf")
const RED:=Color("f47f8b")
const MINT:=Color("86cfbd")
const LIFETIME:=3.0
const MAX_MESSAGES:=3
var entries: Array=[]
var instinct: PanelContainer
var starvation: PanelContainer
var waiting:=Control.new()
var clock:=0.0
var top:=0.0
func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 instinct=_pane("","info");starvation=_pane("Starving","error")
 add_child(waiting);waiting.mouse_filter=Control.MOUSE_FILTER_IGNORE
 waiting.custom_minimum_size=Vector2(36,36);waiting.draw.connect(_draw_waiting)
 instinct.hide();starvation.hide();waiting.hide()
func _pane(text: String,tone: String) -> PanelContainer:
 var box:=PanelContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var label:=Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.max_lines_visible=2
 label.add_theme_font_override("font",FONT);box.add_child(label);add_child(box)
 _style(box,tone,1.0)
 return box
func _style(box: PanelContainer,tone: String,s: float) -> void:
 if box.get_meta("status_scale",-1.0)==s and box.get_meta("status_tone","")==tone:return
 box.set_meta("status_scale",s);box.set_meta("status_tone",tone)
 var ink:=StyleBoxFlat.new();ink.bg_color=Color(.045,.085,.14,.88)
 var color:=RED if tone=="error" else MINT
 ink.border_color=color;ink.set_border_width_all(maxi(1,roundi(s)))
 ink.set_corner_radius_all(roundi(4*s))
 ink.content_margin_left=7*s;ink.content_margin_right=7*s;ink.content_margin_top=3*s;ink.content_margin_bottom=3*s
 box.add_theme_stylebox_override("panel",ink)
 var label: Label=box.get_child(0)
 label.add_theme_color_override("font_color",RED.lightened(.25) if tone=="error" else Color("e5f5ec"))
func push(value: String,tone: String="info") -> void:
 var text:=value.strip_edges().replace("\n"," · ")
 if text.is_empty():return
 if text.length()>180:text=text.left(177)+"…"
 for entry in entries:
  if entry.text==text and entry.tone==tone:return # Repeats never extend a notice's life.
 while entries.size()>=MAX_MESSAGES:
  entries.pop_front().panel.queue_free()
 var box:=_pane(text,tone)
 entries.append({"panel":box,"text":text,"tone":tone,"age":0.0})
func advance(dt: float) -> void:
 clock+=maxf(0,dt)
 for entry in entries.duplicate():
  entry.age+=maxf(0,dt)
  entry.panel.modulate.a=clampf(1-entry.age/LIFETIME,0,1)
  if entry.age>=LIFETIME:entries.erase(entry);entry.panel.queue_free()
static func starving(cell) -> bool:
 return not cell.dead and cell.energy<=.000001 and cell.biomass<=.000001
func _place(box: PanelContainer,y: float,s: float,max_width: float,tone: String) -> float:
 _style(box,tone,s)
 var label: Label=box.get_child(0)
 var font_size:=roundi(17*s)
 if box.get_meta("layout_text","")!=label.text or box.get_meta("layout_scale",-1.0)!=s or box.get_meta("layout_width",-1.0)!=max_width:
  box.set_meta("layout_text",label.text);box.set_meta("layout_scale",s);box.set_meta("layout_width",max_width)
  label.add_theme_font_size_override("font_size",font_size)
  var width: float=minf(max_width,maxf(70*s,FONT.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+14*s))
  label.custom_minimum_size.x=maxf(30*s,width-14*s)
  box.custom_minimum_size.x=width;box.reset_size();box.size=box.get_combined_minimum_size()
 var minimum:=box.get_combined_minimum_size()
 if box.size!=minimum:box.size=minimum # Shrink once wrapped text settles after container layout.
 box.position=Vector2(8*s,maxf(8*s,y-box.size.y))
 return box.position.y-5*s
func sync(dt: float,cell,show_instinct: bool,intention: String,busy: bool,s: float,viewport: Vector2,bottom: float) -> void:
 advance(dt);size=viewport
 waiting.visible=busy;waiting.size=Vector2.ONE*36*s
 waiting.position=Vector2(viewport.x-44*s,bottom-40*s)
 if busy:waiting.queue_redraw()
 var y:=bottom
 var width:=minf(480*s,maxf(80*s,viewport.x-72*s))
 instinct.visible=show_instinct and not cell.dead
 if instinct.visible:
  instinct.get_child(0).text="Instinct · "+intention
  y=_place(instinct,y,s,width,"info")
 starvation.visible=starving(cell)
 if starvation.visible:y=_place(starvation,y,s,width,"error")
 for entry in entries:
  y=_place(entry.panel,y,s,width,entry.tone)
 top=y
func _draw_waiting() -> void:
 var center:=waiting.size*.5;var radius:=minf(waiting.size.x,waiting.size.y)*.31
 var blob:=PackedVector2Array()
 for i in 40:
  var a:=TAU*i/40.0
  var r:=radius*(1+.13*sin(3*a-clock*3.1)+.08*sin(5*a+clock*2.3))
  blob.append(center+Vector2.from_angle(a)*r)
 waiting.draw_colored_polygon(blob,Color(.25,.81,.72,.72))
 var edge:=blob.duplicate();edge.append(blob[0])
 waiting.draw_polyline(edge,Color(.64,1,.86,.94),maxf(1,waiting.size.x/25),true)
 var nucleus:=center+Vector2(sin(clock*2.2),cos(clock*1.9))*radius*.18
 waiting.draw_circle(nucleus,radius*.3,Color("b5f6ba"))
