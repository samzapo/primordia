extends Node2D
## Cached local drawing, with native Node2D transform interpolation between ticks.
const Art = preload("res://scripts/cell_art.gd")
const Surface = preload("res://scripts/membrane_art.gd")
const Visuals = preload("res://scripts/visuals.gd")
var cell
var art: Dictionary = {}
var art_lineage := -2147483648
var art_color:=""
var nucleus_lag := Vector2.ZERO
var last_age := 0.0
var game
var cytoplasm=preload("res://scripts/cytoplasm_view.gd").new()
var seen_revision := -1
var simple_view := false
var last_draw_tick := -2
var emission_seen: Dictionary={}
var emission_started: Dictionary={}
var last_internal_tick := -1
var was_internal := false
var detail_lod := true
var label := Label.new()
var appendages := Node2D.new()
var surface := MeshInstance2D.new()
var interior_backing:=MeshInstance2D.new()
var water_wake := MeshInstance2D.new()
var surface_revision := -1
var depth_style := false
var sound_waves := Node2D.new()
var nucleus_center := Vector2.ZERO
var nucleus_size := 0.0

func _ready() -> void:
	# Keep each shaded body immediately behind its own contents, so another
	# cell can still occlude both instead of exposing every nucleus above all bodies.
	surface.show_behind_parent = true
	surface.material = ShaderMaterial.new()
	surface.material.shader = preload("res://shaders/membrane.gdshader")
	interior_backing.show_behind_parent=true
	interior_backing.material=ShaderMaterial.new()
	interior_backing.material.shader=preload("res://shaders/interior_backing.gdshader")
	add_child(interior_backing)
	add_child(surface)
	add_child(cytoplasm)
	water_wake.z_as_relative=false
	water_wake.z_index = 1 # Cells are at z=2; all wakes remain below every body.
	water_wake.material = ShaderMaterial.new()
	water_wake.material.shader = preload("res://shaders/cell_wake.gdshader")
	add_child(water_wake)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color",Color("21375d"))
	label.add_theme_constant_override("outline_size",4)
	add_child(label)
	appendages.z_index = 1
	add_child(appendages)
	appendages.draw.connect(_draw_organs)
	add_child(sound_waves)
	sound_waves.draw.connect(_draw_sound_waves)

func sync(render_position: Vector2, render_angle: float, zoom: float, alpha: float) -> void:
	var paint: String=game.lineage_color(cell.lineage_id())
	if art_lineage != cell.lineage_id() or paint!=art_color:
		art_lineage = cell.lineage_id();art_color=paint;surface_revision=-1
		art = Art.make(game.world.seed_value,art_lineage,paint)
		art["core"] = Art.nucleus_outline(art.nucleus,art.phase)
		seen_revision = -1
	# Bounded presentation lag follows existing acceleration/turns, never physics.
	var elapsed := clampf(cell.age-last_age,0,0.1)
	last_age = cell.age
	var drift: Vector2 = (-cell.shape_acceleration.rotated(-render_angle)*0.002+Vector2(0,-cell.angular_velocity)*cell.radius*0.025).limit_length(cell.radius*0.055)
	nucleus_lag = nucleus_lag.lerp(drift,1-exp(-elapsed*6))
	sound_waves.queue_redraw()
	position = render_position
	rotation = render_angle
	if depth_style != game.membrane_depth:
		depth_style = game.membrane_depth
		seen_revision = -1
		surface_revision = -1
		surface.visible = depth_style
	var internal: bool=game.internal_visible(cell)
	interior_backing.visible=internal
	interior_backing.mesh=surface.mesh if surface.mesh!=null else Surface.mesh(cell.membrane.outline(),game.native_geometry)
	cytoplasm.visible=internal
	if internal:cytoplasm.sync(cell.chemistry,alpha,game.perception_mask.viewport.get_texture(),maxf(1,cell.extent()*1.05))
	if internal!=was_internal or (internal and last_internal_tick!=cell.chemistry.tick):
		queue_redraw();last_internal_tick=cell.chemistry.tick;was_internal=internal
	var reduced: bool = detail_lod and cell.radius*zoom < 18 and not game.build_open and not internal
	var detail_changed: bool = reduced != simple_view
	simple_view = reduced
	if (seen_revision != cell.render_revision and (not reduced or game.world.revision-last_draw_tick >= 2)) or detail_changed or game.show_senses != get_meta("senses",false) or game.build_open != get_meta("assembly",false):
		seen_revision = cell.render_revision
		last_draw_tick = game.world.revision
		set_meta("senses",game.show_senses)
		set_meta("assembly",game.build_open)
		queue_redraw()
		appendages.queue_redraw()
	water_wake.visible = depth_style and game.flow_wakes
	if depth_style:
		_sync_surface(render_angle,detail_changed)
	label.visible = cell.rival_name != "" and (game.show_senses or get_global_mouse_position().distance_to(global_position) < cell.extent()*zoom+20)
	if label.visible:
		label.text = cell.rival_name
		label.rotation = -rotation
		label.scale = Vector2.ONE/zoom
		label.position = Vector2(-label.size.x/2/zoom,-cell.extent()-22/zoom).rotated(-rotation)

