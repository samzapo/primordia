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
	add_child(label)
	appendages.z_index = 1
	add_child(appendages)
	appendages.draw.connect(_draw_organs)

func sync(render_position: Vector2, render_angle: float, zoom: float, alpha: float) -> void:
	position = render_position
	rotation = render_angle
	if seen_revision != cell.render_revision or game.show_senses != get_meta("senses",false):
		seen_revision = cell.render_revision
		set_meta("senses",game.show_senses)
		queue_redraw()
		appendages.queue_redraw()
	label.text = "YOUR CELL" if cell == game.world.player else cell.role.to_upper()
	label.modulate = Color("80efce") if cell == game.world.player else Color("fc8c90") if cell.role == "hunter" else Color("f5d47b")
	var font_size := roundi(16*game.preferences.hud_scale)
	if label.get_theme_font_size("font_size") != font_size: label.add_theme_font_size_override("font_size",font_size)
	label.scale = Vector2.ONE/zoom
	label.rotation = -rotation
	label.position = Vector2(-label.size.x/(2*zoom),-cell.radius*cell.aspect-30/zoom).rotated(-rotation)
	label.visible = alpha > 0.1

func _draw() -> void:
	if cell == null: return
	var hue := Color("80efce") if cell == game.world.player else (Color("fc8c90") if cell.role == "hunter" else Color("f5d47b"))
	var outline: PackedVector2Array = cell.membrane.outline()
	draw_colored_polygon(Transform2D(0,Vector2.ONE*1.04,0,Vector2(0,5))*outline,Color(0.01,0.07,0.12,0.4))
	draw_colored_polygon(outline,hue.lerp(Color.WHITE,cell.hurt_flash*0.7))
	draw_colored_polygon(Transform2D(0,Vector2.ONE*0.87,0,Vector2.ZERO)*outline,hue.darkened(0.35))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed,hue.lightened(0.3),2,true)
	for link in cell.membrane.skeleton.links:
		var a: Vector2 = cell.membrane.skeleton.point(link.a,cell.membrane)
		var b: Vector2 = cell.membrane.skeleton.point(link.b,cell.membrane)
		draw_line(a,b,hue.lightened(0.45)*Color(1,1,1,0.35+link.tension*0.5),1+link.tension*2,true)
	for junction in cell.membrane.skeleton.junctions.values(): draw_circle(junction.p,3,Color("cce6ee"))
	draw_circle(Vector2(-0.15,-0.15)*cell.radius,cell.radius*0.3,Color("a99bde"))
	draw_circle(Vector2(-0.11,-0.19)*cell.radius,cell.radius*0.2,Color("d7b3e9"))
	for i in 7:
		var q: Vector2 = Vector2.from_angle(i*2.3)*cell.radius*(0.5+0.13*sin(i*7.0))
		draw_circle(q,3.5+i%2,hue.lightened(0.2))
	for packet in cell.signals: draw_circle(packet.p,3,Color("fc8c90") if packet.fear else Color("b5a3f4"))
	for packet in cell.resource_packets:
		if packet.delay > 0: continue
		var color := Color("f5d47b") if packet.kind == "atp" else Color("ffa8bd")
		draw_circle(packet.p,5,color.darkened(0.25))
		draw_circle(packet.p,3,color.lightened(0.3))
	for hole in cell.holes:
		var at: Vector2 = cell.local_point(hole.a)
		draw_circle(at,3+hole.size*6,Color("102d39"))
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
