extends Button
## Compact cell-local choices use the same organ artwork as the world.
const Visuals = preload("res://scripts/visuals.gd")
var picture := Node2D.new()
var kind := ""
var caption := ""
var description := ""
var symbol := ""
var tint := Color("83ead2")
var text_scale := 1.0
var affordable := true

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
	if not affordable: draw_circle(center+Vector2(r*0.65,-r*0.65),4*text_scale,Color("f68899"))

func _draw_picture() -> void:
	if kind != "": Visuals.icon(picture,Vector2.ZERO,kind,-0.4,0.73*text_scale,0,"graze")
