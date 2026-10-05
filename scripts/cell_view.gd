extends Node2D
## Cached local drawing, with native Node2D transform interpolation between ticks.
const Visuals = preload("res://scripts/visuals.gd")
var cell
var game
var seen_revision := -1
var label := Label.new()
var appendages := Node2D.new()

func _ready() -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color",Color("21375d"))
	label.add_theme_constant_override("outline_size",4)
	add_child(label)
	appendages.z_index = 1
	add_child(appendages)
	appendages.draw.connect(_draw_organs)

func sync(render_position: Vector2, render_angle: float, zoom: float, alpha: float) -> void:
	position = render_position
	rotation = render_angle
	if seen_revision != cell.render_revision or game.show_senses != get_meta("senses",false) or game.build_open != get_meta("assembly",false):
		seen_revision = cell.render_revision
		set_meta("senses",game.show_senses)
		set_meta("assembly",game.build_open)
		queue_redraw()
		appendages.queue_redraw()
	label.text = "YOUR CELL" if cell == game.world.player else ""
	label.modulate = Color("edf6ff")
	var font_size := roundi(16*game.preferences.hud_scale)
	if label.get_theme_font_size("font_size") != font_size: label.add_theme_font_size_override("font_size",font_size)
	label.scale = Vector2.ONE/zoom
	label.rotation = -rotation
	label.position = Vector2(-label.size.x/(2*zoom),-cell.radius*cell.aspect-30/zoom).rotated(-rotation)
	label.visible = alpha > 0.1

func _draw() -> void:
	if cell == null: return
	# The body palette is shared: anatomy and secretions communicate function.
	var hue := Color("9d9aee")
	var outline: PackedVector2Array = cell.membrane.outline()
	draw_colored_polygon(Transform2D(0,Vector2.ONE*1.04,0,Vector2(0,5))*outline,Color(0.08,0.12,0.30,0.3))
	draw_colored_polygon(outline,hue.lerp(Color.WHITE,cell.hurt_flash*0.7))
	draw_colored_polygon(Transform2D(0,Vector2.ONE*0.87,0,Vector2.ZERO)*outline,hue.darkened(0.14))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed,hue.lightened(0.4),2.5,true)
	for link in cell.membrane.skeleton.links:
		var a: Vector2 = cell.membrane.skeleton.point(link.a,cell.membrane)
		var b: Vector2 = cell.membrane.skeleton.point(link.b,cell.membrane)
		draw_line(a,b,hue.lightened(0.45)*Color(1,1,1,(0.5 if game.build_open else 0.16)+link.tension*0.3),1+link.tension*2,true)
	for junction in cell.membrane.skeleton.junctions.values(): draw_circle(junction.p,3,Color("cce6ee"))
	# Decorative cytoplasm stays inside the deformed body; it adds no anatomy.
	for i in 9:
		var angle := i*2.3
		var q: Vector2 = Vector2.from_angle(angle)*cell.visible_support(angle)*(0.5+0.12*sin(i*7.0))
		var vesicle := hue.lightened(0.15 if i%3 == 0 else 0.3)
		draw_circle(q,3.5+i%2,vesicle)
	var nucleus: Vector2 = Vector2(-0.15,-0.15)*cell.radius
	var core := Color("66ddf7")
	draw_circle(nucleus+Vector2(1,2),cell.radius*0.31,hue.darkened(0.5))
	draw_circle(nucleus,cell.radius*0.29,Color("6855bc"))
	draw_circle(nucleus+Vector2(-0.025,-0.025)*cell.radius,cell.radius*0.22,core.darkened(0.1))
	draw_circle(nucleus+Vector2(-0.065,-0.07)*cell.radius,cell.radius*0.14,core)
	draw_circle(nucleus+Vector2(-0.10,-0.11)*cell.radius,cell.radius*0.065,core.lightened(0.5))
	for packet in cell.signals: draw_circle(packet.p,3,Color("fc8c90") if packet.fear else Color("b5a3f4"))
	for packet in cell.resource_packets:
		if packet.delay > 0: continue
		var color := Color("f5d47b") if packet.kind == "atp" else Color("ffa8bd")
		draw_circle(packet.p,5,color.darkened(0.25))
		draw_circle(packet.p,3,color.lightened(0.3))
	for hole in cell.holes:
		var at: Vector2 = cell.local_point(hole.a)
		draw_circle(at,3+hole.size*6,Color("27325e"))
		draw_arc(at,4+hole.size*6,0,TAU,16,Color("fc8c90"),1.5,true)
	if game.show_senses:
		draw_line(Vector2.ZERO,cell.target.rotated(-cell.angle)*(cell.radius+80),Color("b5a3f4"),2,true)

func _draw_organs() -> void:
	for organ in cell.organs:
		var point: Vector2 = cell.local_point(organ.a)
		var at: Vector2 = point+point.normalized()*5*organ.scale
		var heading := point.angle()
		Visuals.icon(appendages,at,organ.kind,heading,organ.scale,cell.age,organ.mode,organ.consume_flash)
		if organ.blocked > 0:
			appendages.draw_arc(at,15*organ.scale,-PI/2,-PI/2+TAU*organ.blocked,28,Color("cf92e8"),4*organ.scale,true)
		if organ.charge_flash > 0:
			appendages.draw_arc(at,11*organ.scale+organ.charge_flash*6,0,TAU,24,Color(0.96,0.84,0.48,organ.charge_flash),2,true)
		if game.show_senses and organ.kind in ["feeding","sensing","offensive"]:
			appendages.draw_arc(at,(760 if organ.kind == "offensive" else 310)*sqrt(organ.scale),0,TAU,48,Color(0.6,0.55,0.96,0.22),1,true)
		if organ.kind == "feeding" and organ.feeding:
			var end: Vector2 = game.world.Medium.offset(cell.position,organ.link).rotated(-cell.angle)
			appendages.draw_line(at,end,Color("fff0b4"),3,true)
			for i in 3:
				var t := fposmod(cell.age*1.5+i/3.0,1.0)
				appendages.draw_circle(end.lerp(at,t),4,Color("a1e88a"))
		if organ.hp < organ.max_hp:
			appendages.draw_arc(at,19*organ.scale,-PI/2,-PI/2+TAU*organ.hp/organ.max_hp,24,Color("fc8c90"),2,true)
