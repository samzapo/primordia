extends RefCounted
## Original rounded vector anatomy. Local +X points out through the membrane.
const MINT := Color("35dab1")
const GOLD := Color("ffbe32")
const PURPLE := Color("b84fe9")
static func icon(c: Node2D, p: Vector2, kind: String, rotation: float, scale: float, animation_time: float = 0, mode: String = "graze", pulse: float = 0, detail: bool = true, charge: float = 0) -> void:
	c.draw_set_transform(p,rotation,Vector2.ONE*scale)
	var steps := 24 if detail else 10
	match kind:
		"propulsion":
			var path := PackedVector2Array()
			for i in (18 if detail else 9):
				var t := float(i)/(17 if detail else 8)
				path.append(Vector2(t*43,sin(t*7-animation_time*9)*t*9))
			c.draw_polyline(path,Color("137889"),8,true)
			c.draw_polyline(path,MINT,5,true)
			c.draw_circle(path[-1],2.5,MINT)
			c.draw_circle(Vector2(-3,0),8,Color("1a7a87"))
			c.draw_circle(Vector2(-1,-1),5,MINT)
		"protection":
			var shield := PackedVector2Array([Vector2(-10,-16),Vector2(4,-17),Vector2(15,-9),Vector2(18,0),Vector2(15,9),Vector2(4,17),Vector2(-10,16)])
			c.draw_colored_polygon(shield,Color("1966ad"))
			c.draw_colored_polygon(Transform2D(0,Vector2.ONE*0.83,0,Vector2(1,-1))*shield,Color("32bdf2"))
			c.draw_arc(Vector2(-1,0),12,-1.2,1.2,steps,Color("9cebff"),4,true)
			if detail: c.draw_line(Vector2(-3,-9),Vector2(-3,9),Color("248ccc"),3,true)
		"offensive":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-9,-9),Vector2(6,-10),Vector2(42,0),Vector2(6,10),Vector2(-9,9)]),Color("ac215b"))
			c.draw_colored_polygon(PackedVector2Array([Vector2(-5,-6),Vector2(42,0),Vector2(-3,7)]),Color("ff407b").lerp(Color("ffe783"),pulse))
			c.draw_line(Vector2(-3,-4),Vector2(34,-1),Color("ffb58d"),3,true)
		"photosynthesis":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-12,-8),Vector2(4,-12),Vector2(17,-5),Vector2(20,2),Vector2(8,12),Vector2(-10,9)]),Color("198b59"))
			c.draw_circle(Vector2(1,-1),11,Color("79e94d").lerp(Color("fff18a"),pulse))
			if detail:
				for i in 3: c.draw_line(Vector2(-6+i*6,-6),Vector2(-6+i*6,6),Color("2bb161"),3,true)
			c.draw_circle(Vector2(13,-7),3,Color("25d7f2"))
		"toxin","neutralizing","acidifying":
			var color := Color("ff407b") if kind == "toxin" else Color("4094ff") if kind == "neutralizing" else Color("f34db1")
			var swelling := 1+0.15*charge-0.10*pulse
			c.draw_circle(Vector2(-4,1),13*swelling,color.darkened(0.42))
			c.draw_circle(Vector2(-3,-1),10.5*swelling,color)
			c.draw_line(Vector2(1,0),Vector2(18,0),color,9,true)
			c.draw_circle(Vector2(18,0),4.5,color)
			c.draw_circle(Vector2(19,0),2.5,Color("291948"))
			if detail:
				c.draw_arc(Vector2(-3,-1),7,3.3,4.5,10,color.lightened(0.45),3,true)
				if kind == "neutralizing": c.draw_arc(Vector2(-2,0),5,0.8,TAU-0.8,16,Color("c2f5ff"),2.5,true)
				elif kind == "acidifying": c.draw_circle(Vector2(-3,3),3,Color("ffabd6"))
		"regenerative":
			c.draw_circle(Vector2(-3,0),14,Color("178899"))
			c.draw_circle(Vector2(-1,-1),11,Color("2ce3bb"))
			c.draw_circle(Vector2(0,0),7,Color("198a99"))
			c.draw_line(Vector2(0,-4),Vector2(0,4),Color("d0ffbe"),3,true)
			c.draw_line(Vector2(-4,0),Vector2(4,0),Color("d0ffbe"),3,true)
		"feeding":
			# Contract the aperture on real ingestion; attachment remains anchored.
			var center := Vector2(9-pulse*2,0)
			c.draw_circle(center,18,Color("ac6439"))
			c.draw_circle(center+Vector2(0,-1),15.5,GOLD.lerp(Color("fff18a"),pulse*0.8))
			c.draw_circle(center,10.5*(1-0.22*pulse),Color("312154"))
			c.draw_arc(center,14,2.9,4.9,steps,Color("ffed89"),4,true)
			if detail: c.draw_arc(center+Vector2(3,0),6,0.9,TAU-0.9,steps,Color("ec8b3b"),3,true)
		"sensing":
			c.draw_line(Vector2(-6,0),Vector2(11,0),Color("7634b2"),8,true)
			c.draw_line(Vector2(-3,0),Vector2(12,0),PURPLE,5,true)
			for side in [-1,1]:
				c.draw_line(Vector2(10,0),Vector2(19,side*9),PURPLE,5,true)
				c.draw_circle(Vector2(19,side*9),4,Color("ed98ff"))
			c.draw_circle(Vector2(-4,0),6,PURPLE)
		"hunting":
			# Inward-hooked coral fork: pursuit is distinct from violet flight.
			c.draw_line(Vector2(-6,0),Vector2(10,0),Color("af394e"),8,true)
			c.draw_line(Vector2(-3,0),Vector2(12,0),Color("ff9362"),5,true)
			for side in [-1,1]:
				c.draw_polyline(PackedVector2Array([Vector2(9,0),Vector2(17,side*10),Vector2(24,side*6)]),Color("ff9362"),5,true)
				c.draw_circle(Vector2(24,side*6),3.5,Color("ffe6a1"))
			c.draw_circle(Vector2(-4,0),6,Color("ff9362"))
		"microtubule":
			c.draw_line(Vector2(-22,-16),Vector2(25,18),Color("b7d9e8"),3,true)
			c.draw_line(Vector2.ZERO,Vector2(13,-25),Color("b7d9e8"),3,true)
			for point in [Vector2(-22,-16),Vector2(25,18),Vector2.ZERO,Vector2(13,-25)]: c.draw_circle(point,5,MINT)
	c.draw_set_transform(Vector2.ZERO)
