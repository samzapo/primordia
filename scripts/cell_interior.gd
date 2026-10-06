extends Node2D
## Player-only resource artwork and clickable structures; no simulated bodies.
var game
var anchors: Dictionary = {}
var atp_fraction := 0.0
var coin_count := 0
var previous_coins := -1
var coin_transfers: Array = []
var bud_material := 0.0
var bud_energy := 0.0

static func layout(cell) -> Dictionary:
	var radius: float = cell.radius
	for point in cell.membrane.points: radius = minf(radius,point.length())
	return {"radius":radius,"nucleus":Vector2(-0.12,-0.10)*radius,
		"assembly":Vector2(-0.38,0.29)*radius,"chemistry":Vector2(0.39,0.16)*radius,
		"atp":Vector2(0.32,-0.39)*radius,"coins":Vector2(0.0,0.52)*radius,
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
	atp_fraction = clampf(cell.energy/maxf(0.01,cell.energy_capacity()),0,1)
	coin_count = game.world.evolution.points
	if previous_coins >= 0 and coin_count < previous_coins:
		for i in mini(12,previous_coins-coin_count):
			coin_transfers.append({"start":game.ui_time+i*0.045,"to":anchors.chemistry if game.selected >= 6 else anchors.assembly})
	previous_coins = coin_count
	coin_transfers = coin_transfers.filter(func(t): return game.ui_time-t.start < 0.55)
	bud_material = clampf(cell.brood_mass/maxf(0.01,game.world.offspring_quote().material),0,1)
	bud_energy = clampf(cell.brood_energy/60,0,1)
	visible = not cell.dead and game.views.has(cell.id)
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
	_ellipse(at+Vector2(0,r*0.025),Vector2(0.15,0.22)*r,Color("182751"))
	_ellipse(at,Vector2(0.145,0.215)*r,Color("46717f"))
	_ellipse(at,Vector2(0.118,0.184)*r,Color("254854"))
	_ellipse(at,Vector2(0.118,0.184)*r,Color("ffd94b"),atp_fraction)
	draw_arc(at,0.13*r,PI,PI*1.47,12,Color("b6f5d9"),r*0.032,true)
	if atp_fraction < 0.18:
		draw_arc(at,0.22*r,0,TAU,24,Color(1,0.62,0.25,0.3+0.25*sin(game.ui_time*4)),r*0.025,true)
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
	# Each token is one AP. The run's finite grants bound this tiny visual cluster.
	for i in coin_count:
		var p: Vector2 = anchors.coins+Vector2((i%6-2.5)*0.066,-(i/6)*0.070)*r
		var width := (0.30+0.70*absf(cos(game.ui_time*1.8+i*0.7)))*r*0.031
		_ellipse(p,Vector2(width,r*0.032),Color("ed9d42"))
		_ellipse(p-Vector2(0,r*0.008),Vector2(width*0.68,r*0.023),Color("ffe981"))
	for transfer in coin_transfers:
		var progress: float = clampf((game.ui_time-transfer.start)/0.55,0,1)
		var p: Vector2 = anchors.coins.lerp(transfer.to,progress)+Vector2(0,-sin(progress*PI)*r*0.1)
		_ellipse(p,Vector2(0.025,0.035)*r,Color("fff09b"))
	at = anchors.bud
	_ellipse(at,Vector2(0.17,0.145)*r,Color("9363ac"))
	_ellipse(at,Vector2(0.15,0.125)*r,Color("4b3979"))
	_ellipse(at,Vector2(0.13,0.105)*r,Color("ed69bc"),bud_material)
	draw_arc(at,0.16*r,-PI/2,-PI/2+TAU*bud_energy,24,Color("ffd65a"),r*0.032,true)
	if game.world.evolution.offspring_id >= 0:
		draw_arc(at,0.16*r,-PI/2,-PI/2+TAU*clampf(game.world.evolution.viable_seconds/60,0,1),24,Color("9cf4b4"),r*0.045,true)
	# A quiet nucleus rim communicates tides and a ready draft.
	for i in 6:
		var a := -PI/2+i*TAU/6
		var color := Color("b8f0de") if i <= game.world.evolution.tide else Color("547299")
		draw_arc(anchors.nucleus,r*0.31,a,a+0.72,8,color,r*0.026,true)
	if not game.world.evolution.chosen:
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
		draw_circle(p,3,color)