static func relative_flow(body, fluid, heading: float) -> Vector2:
	var water := Vector2.ZERO
	for i in 6:
		var a: float = TAU*i/6.0
		var at: Vector2 = body.position+body.local_point(a).rotated(heading)*1.35
		water += fluid.sample(at)/6.0
	return (water-body.velocity).rotated(-heading)

func _sync_surface(render_angle: float, changed: bool) -> void:
	if surface_revision != seen_revision or changed:
		var mark := Time.get_ticks_usec() if game.frame_trace != null else 0
		var outline: PackedVector2Array = cell.membrane.outline()
		if simple_view:
			var reduced := PackedVector2Array()
			for i in range(0,outline.size(),4): reduced.append(outline[i])
			outline = reduced
		surface.mesh = Surface.mesh(outline,game.native_geometry)
		water_wake.mesh = surface.mesh
		if game.frame_trace != null:
			game.frame_trace.work("geometry",Time.get_ticks_usec()-mark)
			game.frame_trace.count("mesh_updates")
		surface_revision = seen_revision
		for pair in [["edge",0],["body",1],["gel",2],["rim",3],["shine",4]]:
			surface.material.set_shader_parameter(pair[0],art.colors[pair[1]])
	var slip: Vector2 = cell.velocity-game.world.fluid.sample(cell.position)
	surface.material.set_shader_parameter("heading",render_angle)
	surface.material.set_shader_parameter("hurt",cell.hurt_flash)
	surface.material.set_shader_parameter("clock",game.world.time)
	surface.material.set_shader_parameter("slip",slip)
	surface.material.set_shader_parameter("wakes",false)
	water_wake.material.set_shader_parameter("relative_flow",relative_flow(cell,game.world.fluid,render_angle))
	water_wake.material.set_shader_parameter("clock",game.world.time)


func _draw() -> void:
	var mark := Time.get_ticks_usec() if game.frame_trace != null else 0
	if cell == null: return
	var palette: Array = art.colors
	var hue: Color = palette[1]
	var outline: PackedVector2Array = cell.membrane.outline()
	if simple_view:
		var reduced_outline := PackedVector2Array()
		for i in range(0,outline.size(),4): reduced_outline.append(outline[i])
		outline = reduced_outline
	if not depth_style:
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
		draw_line(a,b,hue.lightened(0.45)*Color(1,1,1,0.12+link.tension*0.08),0.7+link.tension*0.6,true)
	# Junctions remain physical but have no visible handles or editing affordances.
	if not simple_view and cell != game.world.player and game.internal_visible(cell):
		for vacuole in cell.chemistry.vacuoles:
			draw_arc(vacuole.p,vacuole.radius,0,TAU,16,Color("8fe3bf").lerp(Color("f497c4"),vacuole.acid),0.8,true)
	var safe_radius: float = cell.radius
	for point in outline: safe_radius = minf(safe_radius,point.length())
	var nucleus: Vector2 = Vector2(-0.12,-0.10)*safe_radius+nucleus_lag
	var core: PackedVector2Array = art.core
	if simple_view:
		var reduced_core := PackedVector2Array()
		for i in range(0,core.size(),2): reduced_core.append(core[i])
		core = reduced_core
	var size := safe_radius*0.28
	nucleus_center = nucleus
	nucleus_size = size
	Visuals.nucleus_art(self,nucleus,size,core,palette,not simple_view)
	for packet in (cell.signals if game.internal_visible(cell) else []): draw_circle(packet.p,3*Visuals.INTERNAL_PARTICLE_SCALE,Color("fc8c90") if packet.fear else Color("b5a3f4"))
	for hole in cell.holes:
		var at: Vector2 = cell.local_point(hole.a)
		draw_circle(at,3+hole.size*6,Color("27325e"))
		draw_arc(at,4+hole.size*6,0,TAU,16,Color("fc8c90"),1.5,true)
	if game.show_senses:
		draw_line(Vector2.ZERO,cell.target.rotated(-cell.angle)*(cell.radius+80),Color("b5a3f4"),2,true)

	if game.frame_trace != null: game.frame_trace.work("cell_draw_commands",Time.get_ticks_usec()-mark)

