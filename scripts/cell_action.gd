extends Button
## Compact cell-local choices use the same organ artwork as the world.
const Portrait=preload("res://scripts/cell_portrait.gd")
const FONT=preload("res://assets/fonts/ComicNeue-Regular.ttf")
var portrait: Dictionary={}
var portrait_art: Dictionary={}
var portrait_key:=""
var portrait_mesh: ArrayMesh
var portrait_geometry:=0
var lettering:=Node2D.new()
const SELECTION_MARK=preload("res://assets/ui/selection-mark.svg")
var selected:=false
var radial_progress:=-1.0
var progress_ready:=false
const Visuals = preload("res://scripts/visuals.gd")
var structure_art: Dictionary={}
var scar:=false
var picture := Node2D.new()
var kind := ""
var caption := ""
var description := ""
var symbol := ""
var tint := Color("83ead2")
var text_scale := 1.0
var affordable := true
var tissue_cost := -1.0
var ap_cost := 0
var rate_model: Dictionary = {}

func _ready() -> void:
	add_child(picture)
	picture.draw.connect(_draw_picture)
	add_child(lettering);lettering.draw.connect(_draw_lettering)
	resized.connect(queue_redraw)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus","disabled"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var center := size*0.5
	var r := minf(size.x,size.y)*0.47
	var active := is_hovered() or has_focus()
	draw_circle(center,r,Color("172448"))
	draw_circle(center,r*0.9,Color("305066") if active else Color("223954"))
	draw_arc(center,r*0.93,0,TAU,32,tint if active else tint.darkened(0.3),2*text_scale,true)
	if kind != "" or not portrait.is_empty():
		picture.position = center
		picture.queue_redraw()
	else:
		var font := ThemeDB.fallback_font
		var pixels := roundi(17*text_scale)
		var extent := font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels)
		if extent.x > r*1.7:
			pixels = maxi(10,roundi(pixels*r*1.7/extent.x))
			extent = font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels)
		draw_string(font,center+Vector2(-extent.x*0.5,pixels*0.34),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,tint)
	lettering.queue_redraw()
	if radial_progress>=0:
		var color:=Color("86f5b5") if progress_ready else Color("ffd784") if radial_progress>=.999999 else Color("79d7ed")
		draw_arc(center,r*1.01,-PI/2,-PI/2+TAU,48,Color("15283c"),3.5*text_scale,true)
		if radial_progress>0:draw_arc(center,r*1.01,-PI/2,-PI/2+TAU*clampf(radial_progress,0,1),48,color,3.5*text_scale,true)
	if selected:draw_texture_rect(SELECTION_MARK,Rect2(center+Vector2(r*.35,-r*.8),Vector2.ONE*16*text_scale),false)
	if scar:draw_arc(center,r*.75,0,TAU,24,Color("ffb6ca"),2*text_scale,true)
	if not affordable and radial_progress<0: draw_circle(center+Vector2(r*0.65,-r*0.65),4*text_scale,Color("f68899"))

func set_portrait(model: Dictionary,seed_value: int,paint: String) -> void:
	portrait=model
	if model.is_empty():picture.queue_redraw();return
	var key: String="%d:%d:%s" % [seed_value,model.lineage,paint]
	if key!=portrait_key:
		portrait_key=key;portrait_art=Portrait.Art.make(seed_value,model.lineage,paint)
		portrait_art["core"]=Portrait.Art.nucleus_outline(portrait_art.nucleus,portrait_art.phase)
	var geometry: int=hash([model.outline,model.hurt,portrait_art.colors])
	if portrait_mesh==null or portrait_geometry!=geometry:
		portrait_geometry=geometry;portrait_mesh=Portrait.body(model,portrait_art)
	picture.queue_redraw();lettering.queue_redraw()

func _draw_lettering() -> void:
	if portrait.is_empty():return
	var pixels:=maxi(10,roundi(14*text_scale))
	var extent:=FONT.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels)
	var badge: Vector2=size*.5+Vector2.ONE*minf(size.x,size.y)*.30
	var radius:=maxf(8*text_scale,extent.x*.5+3*text_scale)
	badge=badge.min(size-Vector2.ONE*(radius+2*text_scale))
	lettering.draw_circle(badge,radius,Color("17364e"))
	lettering.draw_arc(badge,radius,0,TAU,24,Color("8fe7cb"),maxf(1,text_scale),true)
	lettering.draw_string_outline(FONT,badge+Vector2(-extent.x*.5,pixels*.34),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,maxi(1,roundi(.35*text_scale)),Color("eaffef"))
	lettering.draw_string(FONT,badge+Vector2(-extent.x*.5,pixels*.34),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,Color("eaffef"))

func _draw_picture() -> void:
	if not portrait.is_empty():
		Portrait.draw(picture,portrait,portrait_art,portrait_mesh,minf(size.x,size.y)*.41)
	elif kind=="cell_nucleus" and not structure_art.is_empty():
		picture.draw_set_transform(Vector2.ZERO,-.4,Vector2.ONE*.73*text_scale)
		Visuals.nucleus_art(picture,Vector2.ZERO,19,structure_art.core,structure_art.colors)
		picture.draw_set_transform(Vector2.ZERO)
	elif kind!="":Visuals.icon(picture,Vector2.ZERO,kind,-.4,.73*text_scale,0,"graze")
