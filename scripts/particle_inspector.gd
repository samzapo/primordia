extends Control
## A local optical lens. Picking uses the existing spatial grid and rendered poses.
const Art = preload("res://scripts/particle_art.gd")
const DETAILS := [
	"Food collected by grazing pores. Binding improves ATP yield; mild acid helps it bind.",
	"Supports efficient respiration.",
	"Enzymes can convert it into food.",
	"A drifting cell report. Hunting and flight receptors read its last-known location, size and hostility.",
	"Damages foreign cells; antitoxin can neutralize it.",
	"Photosynthesis uses it in bright water.",
	"Reuses waste as food when its binding face aligns.",
	"Binds toxins into harmless waste.",
	"Helps nutrients bind, but excessive acidity damages cells.",
	"Reduces local acidity.",
	"Temporarily competes for sensing receptors."
]
const RADIUS := 68.0
const MAGNIFICATION := 3.5
const TRACK_SECONDS := 0.9
const CURSOR_RELEASE := 24.0
var tracked_world
var tracked_packet: Dictionary = {}
var tracked_index := -1
var track_remaining := 0.0
var cursor_anchor := Vector2.ZERO
var game
var hovered: Dictionary = {}
var lens_amount := 0.0
var lens_center := Vector2.ZERO
var box := PanelContainer.new()
var label := Label.new()
var candidates_examined := 0
var glyph := Sprite2D.new()
var particle_material: ShaderMaterial
var vacuole_material:=ShaderMaterial.new()
var touch_position:=Vector2.ZERO
var touch_until:=0
func cursor_at(mouse: Vector2) -> Vector2:return touch_position if Time.get_ticks_msec()<touch_until else mouse
func inspect_touch(at: Vector2) -> void:
	touch_position=at;touch_until=Time.get_ticks_msec()+2500

func initialize(owner_game) -> void:
	game = owner_game
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	box.hide()
	box.z_index = 2
	add_child(glyph)
	glyph.z_index = 1
	var detail_material := ShaderMaterial.new()
	detail_material.shader = preload("res://shaders/inspection_particle.gdshader")
	particle_material=detail_material
	vacuole_material.shader=preload("res://shaders/inspection_vacuole.gdshader")
	vacuole_material.set_shader_parameter("glyph_atlas",preload("res://scripts/cytoplasm_view.gd").atlas())
	glyph.material = detail_material
	glyph.hide()

func _near_cell(at: Vector2, alpha: float) -> bool:
	var sim = game.world
	var padding: float = 24*game.cell_ui.ui_scale()/game.zoom
	for cell in sim.cells:
		if cell.dead: continue
		var fraction: float = game._cell_render_alpha(cell,alpha)
		var center: Vector2 = cell.previous_position+sim.Medium.offset(cell.previous_position,cell.position)*fraction
		var offset: Vector2 = sim.Medium.offset(center,at)
		if offset.length_squared() > pow(cell.extent()+padding,2): continue
		var heading := lerp_angle(cell.previous_angle,cell.angle,fraction)
		if offset.length() <= cell.visible_support(offset.angle()-heading)+padding: return true
	return false

func _world_at(screen: Vector2) -> Vector2:
	return game._screen_world(screen)

