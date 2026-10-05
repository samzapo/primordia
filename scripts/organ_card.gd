extends Button
const Visuals = preload("res://scripts/visuals.gd")
var picture := Node2D.new()
var caption := Label.new()
var kind := "feeding"
var mode := "graze"
var hud_scale := 1.0

func _ready() -> void:
	add_child(picture)
	picture.draw.connect(_draw_picture)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(caption)
	resized.connect(_layout)
	_layout()

func configure(label: String, category: String, variant: String, scale_value: float) -> void:
	caption.text = label
	kind = category
	mode = variant
	hud_scale = scale_value
	tooltip_text = label
	custom_minimum_size.y = 88*hud_scale
	_layout()
	picture.queue_redraw()

func _layout() -> void:
	picture.position = Vector2(48*hud_scale,size.y*0.5)
	picture.scale = Vector2.ONE*hud_scale
	caption.position = Vector2(100*hud_scale,8*hud_scale)
	caption.size = Vector2(maxf(40,size.x-112*hud_scale),maxf(30,size.y-16*hud_scale))
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _draw_picture() -> void:
	Visuals.icon(picture,Vector2.ZERO,kind,-0.35,0.8,0,mode)
