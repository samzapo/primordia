extends Node2D
## Intracellular resource parcels and anatomy; the outside can pause independently.
const Ecology = preload("res://scripts/interior_ecology.gd")
var ecology := Ecology.new()
var game
var anchors: Dictionary = {}
var atp_size := 0.0
var bud_material := 0.0
var bud_energy := 0.0

static func layout(cell) -> Dictionary:
	var radius: float = cell.radius
	for point in cell.membrane.points: radius = minf(radius,point.length())
	return {"radius":radius,"nucleus":Vector2(-0.12,-0.10)*radius,
		"assembly":Vector2(-0.38,0.29)*radius,"chemistry":Vector2(0.39,0.16)*radius,
		"atp":Vector2(0.32,-0.39)*radius,
		"bud":Vector2(-0.43,-0.44)*radius}

func sync() -> void:
	var cell = game.world.player
	anchors = layout(cell)
	if game.views.has(cell.id):
		var view = game.views[cell.id]
		position = view.position
		rotation = view.rotation
		anchors.nucleus += view.nucleus_lag
	else:
		position = game.Simulation.Medium.offset(game.render_camera,cell.position)
		rotation = cell.angle
	# A full, elastic sac changes size rather than filling a fixed tank.
	atp_size = anchors.radius*0.13*sqrt(log(1+maxf(0,cell.energy)/cell.energy_reference()*3))
	ecology.sync(cell,game.world.evolution.points)
	bud_material = clampf(cell.brood_mass/maxf(0.01,game.world.offspring_quote().material),0,1)
	bud_energy = clampf(cell.brood_energy/60,0,1)
	visible = not cell.dead and game.views.has(cell.id)
	queue_redraw()

func animate(dt: float) -> void:
	if not visible or game.settings_panel.visible: return
	ecology.step(dt,game.world.player)
	queue_redraw()

func _ellipse(at: Vector2, extent: Vector2, color: Color, fill: float = 1.0) -> void:
	if fill <= 0: return
	var points := PackedVector2Array()
	# Clip an ellipse by a horizontal liquid surface, leaving a truly empty sac at zero.
	var cut := acos(clampf(1-fill*2,-1,1))
	for i in (24 if fill >= 1.0 else 25):
		var a := PI/2-cut+2*cut*i/24
		points.append(at+Vector2(cos(a),sin(a))*extent)
	if points.size() >= 3: draw_colored_polygon(points,color)