func _internal_pose(screen: Vector2,alpha: float,identity: int=-1) -> Dictionary:
	var cell=game._follow_cell()
	if not game.internal_visible(cell) or not game.views.has(cell.id):return {}
	var view=game.views[cell.id]
	if identity<0:
		var local: Vector2=view.to_local(screen)
		if local.length()>cell.visible_support(local.angle())+12/game.zoom:return {}
	if cell.chemistry.accelerator!=null:
		var found: Dictionary={};var nearest:=INF
		for v in cell.chemistry.vacuoles:
			if identity>=0 and v.id!=identity:continue
			candidates_examined+=1
			var at: Vector2=game.world_layer.to_global(view.position+v.p.rotated(view.rotation))
			if not get_viewport_rect().has_point(at):continue
			var distance:=screen.distance_to(at)
			if (identity>=0 or distance<=maxf(v.radius*game.zoom+4,12)) and distance<nearest:
				nearest=distance
				if v.get("species","") in ["oxygen","carbon"]:
					found={"index":-1,"packet":{"id":v.id,"species":v.species,"amount":v.contents},"internal":true,"gas":true,"cell_id":cell.id,"kind":1 if v.species=="oxygen" else 5,"screen":at,"angle":view.rotation+float(v.get("angle",0)),"radius":v.radius*game.zoom}
					continue
				var food: float=v.contents*(1-v.acid);var waste: float=v.contents*v.acid
				found={"food":food,"waste":waste,"age":v.age,"index":-1,"packet":{"id":v.id,"species":"food" if food>.0000001 else "waste","amount":food if food>.0000001 else waste},"internal":true,"cell_id":cell.id,"kind":0 if food>.0000001 else 2,"screen":at,"angle":view.rotation,"radius":7*game.zoom}
		return found
	var best:=INF
	var result: Dictionary={}
	var packets: Array=cell.chemistry.particle_snapshots(true)
	for packet in packets:
		if packet.species=="waste" and packets.any(func(food):return food.species=="food" and food.compartment==packet.compartment):continue
		if not packet.alive or (identity>=0 and packet.id!=identity):continue
		candidates_examined+=1
		var origin: Dictionary=cell.chemistry.render_origins.get(packet.id,{})
		var at: Vector2=origin.get("p",packet.p).lerp(packet.p,alpha)
		if at.length()>cell.visible_support(at.angle()):continue
		var position: Vector2=game.world_layer.to_global(view.position+at.rotated(view.rotation))
		if not get_viewport_rect().has_point(position):continue
		var radius: float=preload("res://scripts/visuals.gd").internal_particle_radius(packet)*game.zoom
		var distance:=screen.distance_to(position)
		if (identity>=0 or distance<=maxf(radius+4,12)) and distance<best:
			best=distance
			if packet.species in ["oxygen","carbon"]:
				result={"index":-1,"packet":packet,"internal":true,"gas":true,"cell_id":cell.id,"kind":1 if packet.species=="oxygen" else 5,"screen":position,"angle":view.rotation+packet.angle,"radius":radius}
				continue
			var food:=0.0;var waste:=0.0
			for stock in packets:
				if stock.compartment==packet.compartment and stock.species in ["food","waste"]:
					if stock.species=="food":food+=stock.amount
					else:waste+=stock.amount
			result={"food":food,"waste":waste,"age":packet.get("age",0),"index":-1,"packet":packet,"internal":true,"cell_id":cell.id,"kind":0 if packet.species=="food" else 2,"screen":position,"angle":view.rotation,"radius":radius}
	return result

func pick(screen: Vector2, alpha: float) -> Dictionary:
	var sim = game.world
	var at: Vector2 = game._screen_world(screen)
	candidates_examined = 0
	if game.perception=="interoception":return _internal_pose(screen,alpha)
	# Keep anatomy and feeding clouds visually quiet, including pheromones.
	if _near_cell(at,alpha): return {}
	if sim.resident!=null:
		var packet: Dictionary=sim.resident.inspect(at,8.5+7/game.zoom,Vector2i(-1,-1),game.zoom)
		return _resident_pose(packet,screen,alpha,true)
	if sim.grid.source_size != sim.particle_count(): sim.grid.rebuild(sim.particles)
	var best := INF
	var result := {}
	# One neighboring-bucket query, with padding for one interpolated transport step.
	var ids: Array = sim.grid.query(at,16/game.zoom+64)
	var candidates: Array = sim.kernels.pool_inspection(ids,at,alpha,sim.revision,sim.time,game.zoom) if sim.particle_pool else ids
	for candidate in candidates:
		var index: int = int(candidate.index) if sim.particle_pool else int(candidate)
		var particle: Dictionary = candidate.packet if sim.particle_pool else sim.particles[index]
		if not sim._pheromone_alive(particle): continue
		candidates_examined += 1
		var p: Vector2 = particle.p
		var angle: float = particle.angle
		if particle.get("updated",-1) == sim.revision:
			p = particle.previous+sim.Medium.offset(particle.previous,p)*alpha
			angle = lerp_angle(particle.previous_angle,particle.angle,alpha)
		var screen_point: Vector2 = game._world_screen(p)
		var radius: float = sim.particle_radius(particle.kind)*sim.particle_scale(particle.amount)*game.zoom
		var tolerance: float = maxf(radius+3,7)
		if screen.distance_to(screen_point) > tolerance+10: continue
		if particle.kind != sim.PHEROMONE: p = game._visible_particle_position(p,alpha)
		screen_point = game._world_screen(p)
		var distance := screen.distance_to(screen_point)
		if distance <= tolerance and distance < best and not _near_cell(p,alpha):
			best = distance
			result = {"index":index,"packet":particle,"kind":particle.kind,"screen":screen_point,"angle":angle,"radius":radius}
	return result

