extends Button
## Compact cell-local choices use the same organ artwork as the world.
const SELECTION_MARK=preload("res://assets/ui/selection-mark.svg")
var selected:=false
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
	if kind != "":
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
	if selected:draw_texture_rect(SELECTION_MARK,Rect2(center+Vector2(r*.35,-r*.8),Vector2.ONE*16*text_scale),false)
	if scar:draw_arc(center,r*.75,0,TAU,24,Color("ffb6ca"),2*text_scale,true)
	if not affordable: draw_circle(center+Vector2(r*0.65,-r*0.65),4*text_scale,Color("f68899"))

func _draw_picture() -> void:
	if kind=="cell_nucleus" and not structure_art.is_empty():
		picture.draw_set_transform(Vector2.ZERO,-.4,Vector2.ONE*.73*text_scale)
		Visuals.nucleus_art(picture,Vector2.ZERO,19,structure_art.core,structure_art.colors)
		picture.draw_set_transform(Vector2.ZERO)
	elif kind!="":Visuals.icon(picture,Vector2.ZERO,kind,-.4,.73*text_scale,0,"graze")
