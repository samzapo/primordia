extends RefCounted
const MINT := Color("80efce")
const GOLD := Color("f5d47b")
const PURPLE := Color("b5a3f4")
static func icon(c: Node2D, p: Vector2, kind: String, rotation: float, scale: float, animation_time: float = 0) -> void:
	var forward = Vector2.from_angle(rotation)
	var side = forward.orthogonal()
	match kind:
		"propulsion":
			var path = PackedVector2Array()
			for i in 22:
				var t = i / 21.0
				path.append(p + forward * (t * 43 * scale) + side * sin(t * 7 - animation_time * 9) * t * 10 * scale)
			c.draw_polyline(path, MINT, 4 * scale, true)
			c.draw_circle(p, 8 * scale, Color("cee8a5"))
			c.draw_circle(p, 4 * scale, Color("418e8d"))
		"protection":
			var polygon = PackedVector2Array()
			for i in 6:
				polygon.append(p + Vector2.from_angle(rotation + TAU*i/6.0) * 15 * scale)
			c.draw_colored_polygon(polygon, Color("9fcaee"))
			c.draw_circle(p, 8 * scale, Color("619fbd"))
			c.draw_line(p-side*7*scale, p+side*7*scale, Color("d4e9f4"), 2*scale)
		"offensive":
			c.draw_circle(p, 12*scale, Color("f2909e"))
			c.draw_circle(p-forward*3*scale, 7*scale, Color("b55976"))
			c.draw_line(p, p+forward*20*scale, Color("ffc78c"), 7*scale, true)
			c.draw_circle(p+forward*20*scale, 3*scale, Color("fff0b7"))
		"regenerative":
			c.draw_circle(p, 13*scale, Color("e6a6d7"))
			c.draw_circle(p, 9*scale, Color("9e72b2"))
			c.draw_line(p-side*5*scale, p+side*5*scale, Color("ffe2e5"), 3*scale)
			c.draw_line(p-forward*5*scale, p+forward*5*scale, Color("ffe2e5"), 3*scale)
		"feeding":
			c.draw_circle(p, 14*scale, GOLD)
			c.draw_circle(p+forward*3*scale, 8*scale, Color("527e71"))
			c.draw_arc(p, 14*scale, rotation+0.8, rotation+TAU-0.8, 28, Color("fff0b4"), 3*scale, true)
		"sensing":
			c.draw_line(p-forward*6*scale, p+forward*13*scale, PURPLE, 5*scale, true)
			for sign_value in [-1, 1]:
				var tip: Vector2 = p + forward*19*scale + side*sign_value*9*scale
				c.draw_line(p+forward*10*scale, tip, PURPLE, 4*scale, true)
				c.draw_circle(tip, 4*scale, Color("dcc5ff"))
			c.draw_circle(p, 7*scale, Color("a393d1"))
