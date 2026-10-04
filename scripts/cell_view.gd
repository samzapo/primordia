extends Node2D
## Cached local drawing, with native Node2D transform interpolation between ticks.
const Visuals = preload("res://scripts/visuals.gd")
var cell
var game
var seen_revision := -1
var label := Label.new()

func _ready() -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

func sync(render_position: Vector2, render_angle: float, zoom: float, alpha: float) -> void:
	position = render_position
	rotation = render_angle
	if seen_revision != cell.render_revision or game.show_senses != get_meta("senses",false):
		seen_revision = cell.render_revision
		set_meta("senses",game.show_senses)
		queue_redraw()
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
	for ends in cell.membrane.CHORDS:
		draw_line(cell.membrane.points[ends[0]]*0.92,cell.membrane.points[ends[1]]*0.92,hue.lightened(0.3)*Color(1,1,1,0.36),1.5,true)
	draw_circle(Vector2(-7,-7),cell.radius*0.3,Color("a99bde"))
	draw_circle(Vector2(-5,-9),cell.radius*0.2,Color("d7b3e9"))
	for i in 7:
		var q: Vector2 = Vector2.from_angle(i*2.3)*cell.radius*(0.5+0.13*sin(i*7.0))
		draw_circle(q,3.5+i%2,hue.lightened(0.2))
	for packet in cell.signals: draw_circle(packet.p,3,Color("fc8c90") if packet.fear else Color("b5a3f4"))
	for organ in cell.organs:
		var at: Vector2 = cell.local_point(organ.a)+Vector2.from_angle(organ.a)*5
		Visuals.icon(self,at,organ.kind,organ.a,1,cell.age)
		if organ.kind == "sensing":
			var color: Color = {"forage":Color("a1e88a"),"hunt":Color("fc8c90"),"host":Color("f5d47b"),"flee":Color("70d6e1")}.get(organ.mode,Color.WHITE)
			draw_circle(at,3.5,color)
			if game.show_senses: draw_arc(at,310,0,TAU,48,color*Color(1,1,1,0.25),1,true)
		if organ.kind == "feeding" and organ.mode != "graze":
			if organ.mode == "parasite":
				draw_line(at,at+Vector2.from_angle(organ.a)*52,Color("f5d47b"),5,true)
				draw_line(at,at+Vector2.from_angle(organ.a)*51,Color("527e71"),2,true)
			else: draw_arc(at,23,organ.a-1,organ.a+1,20,Color("f5d47b"),4,true)
			if organ.feeding:
				var end: Vector2 = game.world.Medium.offset(cell.position,organ.link).rotated(-cell.angle)
				draw_line(at,end,Color("fff0b4"),4,true)
				for i in 3:
					var t := fposmod(cell.age*1.5+i/3.0,1.0)
					draw_circle(end.lerp(at,t),4,Color("a1e88a"))
				draw_arc(at,27,-PI/2,-PI/2+TAU*maxf(0.04,organ.progress),32,Color("fff0b4"),3,true)
		if organ.hp < organ.max_hp: draw_arc(at,19,-PI/2,-PI/2+TAU*organ.hp/organ.max_hp,24,Color("fc8c90"),2,true)
	for hole in cell.holes:
		var at: Vector2 = cell.local_point(hole.a)
		draw_circle(at,3+hole.size*6,Color("102d39"))
		draw_arc(at,4+hole.size*6,0,TAU,16,Color("fc8c90"),1.5,true)
	if game.show_senses:
		draw_line(Vector2.ZERO,cell.target.rotated(-cell.angle)*(cell.radius+80),Color("b5a3f4"),2,true)
