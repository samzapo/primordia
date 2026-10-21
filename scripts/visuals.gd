extends RefCounted
## Original rounded vector anatomy. Local +X points out through the membrane.
const MINT := Color("35dab1")
const GOLD := Color("ffbe32")
const PURPLE := Color("b84fe9")
# Presentation only: preserve chemistry amounts, contacts and packet motion.
const INTERNAL_PARTICLE_SCALE := 0.2
static func internal_content_radius(kind: int,amount: float=.3) -> float:
	return preload("res://scripts/chemistry_catalog.gd").radius(kind)*.5*clampf(sqrt(amount/.3),.8,1.7)
static func internal_particle_radius(packet: Dictionary) -> float:
	return 1.4 if packet.species in ["oxygen","carbon"] else 7.0 # One carrier; illustrated contents use half-size external glyphs.

# The inherent mouth is membrane tissue, not a fixed-size attachment icon.
# Sample the exact rendered curve over the same half-radian groove as physics.
static func oral_path(cell, angle: float) -> PackedVector2Array:
	var outline: PackedVector2Array = cell.membrane.outline()
	var path := PackedVector2Array()
	for i in 25:
		var phase := fposmod(angle-.5+i/24.0,TAU)/TAU*outline.size()
		var index := int(phase)
		path.append(outline[index].lerp(outline[(index+1)%outline.size()],phase-index))
	return path

static func oral_groove(c: Node2D, cell, organ: Dictionary, clock: float, detail: bool) -> void:
	var lip := oral_path(cell,organ.a)
	var width := minf(5,cell.radius*.10)
	var pulse: float = organ.consume_flash
	c.draw_polyline(lip,Color("31537c"),width,true)
	c.draw_polyline(lip,Color("6ee6d4").lerp(Color("fff1ab"),pulse),width*.44,true)
	if detail:
		for i in range(2,23,3):
			var a: float = organ.a-.5+i/24.0
			var normal: Vector2 = cell.local_normal(a)
			var reach := minf(6,cell.radius*.13)*(1+.15*sin(clock*7+i))
			c.draw_line(lip[i],lip[i]+normal*reach,Color("caf7be"),width*.24,true)
	c.draw_circle(lip[12],width*.48*(1+.18*pulse),Color("e1f5ac"))

static func structure_ellipse(c,at: Vector2,extent: Vector2,color: Color,fill: float=1.0) -> void:
	if fill<=0:return
	var points:=PackedVector2Array()
	var cut:=acos(clampf(1-fill*2,-1,1))
	for i in (24 if fill>=1 else 25):
		var angle:=PI/2-cut+2*cut*i/24
		points.append(at+Vector2(cos(angle),sin(angle))*extent)
	if points.size()>=3:c.draw_colored_polygon(points,color)

static func assembly_factory(c,at: Vector2,r: float) -> void:
	for i in 3:
		var points:=PackedVector2Array()
		for j in 9:
			var t:=j/8.0
			points.append(at+Vector2((t-.5)*.30,(i-1)*.075+sin(t*PI)*.065)*r)
		c.draw_polyline(points,Color("bc557d"),r*.068,true)
		c.draw_polyline(points,Color("ffa96a"),r*.040,true)
	c.draw_circle(at+Vector2(.18,.06)*r,r*.047,Color("ffd267"))

const CRITICAL_ATP:=10.0
const CRITICAL_HEALTH:=30.0
static func warning_pulse(clock: float) -> float:
	# Slow, smooth emphasis on the structure; never hide anatomy or change stocks.
	return pow(.5-.5*cos(TAU*clock/1.6),2)

static func atp_warning(c,at: Vector2,extent: float,zoom: float,clock: float) -> void:
	var strength:=warning_pulse(clock)
	var ring:=PackedVector2Array()
	for i in 33:ring.append(at+Vector2(cos(TAU*i/32),sin(TAU*i/32))*Vector2(.86,1.16)*maxf(extent,5/maxf(.001,zoom))*1.2)
	c.draw_polyline(ring,Color(1,.64,.16,strength*.25),maxf(extent*.16,3/maxf(.001,zoom)),true)
	c.draw_polyline(ring,Color(1,.91,.53,strength*.90),maxf(extent*.07,1.2/maxf(.001,zoom)),true)

