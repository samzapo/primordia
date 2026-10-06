extends Node2D
## Cached local drawing, with native Node2D transform interpolation between ticks.
const Art = preload("res://scripts/cell_art.gd")
const Visuals = preload("res://scripts/visuals.gd")
var cell
var art: Dictionary = {}
var art_lineage := -2147483648
var nucleus_lag := Vector2.ZERO
var last_age := 0.0
var game
var seen_revision := -1
var simple_view := false
var last_draw_tick := -2
var detail_lod := true
var label := Label.new()
var appendages := Node2D.new()

func _ready() -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color",Color("21375d"))
	label.add_theme_constant_override("outline_size",4)
	add_child(label)
	appendages.z_index = 1
	add_child(appendages)
	appendages.draw.connect(_draw_organs)

func sync(render_position: Vector2, render_angle: float, zoom: float, alpha: float) -> void:
	if art_lineage != cell.lineage_id():
		art_lineage = cell.lineage_id()
		art = Art.make(game.world.seed_value,art_lineage)
		art["core"] = Art.nucleus_outline(art.nucleus,art.phase)
		seen_revision = -1
	# Bounded presentation lag follows existing acceleration/turns, never physics.
	var elapsed := clampf(cell.age-last_age,0,0.1)
	last_age = cell.age
	var drift: Vector2 = (-cell.shape_acceleration.rotated(-render_angle)*0.002+Vector2(0,-cell.angular_velocity)*cell.radius*0.025).limit_length(cell.radius*0.055)
	nucleus_lag = nucleus_lag.lerp(drift,1-exp(-elapsed*6))
	position = render_position
	rotation = render_angle
	var reduced: bool = detail_lod and cell.radius*zoom < 18 and not game.build_open
	var detail_changed: bool = reduced != simple_view
	simple_view = reduced
	if (seen_revision != cell.render_revision and (not reduced or game.world.revision-last_draw_tick >= 2)) or detail_changed or game.show_senses != get_meta("senses",false) or game.build_open != get_meta("assembly",false):
		seen_revision = cell.render_revision
		last_draw_tick = game.world.revision
		set_meta("senses",game.show_senses)
		set_meta("assembly",game.build_open)
		queue_redraw()
		appendages.queue_redraw()
	label.hide()

