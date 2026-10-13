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
	# Cytoplasmic chemicals are the authoritative moving particles.
	for packet in cell.chemistry.particles:
		if not packet.alive: continue
		var definition: Dictionary = cell.chemistry.Catalog.data().species[packet.species]
		var color := Color(definition.color)
		var size: float = 1.4+minf(2,sqrt(packet.amount)*1.5)
		if packet.species == "catalyst": size = 3.2
		draw_circle(packet.p,size,color)
		if packet.species not in ["atp","adp","water"]:
			var tip := Vector2.from_angle(packet.angle)*size*1.7
			draw_line(packet.p,packet.p+tip,color.lightened(0.25),maxf(0.7,size*0.45),true)
	for vacuole in cell.chemistry.vacuoles:
		draw_arc(vacuole.p,vacuole.radius,0,TAU,20,Color("8fe3bf").lerp(Color("f497c4"),vacuole.acid),0.8,true)
	for parcel in ecology.parcels:
		if parcel.kind != "ap": continue
		draw_circle(parcel.p,parcel.radius,Color("f8c650"))
	# Contractile vacuole fill follows actual transported water and expulsion.
	for side in [-1,1]:
		var center := Vector2(0.02,side*0.62)*r
		var swell := 0.35+0.65*clampf(cell.chemistry.amount("water")/maxf(0.1,cell.growth_scale()),0,1)
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
	# Template compartments are local catalyst domains with permeable outputs.
	for node in cell.chemistry.nodes:
		if node.compartment in ["digestive","contractile","membrane"]: continue
		var site: Vector2 = cell.chemistry.site(node)
		var shade := Color("6dceeb") if node.compartment == "mitochondrial" else Color("87e79e") if node.compartment == "photosynthetic" else Color("d9a5eb")
		draw_arc(site,r*0.15,0,TAU,20,shade*Color(1,1,1,0.5),0.7,true)

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
