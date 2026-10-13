extends Control
## A local optical lens. Picking uses the existing spatial grid and rendered poses.
const Art = preload("res://scripts/particle_art.gd")
const DETAILS := [
	"Food collected by grazing pores.",
	"Supports efficient respiration.",
	"Enzymes can convert it into food.",
	"A drifting cell report. Hunting and flight receptors read its last-known location, size and hostility.",
	"Damages foreign cells; antitoxin can neutralize it.",
	"Photosynthesis uses it in bright water.",
	"Reuses waste as food when its binding face aligns.",
	"Binds toxins into harmless waste.",
	"Raises local acidity and changes water color.",
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
	glyph.material = detail_material
	glyph.hide()

func _near_cell(at: Vector2, alpha: float) -> bool:
	var sim = game.world
	var padding: float = 24*game.preferences.hud_scale/game.zoom
	for cell in sim.cells:
		if cell.dead: continue
		var fraction: float = alpha if cell.activity > 0 else 1.0
		var center: Vector2 = cell.previous_position+sim.Medium.offset(cell.previous_position,cell.position)*fraction
		var offset: Vector2 = sim.Medium.offset(center,at)
		if offset.length_squared() > pow(cell.extent()+padding,2): continue
		var heading := lerp_angle(cell.previous_angle,cell.angle,fraction)
		if offset.length() <= cell.visible_support(offset.angle()-heading)+padding: return true
	return false

func _world_at(screen: Vector2) -> Vector2:
	return game.world.Medium.wrap_position(game.render_camera+(screen-game.camera_screen)/game.zoom)

func pick(screen: Vector2, alpha: float) -> Dictionary:
	var sim = game.world
	var at: Vector2 = sim.Medium.wrap_position(game.render_camera+(screen-game.camera_screen)/game.zoom)
	candidates_examined = 0
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
		var screen_point: Vector2 = game.camera_screen+sim.Medium.offset(game.render_camera,p)*game.zoom
		var radius: float = sim.particle_radius(particle.kind)*sim.particle_scale(particle.amount)*game.zoom
		var tolerance: float = maxf(radius+3,7)
		if screen.distance_to(screen_point) > tolerance+10: continue
		if particle.kind != sim.PHEROMONE: p = game._visible_particle_position(p,alpha)
		screen_point = game.camera_screen+sim.Medium.offset(game.render_camera,p)*game.zoom
		var distance := screen.distance_to(screen_point)
		if distance <= tolerance and distance < best and not _near_cell(p,alpha):
			best = distance
			result = {"index":index,"packet":particle,"kind":particle.kind,"screen":screen_point,"angle":angle,"radius":radius}
	return result

func _tracked_pose(alpha: float) -> Dictionary:
	var sim = game.world
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
	var screen: Vector2 = game.camera_screen+sim.Medium.offset(game.render_camera,p)*game.zoom
	if not get_viewport_rect().has_point(screen) or _near_cell(p,alpha): return {}
	return {"index":tracked_index,"packet":tracked_packet,"kind":tracked_packet.kind,"screen":screen,"angle":angle,
		"radius":sim.particle_radius(tracked_packet.kind)*sim.particle_scale(tracked_packet.amount)*game.zoom}

func _resident_pose(packet: Dictionary,cursor: Vector2,alpha: float,picking: bool) -> Dictionary:
	if packet.is_empty() or not packet.alive: return {}
	var sim=game.world
	var screen: Vector2=game.camera_screen+sim.Medium.offset(game.render_camera,packet.p)*game.zoom
	var radius: float=sim.particle_radius(packet.kind)*sim.particle_scale(packet.amount)*game.zoom
	if not get_viewport_rect().has_point(screen) or _near_cell(packet.p,alpha): return {}
	if picking and screen.distance_to(cursor)>maxf(radius+3,7): return {}
	return {"index":packet._index,"packet":packet,"kind":packet.kind,"screen":screen,"angle":packet.angle,"radius":radius}

func update_lens(dt: float, screen: Vector2, alpha: float, allowed: bool) -> void:
	if allowed and _near_cell(_world_at(screen),alpha): allowed = false
	var following := {}
	if allowed and track_remaining > 0 and screen.distance_to(cursor_anchor) <= CURSOR_RELEASE*game.preferences.hud_scale:
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
	if not allowed or (not active and lens_amount > 0 and _near_cell(_world_at(lens_center),alpha)): lens_amount = 0
	var material: ShaderMaterial = game.microscope_layer.material
	material.set_shader_parameter("lens_center",lens_center/get_viewport_rect().size)
	material.set_shader_parameter("lens_amount",lens_amount)
	material.set_shader_parameter("lens_radius",RADIUS*game.preferences.hud_scale/get_viewport_rect().size.x)
	material.set_shader_parameter("lens_magnification",MAGNIFICATION)
	glyph.visible = active and lens_amount > 0
	if glyph.visible:
		var magnification := lerpf(1,MAGNIFICATION,lens_amount)
		glyph.texture = Art.texture(hovered.kind)
		glyph.position = lens_center+(hovered.screen-lens_center)*magnification
		glyph.rotation = hovered.angle
		glyph.scale = Vector2.ONE*hovered.radius*2*magnification/96
		glyph.modulate.a = lens_amount
		glyph.material.set_shader_parameter("lens_center",lens_center/get_viewport_rect().size)
		glyph.material.set_shader_parameter("lens_radius",RADIUS*game.preferences.hud_scale/get_viewport_rect().size.x)
		glyph.material.set_shader_parameter("canvas_aspect",get_viewport_rect().size.y/get_viewport_rect().size.x)
	box.visible = active and lens_amount > 0.15
	if box.visible:
		var value: String = Art.Catalog.data().external_species[hovered.kind].name+"\n"+(DETAILS[hovered.kind] if hovered.kind < DETAILS.size() else "A finite cell-derived chemical packet.")
		if hovered.kind == game.world.PHEROMONE:
			var packet: Dictionary = hovered.packet
			var report: Dictionary = packet.get("report",{})
			if not report.is_empty():
				value += "\nDefense: "+("defended" if report.get("defended",true) else "undefended")+" at emission"
				value += "\nReported size: %.0f μm across · %s\nSignal age: %.1f s" % [report.radius*2*game.scale_bar.MICROMETERS_PER_UNIT,"armed" if report.hostile else "unarmed",maxf(0,game.world.time-report.emitted_at)]
		label.custom_minimum_size.x = minf(260*game.preferences.hud_scale,get_viewport_rect().size.x-36)
		label.add_theme_font_size_override("font_size",roundi(15*game.preferences.hud_scale))
		if label.text != value:
			label.text = value
			box.reset_size()
		var magnified_at: Vector2 = lens_center+((hovered.screen-lens_center)*lerpf(1,MAGNIFICATION,lens_amount)).limit_length(RADIUS*0.45*game.preferences.hud_scale)
		var extent := box.get_combined_minimum_size()
		box.position = (magnified_at+Vector2(18,24)*game.preferences.hud_scale).clamp(Vector2(12,12),get_viewport_rect().size-extent-Vector2(12,12))
	queue_redraw()

func _draw() -> void:
	if lens_amount <= 0: return
	draw_arc(lens_center,RADIUS*game.preferences.hud_scale,0,TAU,64,Color(0.65,0.96,0.92,lens_amount*0.3),1,true)