func _draw() -> void:
	if anchors.is_empty(): return
	var r: float = anchors.radius
	var cell = game.world.player
	var at: Vector2 = anchors.atp
	if atp_size > 0.05:
		var sac := Vector2(0.86,1.16)*atp_size
		_ellipse(at+Vector2(0,1),sac*1.10,Color("745344"))
		_ellipse(at,sac,Color("efbb4c"))
		_ellipse(at-Vector2.ONE*atp_size*0.12,sac*0.76,Color("ffe58e"))
		draw_arc(at,atp_size*0.72,PI,PI*1.47,12,Color("fff5c7"),maxf(0.8,atp_size*0.13),true)
	else:
		draw_arc(at,1.5,0,TAU,12,Color("bc9459"),0.6,true)
	# Food vacuoles and AP tokens are actual stock parcels, never extra currency.
	for parcel in ecology.parcels:
		var color := Color("f8c650") if parcel.kind == "ap" else Color("93e9af") if parcel.kind == "food" else Color("aa78c7")
		draw_circle(parcel.p,parcel.radius*1.15,Color(color.darkened(0.4),0.60))
		draw_circle(parcel.p,parcel.radius,color)
		draw_circle(parcel.p-Vector2.ONE*parcel.radius*0.25,parcel.radius*0.28,color.lightened(0.65))
	# Paired contractile vacuoles and radial canals. Osmotic anatomy is currently
	# a visual model; it does not fabricate a second water/ATP resource balance.
	for side in [-1,1]:
		var center := Vector2(0.02,side*0.62)*r
		var phase := fposmod(ecology.clock*0.23+(0.5 if side < 0 else 0),1)
		var swell := 0.35+0.65*sin(phase*PI)
		for i in 6:
			var ray := Vector2.from_angle(TAU*i/6)
			draw_line(center+ray*r*0.05,center+ray*r*0.17,Color(0.55,0.94,0.93,0.30),r*0.026,true)
		_ellipse(center,Vector2.ONE*r*0.082*swell,Color("75d9df"))
		_ellipse(center-Vector2.ONE*r*0.015,Vector2.ONE*r*0.045*swell,Color("bbfff0"))
	# Small micronucleus beside the macronucleus: the family reserve's landmark.
	draw_circle(anchors.nucleus+Vector2(-0.23,0.06)*r,r*0.075,Color("a86bd8"))
	draw_circle(anchors.nucleus+Vector2(-0.25,0.04)*r,r*0.035,Color("edb3ef"))
	# Folded assembly ribbons, not an extra equipped organ.
	at = anchors.assembly
	for i in 3:
		var points := PackedVector2Array()
		for j in 9:
			var t := j/8.0
			points.append(at+Vector2((t-0.5)*0.30,(i-1)*0.075+sin(t*PI)*0.065)*r)
		draw_polyline(points,Color("bc557d"),r*0.068,true)
		draw_polyline(points,Color("ffa96a"),r*0.040,true)
	draw_circle(at+Vector2(0.18,0.06)*r,r*0.047,Color("ffd267"))
	# Chemistry chambers and their common outlet.
	at = anchors.chemistry
	for i in 3:
		var p := at+Vector2((i-1)*0.10,abs(i-1)*0.07)*r
		_ellipse(p,Vector2(0.063,0.13)*r,Color("235981"))
		_ellipse(p-Vector2(0,r*0.02),Vector2(0.047,0.10)*r,Color("46dfcb"))
		draw_circle(p-Vector2(0,r*0.055),r*0.025,Color("c8ffe1"))
	at = anchors.bud
	_ellipse(at,Vector2(0.17,0.145)*r,Color("9363ac"))
	_ellipse(at,Vector2(0.15,0.125)*r,Color("4b3979"))
	_ellipse(at,Vector2(0.13,0.105)*r,Color("ed69bc"),bud_material)
	draw_arc(at,0.16*r,-PI/2,-PI/2+TAU*bud_energy,24,Color("ffd65a"),r*0.032,true)
	if game.world.evolution.offspring_id >= 0:
		draw_arc(at,0.16*r,-PI/2,-PI/2+TAU*clampf(game.world.evolution.viable_seconds/60,0,1),24,Color("9cf4b4"),r*0.045,true)
	# Three crisis arcs and tiny dormant bodies show the goal and insurance.
	for i in (3 if game.build_open else 0):
		var a := -PI/2+i*TAU/3
		var fraction: float = clampf(game.world.evolution.crisis_seconds[i]/60,0,1)
		draw_arc(anchors.nucleus,r*0.31,a,a+1.7,16,Color("547299"),r*0.026,true)
		if fraction > 0: draw_arc(anchors.nucleus,r*0.31,a,a+1.7*fraction,16,Color("b8f0de"),r*0.038,true)
	for i in game.world.lineage.dormant.size():
		_ellipse(anchors.bud+Vector2(-0.12+i*0.10,-0.21)*r,Vector2(0.035,0.045)*r,Color("a6ead4"))
	if bud_material >= 1 and bud_energy >= 1:
		draw_arc(at,0.21*r,0,TAU,24,Color(1,0.92,0.61,0.5+0.25*sin(game.ui_time*3)),r*0.025,true)
	if game.build_open and not game.world.evolution.chosen:
		draw_circle(anchors.nucleus+Vector2(0.22,-0.20)*r,r*(0.04+0.008*sin(game.ui_time*2)),Color("fff19c"))
	if game.build_open:
		for key in ["assembly","chemistry","nucleus","bud"]:
			draw_arc(anchors[key],r*(0.34 if key == "nucleus" else 0.20),0,TAU,28,Color(0.75,1,0.91,0.18),1.2/game.zoom,true)
		for scar in cell.lost_organs:
			var p: Vector2 = cell.local_point(scar.a)
			draw_arc(p,10*scar.scale,0,TAU,20,Color("ffb6ca"),1.8/game.zoom,true)
	# ATP packets depart the visible sac; repair still leaves the nucleus.
	for packet in cell.resource_packets:
		if packet.delay > 0: continue
		var p: Vector2 = packet.p
		var color := Color("ffa8bd")
		if packet.kind == "atp":
			var organ: Dictionary = cell.organ_by_id(packet.organ_id)
			var a: float = packet.a if organ.is_empty() else organ.a
			var target: Vector2 = cell.local_point(a)*0.96
			var original: Vector2 = Vector2(-0.15,-0.15)*cell.radius
			var fraction := clampf(1-p.distance_to(target)/maxf(0.01,original.distance_to(target)),0,1)
			p = anchors.atp.lerp(target,fraction)
			color = Color("ffe071")
		elif packet.kind == "gain":
			var organ: Dictionary = cell.organ_by_id(packet.organ_id)
			var target: Vector2 = cell.local_point(packet.a if organ.is_empty() else organ.a)*0.96
			var original: Vector2 = Vector2(-0.15,-0.15)*cell.radius
			var fraction := clampf(1-p.distance_to(target)/maxf(0.01,original.distance_to(target)),0,1)
			var source: Vector2 = anchors.nucleus if organ.is_empty() else target
			p = source.lerp(anchors.atp,fraction)
			color = Color("affff0")
		draw_circle(p,3,color)