static func atp_store(c,at: Vector2,extent: float) -> void:
	var sac:=Vector2(.86,1.16)*extent
	structure_ellipse(c,at+Vector2(0,1),sac*1.10,Color("745344"))
	structure_ellipse(c,at,sac,Color("efbb4c"))
	structure_ellipse(c,at-Vector2.ONE*extent*.12,sac*.76,Color("ffe58e"))
	c.draw_arc(at,extent*.72,PI,PI*1.47,12,Color("fff5c7"),maxf(.8,extent*.13),true)

static func offspring_store(c,at: Vector2,r: float,material: float=1,energy: float=1) -> void:
	structure_ellipse(c,at,Vector2(.17,.145)*r,Color("9363ac"))
	structure_ellipse(c,at,Vector2(.15,.125)*r,Color("4b3979"))
	structure_ellipse(c,at,Vector2(.13,.105)*r,Color("ed69bc"),material)
	c.draw_arc(at,.16*r,-PI/2,-PI/2+TAU*energy,24,Color("ffd65a"),r*.032,true)

static func nucleus_art(c,at: Vector2,extent: float,core: PackedVector2Array,palette: Array,detail: bool=true) -> void:
	c.draw_colored_polygon(Transform2D(0,Vector2.ONE*extent*1.18,0,at+Vector2(0,extent*.1))*core,palette[0])
	c.draw_colored_polygon(Transform2D(0,Vector2.ONE*extent,0,at)*core,palette[5].darkened(.2))
	c.draw_colored_polygon(Transform2D(0,Vector2.ONE*extent*.74,0,at-Vector2.ONE*extent*.08)*core,palette[5])
	if detail:c.draw_colored_polygon(Transform2D(-.3,Vector2(.30,.38)*extent,0,at-Vector2.ONE*extent*.22)*core,palette[6])

static func receptor_factory(c,at: Vector2,r: float) -> void:
	c.draw_circle(at,r,Color("332349"));c.draw_arc(at,r,0,TAU,28,Color("c997ef"),r*.10,true)
	for side in [-1,1]:
		c.draw_line(at+Vector2(-.55,side*.3)*r,at+Vector2(.20,side*.3)*r,Color("c997ef"),r*.12,true)
		for direction in [-1,1]:
			c.draw_line(at+Vector2(.15,side*.3)*r,at+Vector2(.55,side*.3+direction*.23)*r,Color("edbfff"),r*.10,true)
	c.draw_circle(at+Vector2(.72,.72)*r,r*.30,Color("204954"))
	c.draw_line(at+Vector2(.55,.72)*r,at+Vector2(.89,.72)*r,Color("ccffe8"),r*.08,true)
	c.draw_line(at+Vector2(.72,.55)*r,at+Vector2(.72,.89)*r,Color("ccffe8"),r*.08,true)

static func internal_factory(c,at: Vector2,radius: float,active: bool=false) -> void:
	# Shared factory/overlap-menu artwork. This is a build affordance, not an organ.
	c.draw_circle(at+Vector2(0,radius*.12),radius,Color("122d51"))
	c.draw_circle(at,radius,Color("276c83"))
	c.draw_circle(at-Vector2(0,radius*.06),radius*.83,Color("193e65"))
	c.draw_arc(at,radius*.94,0,TAU,36,Color("caffdf") if active else Color("72d9d3"),radius*.085,true)
	c.draw_arc(at,radius*.80,PI,TAU,20,Color("3aa0ad"),radius*.055,true)
	for i in 3:
		var center: Vector2=at+Vector2((i-1)*.47,abs(i-1)*.14-.12)*radius
		var outline:=PackedVector2Array()
		for step in 24:outline.append(center+Vector2(cos(step*TAU/24)*.20,sin(step*TAU/24)*.46)*radius)
		c.draw_colored_polygon(outline,Color("42dfc6"))
		c.draw_circle(center-Vector2(0,radius*.20),radius*.11,Color("d3ffe9"))
	var badge: Vector2=at+Vector2(.69,.63)*radius
	c.draw_circle(badge,radius*.34,Color("174a66"))
	c.draw_circle(badge,radius*.27,Color("b8f2bd"))
	for direction in [Vector2.RIGHT,Vector2.DOWN]:
		c.draw_line(badge-direction*radius*.16,badge+direction*radius*.16,Color("20576b"),radius*.10,true)

