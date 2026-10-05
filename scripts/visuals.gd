extends RefCounted
const MINT := Color("67f3db")
const GOLD := Color("ffdf68")
const PURPLE := Color("c28bff")
static func icon(c: Node2D, p: Vector2, kind: String, rotation: float, scale: float, animation_time: float = 0, mode: String = "graze", pulse: float = 0) -> void:
	var forward = Vector2.from_angle(rotation)
	var side = forward.orthogonal()
	match kind:
		"propulsion":
			var path = PackedVector2Array()
			for i in 22:
				var t = i / 21.0
				path.append(p + forward * (t * 43 * scale) + side * sin(t * 7 - animation_time * 9) * t * 10 * scale)
			c.draw_polyline(path, Color("2e849c"), 6 * scale, true)
			c.draw_polyline(path, MINT, 4 * scale, true)
			c.draw_circle(p, 8 * scale, Color("ffe689"))
			c.draw_circle(p, 4 * scale, Color("2c89ab"))
		"protection":
			var polygon = PackedVector2Array()
			for i in 6:
				polygon.append(p + Vector2.from_angle(rotation + TAU*i/6.0) * 15 * scale)
			c.draw_colored_polygon(polygon, Color("65caff"))
			c.draw_circle(p, 8 * scale, Color("2d8bc3"))
			c.draw_line(p-side*7*scale, p+side*7*scale, Color("b5f1ff"), 2*scale)
		"offensive":
			c.draw_colored_polygon(PackedVector2Array([p-side*10*scale,p+forward*42*scale,p+side*10*scale,p-forward*5*scale]),Color("ff779b").lerp(Color.WHITE,pulse))
			c.draw_line(p,p+forward*35*scale,Color("ffe6b7"),2*scale,true)
		"photosynthesis":
			c.draw_set_transform(p,rotation,Vector2(1.25,0.8)*scale)
			c.draw_circle(Vector2.ZERO,14,Color("83ec65").lerp(Color("fff6b7"),pulse))
			for i in 3:
				c.draw_line(Vector2(-6+i*6,-7),Vector2(-6+i*6,7),Color("299b67"),3,true)
			c.draw_circle(Vector2(10,-8),3,Color("55ddec"))
			c.draw_set_transform(Vector2.ZERO)
		"toxin":
			c.draw_circle(p, 12*scale, Color("ff779b"))
			c.draw_circle(p-forward*3*scale, 7*scale, Color("a64383"))
			c.draw_line(p, p+forward*20*scale, Color("ffcf69"), 7*scale, true)
			c.draw_circle(p+forward*20*scale, 3*scale, Color("fff0b7"))
		"neutralizing":
			c.draw_circle(p,13*scale,Color("62bcff"))
			c.draw_arc(p+forward*4*scale,8*scale,rotation+0.8,rotation+TAU-0.8,24,Color("e6f9ff"),4*scale,true)
		"acidifying":
			c.draw_circle(p,12*scale,Color("ff83c7"))
			for i in 3: c.draw_circle(p+forward*(5+i*5)*scale+side*sin(i*2)*4*scale,(4-i)*scale,Color("ffe2e9"))
		"regenerative":
			c.draw_circle(p, 13*scale, Color("63e9c9"))
			c.draw_circle(p, 9*scale, Color("3298af"))
			c.draw_line(p-side*5*scale, p+side*5*scale, Color("ffe2e5"), 3*scale)
			c.draw_line(p-forward*5*scale, p+forward*5*scale, Color("ffe2e5"), 3*scale)
		"feeding":
			var r := 18*scale
			var center: Vector2 = p+forward*r*0.65
			var tint := GOLD.lerp(Color.WHITE,pulse*0.9)
			c.draw_circle(center,r,Color("3c507f"))
			c.draw_arc(center,r*(1+0.12*pulse),0,TAU,48,tint,4*scale,true)
			c.draw_arc(center,r*0.65,rotation+0.8,rotation+TAU-0.8,24,tint,2*scale,true)
		"sensing":
			c.draw_line(p-forward*6*scale, p+forward*13*scale, PURPLE, 5*scale, true)
			for sign_value in [-1, 1]:
				var tip: Vector2 = p + forward*19*scale + side*sign_value*9*scale
				c.draw_line(p+forward*10*scale, tip, PURPLE, 4*scale, true)
				c.draw_circle(tip, 4*scale, Color("ecb7ff"))
			c.draw_circle(p, 7*scale, Color("985dda"))

		"microtubule":
			var a: Vector2 = p+Vector2(-22,-16)*scale
			var b: Vector2 = p+Vector2(25,18)*scale
			c.draw_line(a,b,Color("b7d9e8"),3*scale,true)
			c.draw_line(p,p+Vector2(13,-25)*scale,Color("b7d9e8"),3*scale,true)
			for point in [a,b,p,p+Vector2(13,-25)*scale]: c.draw_circle(point,5*scale,MINT)
