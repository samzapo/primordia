extends Node2D
## Display calibration only; chemistry packets are not drawn at molecular scale.
const MICROMETERS_PER_UNIT := 0.2
var micrometers := 20.0
var length_pixels := 100.0
var font_pixels := 18
var label_text := "20 μm"

func configure(viewport_size: Vector2, pixels_per_unit: float, text_scale: float) -> void:
	position = Vector2(24,viewport_size.y*0.5)
	var target_um := 140.0*MICROMETERS_PER_UNIT/maxf(pixels_per_unit,0.001)
	var decade := pow(10.0,floor(log(target_um)/log(10.0)))
	var next_um := decade
	for factor in [2.0,5.0]:
		if decade*factor <= target_um: next_um = decade*factor
	var next_length := next_um/MICROMETERS_PER_UNIT*pixels_per_unit
	var next_font := roundi(18*text_scale)
	if is_equal_approx(next_um,micrometers) and is_equal_approx(next_length,length_pixels) and next_font == font_pixels: return
	micrometers = next_um
	length_pixels = next_length
	font_pixels = next_font
	label_text = "%d μm" % roundi(micrometers) if micrometers >= 1 else "%s μm" % String.num(micrometers,3)
	queue_redraw()

func _draw() -> void:
	var points := PackedVector2Array([Vector2(0,-length_pixels*0.5),Vector2(0,length_pixels*0.5),Vector2(-5,-length_pixels*0.5),Vector2(5,-length_pixels*0.5),Vector2(-5,length_pixels*0.5),Vector2(5,length_pixels*0.5)])
	draw_multiline(points,Color("173151"),5,true)
	draw_multiline(points,Color("dbf5ed"),2,true)
	var at := Vector2(12,font_pixels*0.35)
	draw_string_outline(ThemeDB.fallback_font,at,label_text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_pixels,4,Color("173151"))
	draw_string(ThemeDB.fallback_font,at,label_text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_pixels,Color("dbf5ed"))