class DimmedInk extends RefCounted:
	var canvas: Node2D
	func _init(target: Node2D) -> void:canvas=target
	func tint(color: Color) -> Color:
		var grey: float=color.get_luminance()
		return color.lerp(Color(grey,grey,grey,color.a),.85).darkened(.18)
	func draw_set_transform(at: Vector2,rotation: float=0,scale: Vector2=Vector2.ONE) -> void:canvas.draw_set_transform(at,rotation,scale)
	func draw_circle(at: Vector2,radius: float,color: Color) -> void:canvas.draw_circle(at,radius,tint(color))
	func draw_line(a: Vector2,b: Vector2,color: Color,width: float=-1,antialias: bool=false) -> void:canvas.draw_line(a,b,tint(color),width,antialias)
	func draw_arc(at: Vector2,radius: float,start: float,end: float,points: int,color: Color,width: float=-1,antialias: bool=false) -> void:canvas.draw_arc(at,radius,start,end,points,tint(color),width,antialias)
	func draw_polyline(points: PackedVector2Array,color: Color,width: float=-1,antialias: bool=false) -> void:canvas.draw_polyline(points,tint(color),width,antialias)
	func draw_colored_polygon(points: PackedVector2Array,color: Color) -> void:canvas.draw_colored_polygon(points,tint(color))