func _tracked_pose(alpha: float) -> Dictionary:
	var sim = game.world
	if game.perception=="interoception":
		if tracked_packet.is_empty() or tracked_world!=sim:return {}
		return _internal_pose(cursor_anchor,alpha,tracked_packet.get("id",-1))
	if tracked_world==sim and sim.resident!=null and not tracked_packet.is_empty():
		tracked_packet=sim.resident.inspect(Vector2.ZERO,1,tracked_packet.get("_resident_handle",Vector2i(-1,-1)))
		return _resident_pose(tracked_packet,Vector2.ZERO,alpha,false)
	if tracked_world == sim and sim.particle_pool and not tracked_packet.is_empty():
		tracked_packet = sim.kernels.pool_resolve(tracked_packet.get("_handle",0))
		if not tracked_packet.is_empty(): tracked_index = tracked_packet._index
	if tracked_world != sim or tracked_packet.is_empty() or not sim._pheromone_alive(tracked_packet):
		return {}
	# The native handle resolves the current slot; the reference backend retains
	# dictionary identity through compaction and chemistry.
	# Only recover the index from neighboring buckets if the old slot has moved.
	if not sim.particle_pool and (tracked_index >= sim.particle_count() or not is_same(sim.particles[tracked_index],tracked_packet)):
		if sim.grid.source_size != sim.particle_count(): sim.grid.rebuild(sim.particles)
		tracked_index = -1
		for index in sim.grid.query(tracked_packet.p,1):
			if is_same(sim.particles[index],tracked_packet):
				tracked_index = index
				break
		if tracked_index < 0: return {}
	var p: Vector2 = tracked_packet.p
	var angle: float = tracked_packet.angle
	if tracked_packet.get("updated",-1) == sim.revision:
		p = tracked_packet.previous+sim.Medium.offset(tracked_packet.previous,p)*alpha
		angle = lerp_angle(tracked_packet.previous_angle,angle,alpha)
	if tracked_packet.kind != sim.PHEROMONE: p = game._visible_particle_position(p,alpha)
	var screen: Vector2 = game._world_screen(p)
	if not get_viewport_rect().has_point(screen) or _near_cell(p,alpha): return {}
	return {"index":tracked_index,"packet":tracked_packet,"kind":tracked_packet.kind,"screen":screen,"angle":angle,
		"radius":sim.particle_radius(tracked_packet.kind)*sim.particle_scale(tracked_packet.amount)*game.zoom}

func _resident_pose(packet: Dictionary,cursor: Vector2,alpha: float,picking: bool) -> Dictionary:
	if packet.is_empty() or not packet.alive: return {}
	var sim=game.world
	var screen: Vector2=game._world_screen(packet.p)
	var radius: float=sim.particle_radius(packet.kind)*sim.particle_scale(packet.amount)*game.zoom
	if not get_viewport_rect().has_point(screen) or _near_cell(packet.p,alpha): return {}
	if picking and screen.distance_to(cursor)>maxf(radius+3,7): return {}
	return {"index":packet._index,"packet":packet,"kind":packet.kind,"screen":screen,"angle":packet.angle,"radius":radius}

