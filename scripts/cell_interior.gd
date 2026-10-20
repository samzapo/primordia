extends Node2D
## Intracellular resource parcels and anatomy; the outside can pause independently.
const Visuals=preload("res://scripts/visuals.gd")
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
	bud_material = game.world.division_status().get("progress",0.0)
	bud_energy = bud_material
	visible = not cell.dead and game.views.has(cell.id)
	queue_redraw()

func animate(dt: float) -> void:
	if not visible or game.settings_panel.visible or not game.internal_visible(game.world.player): return
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
	if not cell.dead and cell.energy<Visuals.CRITICAL_ATP:
		var pixels_per_world: float=absf((get_viewport().get_final_transform()*get_global_transform_with_canvas()).get_scale().x)/maxf(.001,game.cell_ui.ui_scale())
		Visuals.atp_warning(self,at,maxf(1.5,atp_size),pixels_per_world,game.ui_time)
	if game.internal_visible(cell):
		for side in [-1,1]:
			var center:=Vector2(.02,side*.62)*r
			var swell:=.35+.65*sin(fposmod(cell.age*.23+(.5 if side<0 else 0),1)*PI)
			for i in 6:
				var ray:=Vector2.from_angle(TAU*i/6)
				draw_line(center+ray*r*.05,center+ray*r*.17,Color(.55,.94,.93,.3),r*.026,true)
			_ellipse(center,Vector2.ONE*r*.082*swell,Color("75d9df"))
			_ellipse(center-Vector2.ONE*r*.015,Vector2.ONE*r*.045*swell,Color("bbfff0"))
	# Small micronucleus beside the macronucleus: a family-control landmark.
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
	if game.build_open and (not game.world.evolution.division_offers.is_empty()):
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