func _draw() -> void:
	if cell == null: return
	var palette: Array = art.colors
	var hue: Color = palette[1]
	var outline: PackedVector2Array = cell.membrane.outline()
	if simple_view:
		var reduced_outline := PackedVector2Array()
		for i in range(0,outline.size(),4): reduced_outline.append(outline[i])
		outline = reduced_outline
	draw_colored_polygon(Transform2D(0,Vector2.ONE*1.025,0,Vector2(0,3))*outline,Color(palette[0],0.55))
	draw_colored_polygon(outline,palette[0])
	draw_colored_polygon(Transform2D(0,Vector2.ONE*0.96,0,Vector2.ZERO)*outline,hue.lerp(Color.WHITE,cell.hurt_flash*0.55))
	draw_colored_polygon(Transform2D(0,Vector2.ONE*0.78,0,Vector2(0,cell.radius*0.018))*outline,palette[2])
	# Colored rim stays inside the actual outline; it cannot imply extra armor.
	var rim := PackedVector2Array()
	for point in outline: rim.append(point*0.90)
	rim.append(rim[0])
	draw_polyline(rim,palette[3],cell.radius*0.085,true)
	var highlight := PackedVector2Array()
	for point in outline:
		if point.normalized().rotated(rotation).dot(Vector2(-0.707,-0.707)) > 0.60:
			highlight.append(point*0.92)
		else:
			if highlight.size() > 1: draw_polyline(highlight,palette[4],cell.radius*0.068,true)
			highlight.clear()
	if highlight.size() > 1: draw_polyline(highlight,palette[4],cell.radius*0.068,true)
	for link in ([] if simple_view else cell.membrane.skeleton.links):
		var a: Vector2 = cell.membrane.skeleton.point(link.a,cell.membrane)
		var b: Vector2 = cell.membrane.skeleton.point(link.b,cell.membrane)
		draw_line(a,b,hue.lightened(0.45)*Color(1,1,1,(0.5 if game.build_open else 0.16)+link.tension*0.3),1+link.tension*2,true)
	for junction in ([] if simple_view else cell.membrane.skeleton.junctions.values()): draw_circle(junction.p,3,Color("cce6ee"))
	# Six seeded vesicles replace fine repeated speckles; all remain inside the gel.
	if not simple_view and cell != game.world.player:
		for vesicle in art.vesicles:
			var support: float = cell.visible_support(vesicle.angle)
			var q: Vector2 = Vector2.from_angle(vesicle.angle)*support*vesicle.distance
			var color: Color = [palette[1].lightened(0.16),palette[3],palette[2].lightened(0.13)][vesicle.tone]
			draw_circle(q,minf(cell.radius*vesicle.radius,support*0.12),color)
	var safe_radius: float = cell.radius
	for point in outline: safe_radius = minf(safe_radius,point.length())
	var nucleus: Vector2 = Vector2(-0.12,-0.10)*safe_radius+nucleus_lag
	var core: PackedVector2Array = art.core
	if simple_view:
		var reduced_core := PackedVector2Array()
		for i in range(0,core.size(),2): reduced_core.append(core[i])
		core = reduced_core
	var size := safe_radius*0.28
	draw_colored_polygon(Transform2D(0,Vector2.ONE*size*1.18,0,nucleus+Vector2(0,size*0.1))*core,palette[0])
	draw_colored_polygon(Transform2D(0,Vector2.ONE*size,0,nucleus)*core,palette[5].darkened(0.2))
	draw_colored_polygon(Transform2D(0,Vector2.ONE*size*0.74,0,nucleus-Vector2.ONE*size*0.08)*core,palette[5])
	if not simple_view:
		draw_colored_polygon(Transform2D(-0.3,Vector2(0.30,0.38)*size,0,nucleus-Vector2.ONE*size*0.22)*core,palette[6])
	for packet in cell.signals: draw_circle(packet.p,3,Color("fc8c90") if packet.fear else Color("b5a3f4"))
	for packet in ([] if cell == game.world.player or simple_view else cell.resource_packets):
		if packet.delay > 0: continue
		var color := Color("f5d47b") if packet.kind == "atp" else Color("ffa8bd")
		draw_circle(packet.p,5,color.darkened(0.25))
		draw_circle(packet.p,3,color.lightened(0.3))
	for hole in cell.holes:
		var at: Vector2 = cell.local_point(hole.a)
		draw_circle(at,3+hole.size*6,Color("27325e"))
		draw_arc(at,4+hole.size*6,0,TAU,16,Color("fc8c90"),1.5,true)
	if game.show_senses:
		draw_line(Vector2.ZERO,cell.target.rotated(-cell.angle)*(cell.radius+80),Color("b5a3f4"),2,true)

func _draw_organs() -> void:
	for organ in cell.organs:
		var point: Vector2 = cell.local_point(organ.a)
		var at: Vector2 = point+point.normalized()*5*organ.scale
		var heading := point.angle()
		var charge: float = organ.charge_flash
		if organ.kind == "toxin" and cell.target_id >= 0 and cell.threat.length_squared() > 0.01 and cell.energy >= 12 and cell.biomass >= 0.18*organ.scale*organ.scale*cell.Genes.factor(organ,"burst"):
			charge = maxf(charge,clampf(1-float(organ.get("burst_clock",0))/(0.75*cell.Genes.factor(organ,"cooldown")),0,1))
		Visuals.icon(appendages,at,organ.kind,heading,organ.scale,cell.age,organ.mode,organ.consume_flash,not simple_view,charge)
		if organ.get("mutation","") != "": appendages.draw_circle(at,3.5*organ.scale,Color("fff2a3"))
		if organ.blocked > 0:
			appendages.draw_arc(at,15*organ.scale,-PI/2,-PI/2+TAU*organ.blocked,28,Color("cf92e8"),4*organ.scale,true)
		if organ.charge_flash > 0:
			appendages.draw_arc(at,11*organ.scale+organ.charge_flash*6,0,TAU,24,Color(0.96,0.84,0.48,organ.charge_flash),2,true)
		if game.show_senses and organ.kind in ["feeding","sensing","offensive"]:
			appendages.draw_arc(at,(760 if organ.kind == "offensive" else 310)*sqrt(organ.scale),0,TAU,48,Color(0.6,0.55,0.96,0.22),1,true)
		if organ.kind == "feeding" and organ.feeding:
			var end: Vector2 = game.world.Medium.offset(cell.position,organ.link).rotated(-cell.angle)
			appendages.draw_line(at,end,Color("fff0b4"),3,true)
			for i in 3:
				var t := fposmod(cell.age*1.5+i/3.0,1.0)
				appendages.draw_circle(end.lerp(at,t),4,Color("a1e88a"))
		if organ.hp < organ.max_hp:
			appendages.draw_arc(at,19*organ.scale,-PI/2,-PI/2+TAU*organ.hp/organ.max_hp,24,Color("fc8c90"),2,true)