func _draw_organs() -> void:
	var mark := Time.get_ticks_usec() if game.frame_trace != null else 0
	# A small shared waste outlet, attached to the actual pellicle.
	var outlet: Vector2 = cell.local_point(cell.excretion_angle())
	var outlet_normal: Vector2 = cell.local_normal(cell.excretion_angle())
	appendages.draw_line(outlet-outlet_normal.orthogonal()*5,outlet+outlet_normal.orthogonal()*5,Color("9677cb"),3,true)
	for organ in cell.organs:
		var point: Vector2 = cell.local_point(organ.a)
		var normal: Vector2 = cell.organ_normal(organ)
		var at: Vector2 = cell.organ_local_position(organ)
		var heading := normal.angle()
		var serial: int=int(organ.get("emission_serial",0))
		if not emission_seen.has(organ.id) and cell.age-float(organ.get("emission_age",-100))>.3:emission_seen[organ.id]=serial
		if serial!=int(emission_seen.get(organ.id,0)):
			emission_seen[organ.id]=serial
			if game.ui_time-float(emission_started.get(organ.id,-100))>=.28:emission_started[organ.id]=game.ui_time
		var elapsed: float=game.ui_time-float(emission_started.get(organ.id,-100))
		var bounce:=sin(elapsed*TAU*3)*exp(-elapsed*7) if elapsed<.65 else 0.0
		at+=normal*bounce*5*organ.scale
		var drawn_scale: float=organ.scale*(1+.12*bounce)
		var readiness: Dictionary=preload("res://scripts/organelle_status.gd").state(game.world,cell,organ)
		var charge: float = organ.charge_flash
		if organ.kind == "toxin" and cell.target_id >= 0 and cell.threat.length_squared() > 0.01 and cell.biomass >= 0.18*organ.scale*organ.scale*cell.Genes.factor(organ,"burst"):
			charge = maxf(charge,clampf(1-float(organ.get("burst_clock",0))/(0.75*cell.Genes.factor(organ,"cooldown")),0,1))
		if cell.inherent(organ):
			Visuals.oral_groove(appendages,cell,organ,cell.age,not simple_view)
		else:
			Visuals.icon(appendages,at,organ.kind,heading,drawn_scale,cell.age,organ.mode,organ.consume_flash,not simple_view,charge,readiness.depleted,preload("res://scripts/toxin_sac.gd").fraction(organ) if organ.kind=="toxin_sac" else 0)
		if readiness.progress>=0:
			appendages.draw_arc(at,19*organ.scale,-PI/2,-PI/2+TAU*maxf(.001,readiness.progress),28,Color("fff0ac") if not readiness.depleted else Color("8c969f"),1.8*organ.scale,true)
		if organ.get("mutation","") != "": appendages.draw_circle(at,3.5*organ.scale,Color("fff2a3"))
		if organ.blocked > 0:
			appendages.draw_arc(at,15*organ.scale,-PI/2,-PI/2+TAU*organ.blocked,28,Color("cf92e8"),4*organ.scale,true)
		if organ.charge_flash > 0:
			appendages.draw_arc(at,11*organ.scale+organ.charge_flash*6,0,TAU,24,Color(0.96,0.84,0.48,organ.charge_flash),2,true)
		if game.show_senses and organ.kind in ["feeding","sensing","hunting"]:
			appendages.draw_arc(at,(120 if organ.kind == "hunting" else 90 if organ.kind == "sensing" else 310)*sqrt(organ.scale)*(1-organ.blocked*0.65)*cell.Genes.factor(organ,"sense"),0,TAU,48,Color(0.6,0.55,0.96,0.22),1,true)
		if organ.kind == "feeding" and organ.feeding:
			var end: Vector2 = game.world.Medium.offset(cell.position,organ.link).rotated(-cell.angle)
			appendages.draw_line(at,end,Color("fff0b4"),3,true)
			for i in 3:
				var t := fposmod(cell.age*1.5+i/3.0,1.0)
				appendages.draw_circle(end.lerp(at,t),4,Color("a1e88a"))
		if organ.hp < organ.max_hp:
			appendages.draw_arc(at,19*organ.scale,-PI/2,-PI/2+TAU*organ.hp/organ.max_hp,24,Color("fc8c90"),2,true)

	for complex in cell.surface_complexes:
		preload("res://scripts/pore_art.gd").draw(appendages,cell,complex)
	if game.frame_trace != null: game.frame_trace.work("organ_draw_commands",Time.get_ticks_usec()-mark)

func _draw_sound_waves() -> void:
	if game.music == null: return
	for wave in game.music.waves:
		if wave.source != cell.id: continue
		var at: Vector2 = nucleus_center
		var start: float = nucleus_size
		if wave.organ_id == -2:
			at = cell.local_point(0)*0.60
			if cell == game.world.player:
				for parcel in game.cell_ui.interior.ecology.parcels:
					if parcel.kind == "food": at = parcel.p; break
			start = 4
		elif wave.organ_id >= 0:
			var organ: Dictionary = cell.organ_by_id(wave.organ_id)
			if organ.is_empty(): continue
			at = cell.local_point(organ.a)
			start = 10*organ.scale
		var phase: float = wave.age/0.65
		var tint: Color = game.music.Score.note_color(wave.note)
		# Concentric local waves show scheduled notes, never pulse chemical particles.
		for i in 2:
			var progress := clampf(phase-i*0.12,0,1)
			sound_waves.draw_arc(at,start+progress*30,0,TAU,24,Color(tint,(1-progress)*wave.strength*(0.8 if i == 0 else 0.35)),1.2/game.zoom,true)
