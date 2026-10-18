extends Node2D
## Intracellular resource parcels and anatomy; the outside can pause independently.
const Visuals=preload("res://scripts/visuals.gd")
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
		"atp":Vector2(0.32,-0.39)*radius,"receptors":Vector2(.02,.60)*radius,
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
	ecology.sync(cell,game.world.player.ap)
	bud_material = clampf(cell.brood_mass/maxf(0.01,game.world.offspring_quote().material),0,1)
	bud_energy = clampf(cell.brood_energy/60,0,1)
	visible = not cell.dead and game.views.has(cell.id)
	queue_redraw()

func animate(dt: float) -> void:
	if not visible or game.settings_panel.visible or not game.internal_visible(game.world.player): return
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
		Visuals.atp_store(self,at,atp_size)
	else:
		draw_arc(at,1.5,0,TAU,12,Color("bc9459"),0.6,true)
	for parcel in (ecology.parcels if game.internal_visible(cell) else []):
		if parcel.kind != "ap": continue
		draw_circle(parcel.p,parcel.radius*preload("res://scripts/visuals.gd").INTERNAL_PARTICLE_SCALE,Color("f8c650"))

	if game.internal_visible(cell):
		for side in [-1,1]:
			var center:=Vector2(.02,side*.62)*r
			var swell:=.35+.65*sin(fposmod(cell.age*.23+(.5 if side<0 else 0),1)*PI)
			for i in 6:
				var ray:=Vector2.from_angle(TAU*i/6)
				draw_line(center+ray*r*.05,center+ray*r*.17,Color(.55,.94,.93,.3),r*.026,true)
			_ellipse(center,Vector2.ONE*r*.082*swell,Color("75d9df"))
			_ellipse(center-Vector2.ONE*r*.015,Vector2.ONE*r*.045*swell,Color("bbfff0"))
	# Small micronucleus beside the macronucleus: the family reserve's landmark.
	draw_circle(anchors.nucleus+Vector2(-0.23,0.06)*r,r*0.075,Color("a86bd8"))
	draw_circle(anchors.nucleus+Vector2(-0.25,0.04)*r,r*0.035,Color("edb3ef"))
	# Folded assembly ribbons, not an extra equipped organ.
	at = anchors.assembly
	Visuals.assembly_factory(self,at,r)

	# A raised chamber plate and a build badge identify the click point without labels.
	at = anchors.chemistry
	var active: bool=game.cell_ui.hovered.get("kind","")=="chemistry" or game.cell_ui.context.get("kind","")=="chemistry"
	preload("res://scripts/visuals.gd").internal_factory(self,at,r*.21,active)

	Visuals.receptor_factory(self,anchors.receptors,r*.19)

	at = anchors.bud
	Visuals.offspring_store(self,at,r,bud_material,bud_energy)
	if game.world.evolution.offspring_id >= 0:
		draw_arc(at,0.16*r,-PI/2,-PI/2+TAU*clampf(game.world.evolution.viable_seconds/60,0,1),24,Color("9cf4b4"),r*0.045,true)
	# Three crisis arcs show the local objective.
	for i in (3 if game.build_open else 0):
		var a := -PI/2+i*TAU/3
		var fraction: float = clampf(game.world.evolution.crisis_seconds[i]/60,0,1)
		draw_arc(anchors.nucleus,r*0.31,a,a+1.7,16,Color("547299"),r*0.026,true)
		if fraction > 0: draw_arc(anchors.nucleus,r*0.31,a,a+1.7*fraction,16,Color("b8f0de"),r*0.038,true)
	if bud_material >= 1 and bud_energy >= 1:
		draw_arc(at,0.21*r,0,TAU,24,Color(1,0.92,0.61,0.5+0.25*sin(game.ui_time*3)),r*0.025,true)
	if game.build_open and (not game.world.evolution.division_offers.is_empty() or (not game.world.evolution.sandbox and not game.world.evolution.chosen)):
		draw_circle(anchors.nucleus+Vector2(0.22,-0.20)*r,r*(0.04+0.008*sin(game.ui_time*2)),Color("fff19c"))
	if game.build_open:
		for key in ["assembly","chemistry","receptors","nucleus","bud"]:
			draw_arc(anchors[key],r*(0.34 if key == "nucleus" else 0.20),0,TAU,28,Color(0.75,1,0.91,0.18),1.2/game.zoom,true)
		for scar in cell.lost_organs:
			var p: Vector2 = cell.local_point(scar.a)
			draw_arc(p,10*scar.scale,0,TAU,20,Color("ffb6ca"),1.8/game.zoom,true)

	if game.internal_visible(cell):
		for packet in cell.resource_packets:
			if packet.delay>0:continue
			var organ: Dictionary=cell.organ_by_id(packet.organ_id)
			var destination: Vector2=cell.local_point(packet.a if organ.is_empty() else organ.a)*.96
			var original: Vector2=Vector2(-.15,-.15)*cell.radius
			var fraction:=clampf(1-packet.p.distance_to(destination)/maxf(.01,original.distance_to(destination)),0,1)
			var source: Vector2=anchors.atp if packet.kind=="atp" else anchors.nucleus
			var target: Vector2=anchors.atp if packet.kind=="gain" else destination
			if packet.kind=="gain" and not organ.is_empty():source=destination
			var position: Vector2=source.lerp(target,fraction)
			if packet.kind in ["atp","gain"]:
				draw_texture_rect(preload("res://scripts/particle_art.gd").atp_texture(),Rect2(position-Vector2.ONE*2.2,Vector2.ONE*4.4),false)
			else:
				draw_polyline(PackedVector2Array([position+Vector2(-1.8,0),position+Vector2(0,-1.8),position+Vector2(1.8,0),position+Vector2(0,1.8),position+Vector2(-1.8,0)]),Color("ffa8bd"),.65,true)