func update_lens(dt: float, screen: Vector2, alpha: float, allowed: bool) -> void:
	if Time.get_ticks_msec()<touch_until:screen=touch_position
	if allowed and game.perception!="interoception" and _near_cell(_world_at(screen),alpha): allowed = false
	var following := {}
	if allowed and track_remaining > 0 and screen.distance_to(cursor_anchor) <= CURSOR_RELEASE*game.cell_ui.ui_scale():
		following = _tracked_pose(alpha)
		if not following.is_empty():
			track_remaining = maxf(0,track_remaining-dt)
			# Looking directly at the same particle renews the short grace period.
			if screen.distance_to(following.screen) <= maxf(following.radius+3,7):
				track_remaining = TRACK_SECONDS
			if track_remaining <= 0: following = {}
	hovered = following if not following.is_empty() else (pick(screen,alpha) if allowed else {})
	var active := not hovered.is_empty()
	if active:
		if following.is_empty():
			tracked_world = game.world
			tracked_packet = hovered.packet
			tracked_index = hovered.index
			cursor_anchor = screen
			track_remaining = TRACK_SECONDS
		lens_center = hovered.screen
	else:
		tracked_world = null
		tracked_packet = {}
		tracked_index = -1
		track_remaining = 0
	lens_amount = move_toward(lens_amount,1.0 if active else 0.0,dt*9)
	if not allowed or (game.perception!="interoception" and not active and lens_amount > 0 and _near_cell(_world_at(lens_center),alpha)): lens_amount = 0
	var material: ShaderMaterial = game.microscope_layer.material
	material.set_shader_parameter("lens_center",lens_center/get_viewport_rect().size)
	material.set_shader_parameter("lens_amount",lens_amount)
	material.set_shader_parameter("lens_radius",RADIUS*game.cell_ui.ui_scale()/get_viewport_rect().size.x)
	material.set_shader_parameter("lens_magnification",MAGNIFICATION)
	glyph.visible = active and lens_amount > 0
	if glyph.visible:
		var magnification := lerpf(1,MAGNIFICATION,lens_amount)
		glyph.material=vacuole_material if hovered.get("internal",false) and not hovered.get("gas",false) else particle_material
		if hovered.get("internal",false) and not hovered.get("gas",false):
			vacuole_material.set_shader_parameter("contents",Vector3(hovered.food/maxf(.0000001,hovered.food+hovered.waste),clampf(ceilf((hovered.food+hovered.waste)/.3),1,7),game.Simulation.particle_scale((hovered.food+hovered.waste)/clampf(ceilf((hovered.food+hovered.waste)/.3),1,7))))
			vacuole_material.set_shader_parameter("opacity",lens_amount)
		glyph.texture = Art.texture(hovered.kind)
		glyph.position = lens_center+(hovered.screen-lens_center)*magnification
		glyph.rotation = hovered.angle+game.render_rotation
		glyph.scale = Vector2.ONE*hovered.radius*2*magnification/96
		glyph.modulate.a = lens_amount
		glyph.material.set_shader_parameter("lens_center",lens_center/get_viewport_rect().size)
		glyph.material.set_shader_parameter("lens_radius",RADIUS*game.cell_ui.ui_scale()/get_viewport_rect().size.x)
		glyph.material.set_shader_parameter("canvas_aspect",get_viewport_rect().size.y/get_viewport_rect().size.x)
	box.visible = active and lens_amount > 0.15
	if box.visible:
		var value: String = Art.Catalog.data().external_species[hovered.kind].name+"\n"+(DETAILS[hovered.kind] if hovered.kind < DETAILS.size() else "A finite cell-derived chemical packet.")
		if not hovered.get("internal",false) and hovered.kind==0:
			var food: Dictionary=hovered.packet
			var bonus:=clampf(float(food.get("capacity",food.amount))/maxf(.00000001,food.amount)-1,0,float(Art.Catalog.data().ecology.nutrient_bonus_limit))
			value+="\nBinding: +%d%% ATP yield" % roundi(bonus*100)
		if hovered.get("internal",false) and not hovered.get("gas",false):
			value=("Food vacuole\nLocal oxygen supports respiration; otherwise food ferments. Both produce ATP, biomass, carbon and waste." if hovered.kind==0 else "Waste vacuole\nTravels to the cytoproct, then releases waste into the water.")+"\nFood %.2f · Waste %.2f\nResidence %.1f s" % [hovered.food,hovered.waste,hovered.age]
		if hovered.kind == game.world.PHEROMONE:
			var packet: Dictionary = hovered.packet
			var report: Dictionary = packet.get("report",{})
			if not report.is_empty():
				value += "\nDefense: "+("defended" if report.get("defended",true) else "undefended")+" at emission"
				value += "\nReported size: %.0f μm across · %s\nSignal age: %.1f s" % [report.radius*2*game.scale_bar.MICROMETERS_PER_UNIT,"armed" if report.hostile else "unarmed",maxf(0,game.world.time-report.emitted_at)]
		if game.cell_ui.mobile():
			value=value.replace("\n"," · ")
			if value.length()>220:value=value.left(217)+"…"
			label.max_lines_visible=3
		label.custom_minimum_size.x = (get_viewport_rect().size.x-32*game.cell_ui.ui_scale()) if game.cell_ui.mobile() else minf(260*game.cell_ui.ui_scale(),get_viewport_rect().size.x-36)
		label.add_theme_font_size_override("font_size",roundi(15*game.cell_ui.ui_scale()))
		if label.text != value:
			label.text = value
			box.reset_size()
		var magnified_at: Vector2 = lens_center+((hovered.screen-lens_center)*lerpf(1,MAGNIFICATION,lens_amount)).limit_length(RADIUS*0.45*game.cell_ui.ui_scale())
		var extent := box.get_combined_minimum_size()
		box.position = (magnified_at+Vector2(18,24)*game.cell_ui.ui_scale()).clamp(Vector2(12,12),get_viewport_rect().size-extent-Vector2(12,12))
		if game.cell_ui.mobile():
			var scale: float=game.cell_ui.ui_scale()
			box.position=Vector2(8*scale,get_viewport_rect().size.y-game.cell_ui.mobile_resources.get_combined_minimum_size().y-extent.y-16*scale)
	queue_redraw()

func _draw() -> void:
	if lens_amount <= 0: return
	draw_arc(lens_center,RADIUS*game.cell_ui.ui_scale(),0,TAU,64,Color(0.65,0.96,0.92,lens_amount*0.3),1,true)