static func icon(c, p: Vector2, kind: String, rotation: float, scale: float, animation_time: float = 0, mode: String = "graze", pulse: float = 0, detail: bool = true, charge: float = 0, depleted: bool=false, stored: float=0.0, reach: float=27.0) -> void:
	if depleted:c=DimmedInk.new(c)
	c.draw_set_transform(p,rotation,Vector2.ONE*scale)
	var steps := 24 if detail else 10
	match kind:
		"assembly_factory":
			assembly_factory(c,Vector2.ZERO,110)
		"offspring_store":
			offspring_store(c,Vector2.ZERO,115)
		"atp_store":
			atp_store(c,Vector2.ZERO,19)
		"receptor_factory":
			receptor_factory(c,Vector2.ZERO,23)
		"internal_factory":
			internal_factory(c,Vector2.ZERO,23)
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
		"cilia":
			c.draw_line(Vector2(-3,-12),Vector2(-3,12),Color("126a9b"),9,true)
			for strand in (5 if detail else 3):
				var base := Vector2(0,(strand-(2 if detail else 1))*5.0)
				var hair := PackedVector2Array()
				for i in 6:
					var t := float(i)/5
					hair.append(base+Vector2(t*24,sin(t*4-animation_time*10+strand*0.9)*t*6))
				c.draw_polyline(hair,Color("2be2e6"),3.5,true)
				if detail: c.draw_circle(hair[-1],1.5,Color("c5ffff"))
		"protection":
			var shield := PackedVector2Array([Vector2(-10,-16),Vector2(4,-17),Vector2(15,-9),Vector2(18,0),Vector2(15,9),Vector2(4,17),Vector2(-10,16)])
			c.draw_colored_polygon(shield,Color("1966ad"))
			c.draw_colored_polygon(Transform2D(0,Vector2.ONE*0.83,0,Vector2(1,-1))*shield,Color("32bdf2"))
			c.draw_arc(Vector2(-1,0),12,-1.2,1.2,steps,Color("9cebff"),4,true)
			if detail: c.draw_line(Vector2(-3,-9),Vector2(-3,9),Color("248ccc"),3,true)
		"poreforming":
			c.draw_circle(Vector2(-3,0),13,Color("9c3a68"))
			c.draw_circle(Vector2(-3,-1),10,Color("ff985c"))
			c.draw_line(Vector2(2,0),Vector2(16,0),Color("ffdc83"),8,true)
			c.draw_arc(Vector2(17,0),5,0,TAU,12,Color("fff0ba"),3,true)
		"counterattack":
			c.draw_circle(Vector2(-3,0),13,Color("256f88"))
			c.draw_circle(Vector2(-3,-1),10,Color("7ee5e0"))
			c.draw_line(Vector2(1,0),Vector2(15,0),Color("ff80ae"),7,true)
			c.draw_line(Vector2(-7,0),Vector2(1,0),Color("fff2c3"),3,true)
			c.draw_line(Vector2(-3,-4),Vector2(-3,4),Color("fff2c3"),3,true)
		"toxin_sac":
			c.draw_set_transform(p,rotation,Vector2(.85,1.1)*scale)
			c.draw_circle(Vector2.ZERO,15,Color("663657"))
			c.draw_circle(Vector2(-1,-1),12,Color("b35b98"))
			c.draw_circle(Vector2(0,2),3+7*clampf(stored,0,1),Color("ff407b"))
			for i in 3:
				c.draw_circle(Vector2.from_angle(TAU*i/3)*4,1.7+stored,Color("ffb3d0"))
			c.draw_arc(Vector2.ZERO,13,3.3,4.6,12,Color("ffe3f5"),2,true)
			c.draw_set_transform(p,rotation,Vector2.ONE*scale)
		"mitochondrion":
			c.draw_set_transform(p,rotation,Vector2(1.25,.75)*scale)
			c.draw_circle(Vector2.ZERO,13,Color("8a3954"))
			c.draw_circle(Vector2(-1,-1),10.5,Color("ffa15b"))
			var folds:=PackedVector2Array()
			for i in 9:folds.append(Vector2(-8+i*2,(-1 if i%2==0 else 1)*5))
			c.draw_polyline(folds,Color("ffe9a0"),2.3,true)
			c.draw_set_transform(p,rotation,Vector2.ONE*scale)
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
		"proboscis":
			c.draw_circle(Vector2(-5,0),10,Color("773558"))
			c.draw_circle(Vector2(-5,-1),7,Color("e877a0"))
			c.draw_line(Vector2(-2,0),Vector2(reach-3,0),Color("91335d"),7,true)
			c.draw_line(Vector2(-1,-1),Vector2(reach,-1),Color("ffc5ac").lerp(Color("fff4a0"),pulse),3,true)
			c.draw_circle(Vector2(reach,0),3,Color("ffe0b3"))
			if detail:
				for i in 3:c.draw_circle(Vector2(4+i*(reach-7)/3,0),1.8,Color("ffe895").lerp(Color("e877a0"),pulse))
		"feeding":
			var lip := PackedVector2Array()
			for i in 17:
				var t := -PI/2+PI*i/16.0
				lip.append(Vector2(-cos(t)*(16-2*pulse),sin(t)*21))
			c.draw_polyline(lip,Color("31537c"),10,true)
			c.draw_polyline(lip,Color("6ee6d4").lerp(Color("fff1ab"),pulse),4,true)
			if detail:
				for i in range(1,16,2):
					var hair: Vector2 = lip[i]
					var tip := hair+Vector2(7+2*sin(animation_time*7+i),-hair.y*0.18)
					c.draw_line(hair,tip,Color("caf7be"),1.5,true)
			c.draw_circle(Vector2(-14,0),4*(1+0.3*pulse),Color("e1f5ac"))
		"family_toward","family_away":
			var color:=Color("8ee9c7") if kind=="family_toward" else Color("b9b3ff")
			c.draw_line(Vector2(-7,0),Vector2(16,0),color,5,true)
			for side in [-1,1]:
				var x:=12.0 if kind=="family_toward" else 23.0
				var tip:=23.0 if kind=="family_toward" else 12.0
				c.draw_line(Vector2(x,side*9),Vector2(tip,0),color,4,true)
			c.draw_circle(Vector2(-5,0),6,color)
			c.draw_circle(Vector2(-5,0),2.8,Color("285876"))
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
