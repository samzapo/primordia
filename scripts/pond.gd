extends Node2D
const Simulation = preload("res://scripts/simulation.gd")
const PARTICLE_SHADER = preload("res://shaders/particle.gdshader")
const ORIGIN := Vector2(32, 154)
const ARENA := Rect2(ORIGIN, Simulation.VIEW)
const BG := Color("0a1825")
const PANEL := Color("102735")
const LINE := Color("254552")
const TEXT := Color("e5f5ec")
const MUTED := Color("88a9af")
const MINT := Color("80efce")
const GOLD := Color("f5d47b")
const CORAL := Color("fc8c90")
const PURPLE := Color("b5a3f4")
const PALETTE := [Color("a1e88a"), Color("70d6e1"), Color("af9ac3"), Color("fc8c90"), Color("f6b86a")]
const TITLES := ["Flagellum", "Protective cortex", "Toxin vesicle", "Repair body", "Feeding pore", "Chemoreceptor"]
const DESCRIPTIONS := ["Thrust follows the cell's signals", "Protects the membrane beneath it", "Fires damaging chemical particles", "Speeds closure and organelle repair", "Graze / engulf / parasite · press F", "Senses food and nearby cell traces"]
const ACCENTS := [MINT, Color("9fcaee"), CORAL, Color("ecacd9"), GOLD, PURPLE]
var world: Simulation = Simulation.new()
var font: Font
var actors: Node2D
var overlay: Node2D
var batches: Array[MultiMeshInstance2D] = []
var feeding_mode := 0
var selected := -1
var paused := false
var show_senses := false
var ui_time := 0.0
var notice := "Choose an organelle, then click the membrane."
var notice_timer := 0.0
var screenshot_path := ""
var capture_frame := 0

func _ready() -> void:
	font = ThemeDB.fallback_font
	var world_layer = Control.new()
	world_layer.position = ORIGIN
	world_layer.size = Simulation.VIEW
	world_layer.clip_contents = true
	world_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_layer)
	for kind in 5:
		var instance = MultiMeshInstance2D.new()
		var mesh = QuadMesh.new()
		mesh.size = Vector2.ONE
		var multi = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_2D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = 5000
		multi.visible_instance_count = 0
		instance.multimesh = multi
		var material = ShaderMaterial.new()
		material.shader = PARTICLE_SHADER
		instance.material = material
		world_layer.add_child(instance)
		batches.append(instance)
	actors = Node2D.new()
	actors.z_index = 1
	actors.position = -ORIGIN
	world_layer.add_child(actors)
	actors.draw.connect(_draw_organisms)
	var vignette = ColorRect.new()
	vignette.size = Simulation.VIEW
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.z_index = 3
	var vignette_material = ShaderMaterial.new()
	vignette_material.shader = preload("res://shaders/microscope.gdshader")
	vignette.material = vignette_material
	world_layer.add_child(vignette)
	overlay = Node2D.new()
	overlay.z_index = 10
	add_child(overlay)
	overlay.draw.connect(_draw_overlays)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			screenshot_path = arg.trim_prefix("--capture=")
			set_physics_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--habitat="):
			world = Simulation.new(world.seed_value,int(arg.trim_prefix("--habitat=")))
		elif arg.begins_with("--advance="):
			for i in int(arg.trim_prefix("--advance=")):
				world.step(1.0 / 60.0)
		elif arg == "--assembly":
			selected = 1
		elif arg == "--senses":
			show_senses = true
	_sync_particles()

func _physics_process(dt: float) -> void:
	if not paused and selected < 0:
		world.step(dt)

func _process(dt: float) -> void:
	ui_time += dt
	notice_timer = maxf(0, notice_timer - dt)
	_sync_particles()
	queue_redraw()
	actors.queue_redraw()
	overlay.queue_redraw()
	if screenshot_path != "":
		capture_frame += 1
		if capture_frame == 60:
			_capture.call_deferred()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var result = image.save_png(screenshot_path)
	print("CAPTURE ", screenshot_path, " result=", result)
	get_tree().quit(result)

func _sync_particles() -> void:
	var sizes = [6.5, 3.8, 4.0, 4.5, 9.0]
	var counts = [0, 0, 0, 0, 0]
	for particle in world.particles:
		if not particle.alive or not Rect2(Vector2(-20,-20),Simulation.VIEW+Vector2(40,40)).has_point(world.screen_position(particle.p)): continue
		var kind: int = particle.kind
		var index: int = counts[kind]
		if index >= 5000: continue
		var diameter: float = sizes[kind]
		var color: Color = PALETTE[kind]
		if kind == Simulation.OXYGEN: color.a = 0.56
		if kind == Simulation.DANGER: color.a = 0.5
		if particle.life > 0: color.a *= minf(1, particle.life)
		batches[kind].multimesh.set_instance_transform_2d(index, Transform2D(0, Vector2.ONE * diameter, 0, world.screen_position(particle.p)))
		batches[kind].multimesh.set_instance_color(index, color)
		counts[kind] += 1
	for kind in 5:
		batches[kind].multimesh.visible_instance_count = counts[kind]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			_select(event.keycode - KEY_1)
		elif event.keycode == KEY_SPACE:
			paused = not paused
		elif event.keycode == KEY_ESCAPE:
			selected = -1
		elif event.keycode == KEY_S:
			show_senses = not show_senses
		elif event.keycode == KEY_F:
			feeding_mode = (feeding_mode+1)%3
			selected = -1
			_select(4)
		elif event.keycode == KEY_H:
			_restart((world.habitat+1)%3)
		elif event.keycode == KEY_R:
			_restart()
	if event is InputEventMouseButton and event.pressed:
		var mouse: Vector2 = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Rect2(1124, 40, 128, 37).has_point(mouse):
				paused = not paused
			elif Rect2(1264, 40, 142, 37).has_point(mouse):
				_restart()
			elif Rect2(879, 804, 168, 32).has_point(mouse):
				show_senses = not show_senses
			else:
				for i in 6:
					if _card(i).has_point(mouse): _select(i)
				if ARENA.has_point(mouse) and selected >= 0:
					var relative = mouse-ORIGIN-Simulation.VIEW*0.5
					var local_angle = world.player.surface_parameter(relative.angle()-world.player.angle)
					if absf(relative.length()-world.player.support(relative.angle())) < 25:
						if world.install(Simulation.KINDS[selected],local_angle,Simulation.Cell.MODES[feeding_mode]):
							_message(TITLES[selected]+" attached. Watch your cell adapt.")
							selected = -1
						else:
							_message("Needs free membrane and biomass. Right-click an organelle to recycle.")
		elif event.button_index == MOUSE_BUTTON_RIGHT and ARENA.has_point(mouse):
			for i in world.player.organs.size():
				var p = ORIGIN+world.screen_position(world.player.organ_position(world.player.organs[i]))
				if mouse.distance_to(p) < 20 and world.remove(i):
					_message("Half the remaining material returned; the rest becomes recyclable debris.")
					break

func _select(index: int) -> void:
	if world.player.health <= 0:
		_message("This cell has perished. Start a new life to continue.")
		return
	if selected == index:
		selected = -1
		return
	if world.player.biomass < Simulation.COST[index]:
		_message("More biomass needed. Feed and metabolize to grow.")
		return
	selected = index
	_message("Assembly paused. Click any free stretch of membrane.")

func _message(value: String) -> void:
	notice = value
	notice_timer = 5.0

func _restart(profile: int = -1) -> void:
	world = Simulation.new(world.seed_value,world.habitat if profile < 0 else profile)
	selected = -1
	paused = false
	_message("A new life begins. Your organelles do the steering.")

func _card(index: int) -> Rect2:
	return Rect2(1090, 212 + index * 82, 316, 73)

func _text(canvas: Node2D, p: Vector2, value: String, size: int = 16, color: Color = TEXT) -> void:
	canvas.draw_string(font, p, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _box(canvas: Node2D, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, corner: int = 12) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(corner)
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	canvas.draw_style_box(style, rect)

func _draw() -> void:
	if font == null: return
	draw_rect(Rect2(Vector2.ZERO, Vector2(1440, 900)), BG)
	_text(self, Vector2(32, 69), "primordia", 46, TEXT)
	_text(self, Vector2(36, 96), "A SMALL LIFE. AN ENTIRE WORLD.", 12, MINT)
	_stat(468, "MEMBRANE", "%03d%%" % int(world.player.health), world.player.health / 100.0, MINT if world.player.health > 35 else CORAL)
	_stat(656, "ENERGY / ATP", "%03d" % int(world.player.energy), world.player.energy / 100.0, GOLD)
	_stat(844, "BIOMASS", "%02d" % int(world.player.biomass), minf(world.player.biomass / 50, 1), PURPLE)
	_box(self, Rect2(1124, 40, 128, 37), PANEL, LINE, 9)
	_text(self, Vector2(1143, 64), "RESUME" if paused else "PAUSE  II", 13)
	_box(self, Rect2(1264, 40, 142, 37), PANEL, LINE, 9)
	_text(self, Vector2(1284, 64), "NEW LIFE  ↻", 13)
	draw_line(Vector2(32, 119), Vector2(1406, 119), LINE, 1)
	_text(self, Vector2(32, 143), "01  /  " + Simulation.HABITATS[world.habitat], 12, MUTED)
	_text(self, Vector2(850, 143), "%02d:%02d  ALIVE" % [int(world.time + 0.001) / 60, int(world.time + 0.001) % 60], 12, MINT)
	_box(self, ARENA, Color("102d39"), LINE, 18)
	_draw_habitat()
	_text(self, Vector2(56, 185), "THE LIVING MEDIUM", 10, Color("688d94"))
	_text(self, Vector2(1090, 160), "BUILD YOUR CELL", 19)
	_text(self, Vector2(1090, 184), "Choose an organelle. Click the membrane.", 13, MUTED)
	for i in 6:
		var rect = _card(i)
		var hover = rect.has_point(get_global_mouse_position())
		var active = selected == i
		_box(self, rect, Color("1b3945") if active or hover else PANEL, ACCENTS[i] if active else LINE, 11)
		_box(self, Rect2(rect.position + Vector2(12, 14), Vector2(44, 44)), Color("193541"), Color.TRANSPARENT, 10)
		_icon(self, rect.position + Vector2(34, 36), Simulation.KINDS[i], 0, 0.77)
		_text(self, rect.position + Vector2(68, 27), ("Proboscis" if feeding_mode == 2 else ("Engulfing pore" if feeding_mode == 1 else TITLES[i])) if i == 4 else TITLES[i], 16)
		_text(self, rect.position + Vector2(68, 49), DESCRIPTIONS[i], 10, MUTED)
		_text(self, rect.position + Vector2(268, 27), "%d" % Simulation.COST[i], 15, ACCENTS[i] if world.player.biomass >= Simulation.COST[i] else MUTED)
		_text(self, rect.position + Vector2(294, 62), str(i + 1), 10, MUTED)
	_box(self, Rect2(1090, 721, 316, 115), Color("162f3a"), LINE)
	_text(self, Vector2(1107, 747), "YOUR FIRST ADAPTATION", 11, MINT)
	_text(self, Vector2(1107, 773), "Process 40 food units. Live 90 seconds.", 12)
	var progress: float = minf(1, minf(world.player.processed / 40, world.time / 90))
	_box(self, Rect2(1107, 787, 280, 5), LINE, Color.TRANSPARENT, 2)
	if progress > 0:
		_box(self, Rect2(1107, 787, 280 * progress, 5), MINT, Color.TRANSPARENT, 2)
	_text(self, Vector2(1107, 817), "ADAPTED · keep exploring" if world.won else "%d / 40 processed     ·     %d / 90 sec" % [int(world.player.processed), int(world.time + 0.001)], 12, MINT if world.won else MUTED)
	_text(self, Vector2(32, 818), "METABOLISM", 11, MINT)
	_text(self, Vector2(32, 843), "Food + oxygen  →  ATP + biomass + recyclable waste", 16)
	_text(self, Vector2(500, 818), "SUBSTRATE  %.1f" % world.player.substrate, 12, PALETTE[0])
	_text(self, Vector2(666, 818), "OXYGEN  %.1f" % world.player.oxygen, 12, PALETTE[1])
	_box(self, Rect2(879, 804, 168, 32), PANEL, MINT if show_senses else LINE, 8)
	_text(self, Vector2(898, 825), "SENSE VIEW  [S]", 12, MINT if show_senses else MUTED)
	draw_line(Vector2(32, 858), Vector2(1406, 858), LINE)
	_text(self, Vector2(32, 884), "NO STEERING. JUST ADAPTATION.", 11, MINT)
	_text(self, Vector2(363, 884), "1–6 build · F feeding mode · right-click recycle · Space pause · H habitat · R restart", 12, MUTED)
	_text(self, Vector2(1270, 884), "LIVING CELL / 0.2", 11, MUTED)

func _stat(x: float, label: String, value: String, fraction: float, color: Color) -> void:
	_text(self, Vector2(x, 44), label, 10, MUTED)
	_text(self, Vector2(x, 79), value, 28, color)
	_box(self, Rect2(x, 92, 150, 4), LINE, Color.TRANSPARENT, 2)
	if fraction > 0:
		_box(self, Rect2(x, 92, 150 * fraction, 4), color, Color.TRANSPARENT, 2)

func _draw_habitat() -> void:
	_text(self,Vector2(1090,204),"FEEDING: "+Simulation.Cell.MODES[feeding_mode].to_upper()+"  [F]",10,GOLD)

func _draw_legend(c: Node2D) -> void:
	var x = 59.0
	for i in 4:
		var names = ["NUTRIENTS", "OXYGEN", "CELL TRACE", "WASTE / RECYCLES"]
		var colors = [PALETTE[0], PALETTE[1], CORAL, PALETTE[2]]
		c.draw_circle(Vector2(x, 759), 3.5, colors[i])
		_text(c, Vector2(x + 12, 763), names[i], 10, MUTED)
		x += [131.0, 108.0, 135.0, 170.0][i]

func _draw_organisms() -> void:
	var c = actors
	# World-anchored currents remain continuous when the camera crosses a seam.
	var camera: Vector2 = world.player.position
	var corner = camera-Simulation.VIEW*0.5
	for x in range(floori(corner.x/64),ceili((corner.x+Simulation.VIEW.x)/64)+1):
		for y in range(floori(corner.y/64),ceili((corner.y+Simulation.VIEW.y)/64)+1):
			var at = Vector2(x+0.5,y+0.5)*64
			var p = ORIGIN+world.screen_position(at)
			var flow: Vector2 = world.fluid.sample(at)
			c.draw_circle(p,1.2,Color("345967"))
			c.draw_line(p,p+flow*0.55,Color(0.32,0.64,0.69,0.23),1.2,true)
	for cell in world.cells:
		var p = ORIGIN+world.screen_position(cell.position)
		if not ARENA.grow(cell.radius+65).has_point(p): continue
		_draw_cell(c,cell,p)
	if selected >= 0:
		var center = ORIGIN+Simulation.VIEW*0.5
		var relative = get_global_mouse_position()-center
		var a = world.player.surface_parameter(relative.angle()-world.player.angle)
		var point: Vector2 = center+(world.player.local_point(a)+Vector2.from_angle(a)*5).rotated(world.player.angle)
		var fits: bool = world.player.can_fit(Simulation.KINDS[selected],a)
		c.draw_arc(center,world.player.radius+26,0,TAU,80,Color(0.5,0.94,0.8,0.3),1,true)
		c.draw_circle(point,20,Color(0.06,0.15,0.2,0.85))
		_icon(c,point,Simulation.KINDS[selected],a+world.player.angle,0.8)
		c.draw_arc(point,21,0,TAU,36,MINT if fits else CORAL,2,true)

func _draw_cell(c: Node2D, cell, p: Vector2) -> void:
	var yours: bool = cell == world.player
	var hue = MINT if yours else (CORAL if cell.role == "hunter" else GOLD)
	var outline: PackedVector2Array = cell.membrane.outline()
	var poly = PackedVector2Array()
	var inner = PackedVector2Array()
	var shadow = PackedVector2Array()
	for point in outline:
		var rotated: Vector2 = point.rotated(cell.angle)
		poly.append(p+rotated)
		inner.append(p+rotated*0.87)
		shadow.append(p+rotated*1.04+Vector2(0,7))
	c.draw_colored_polygon(shadow,Color(0.01,0.07,0.12,0.4))
	c.draw_colored_polygon(poly,hue.lerp(Color.WHITE,cell.hurt_flash*0.7))
	c.draw_colored_polygon(inner,hue.darkened(0.35))
	var closed = poly.duplicate()
	closed.append(poly[0])
	c.draw_polyline(closed,hue.lightened(0.3),2,true)
	# The visible chords are the actual internal tension constraints.
	for ends in [[0,14],[7,21],[3,17],[10,24]]:
		var a: Vector2 = p+cell.membrane.points[ends[0]].rotated(cell.angle)*0.92
		var b: Vector2 = p+cell.membrane.points[ends[1]].rotated(cell.angle)*0.92
		c.draw_line(a,b,hue.lightened(0.3)*Color(1,1,1,0.36),2,true)
	c.draw_circle(p+Vector2(-7,-7).rotated(cell.angle),cell.radius*0.3,Color("a99bde"))
	c.draw_circle(p+Vector2(-5,-9).rotated(cell.angle),cell.radius*0.2,Color("d7b3e9"))
	for i in 7:
		var q: Vector2 = p+Vector2.from_angle(i*2.3+cell.angle)*cell.radius*(0.5+0.13*sin(i*7.0))
		c.draw_circle(q,3.5+i%2,hue.lightened(0.2))
	for packet in cell.signals:
		c.draw_circle(p+packet.p.rotated(cell.angle),3,CORAL if packet.fear else PURPLE)
	for organ in cell.organs:
		var at = ORIGIN+world.screen_position(cell.organ_position(organ))
		var heading: float = cell.angle+organ.a
		_icon(c,at,organ.kind,heading,1.0)
		if organ.kind == "feeding" and organ.mode == "parasite":
			c.draw_line(at,at+Vector2.from_angle(heading)*40,GOLD,5,true)
			c.draw_line(at,at+Vector2.from_angle(heading)*39,Color("5c7880"),2,true)
		elif organ.kind == "feeding" and organ.mode == "engulf":
			c.draw_arc(at,20,heading-1,heading+1,20,GOLD,4,true)
		if organ.hp < organ.max_hp:
			c.draw_arc(at,19,-PI*0.5,-PI*0.5+TAU*organ.hp/organ.max_hp,30,CORAL,2,true)
		if show_senses and organ.kind == "sensing":
			c.draw_arc(at,190,0,TAU,80,Color(0.7,0.64,0.95,0.22),1,true)
			c.draw_line(at,at+cell.target*75,PURPLE,1,true)
	for hole in cell.holes:
		var at: Vector2 = p+cell.local_point(hole.a).rotated(cell.angle)
		c.draw_circle(at,3+hole.size*6,Color("102d39"))
		c.draw_arc(at,4+hole.size*6,0,TAU,16,CORAL,1.5,true)
	if cell.reaction_flash > 0:
		c.draw_arc(p,cell.radius+20,-0.4,0.6,24,Color(0.7,1,0.55,cell.reaction_flash),2,true)
	var label = "YOUR CELL" if yours else cell.role.to_upper()
	_text(c,p+Vector2(-34,-cell.radius*cell.aspect-47),label,10,hue)
	if not yours:
		c.draw_line(p+Vector2(-20,-cell.radius*cell.aspect-35),p+Vector2(-20+40*cell.health/100,-cell.radius*cell.aspect-35),hue,3)

func _icon(c: Node2D, p: Vector2, kind: String, rotation: float, scale: float) -> void:
	var forward = Vector2.from_angle(rotation)
	var side = forward.orthogonal()
	match kind:
		"propulsion":
			var path = PackedVector2Array()
			for i in 22:
				var t = i / 21.0
				path.append(p + forward * (t * 43 * scale) + side * sin(t * 7 - ui_time * 9) * t * 10 * scale)
			c.draw_polyline(path, MINT, 4 * scale, true)
			c.draw_circle(p, 8 * scale, Color("cee8a5"))
			c.draw_circle(p, 4 * scale, Color("418e8d"))
		"protection":
			var polygon = PackedVector2Array()
			for i in 6:
				polygon.append(p + Vector2.from_angle(rotation + TAU*i/6.0) * 15 * scale)
			c.draw_colored_polygon(polygon, Color("9fcaee"))
			c.draw_circle(p, 8 * scale, Color("619fbd"))
			c.draw_line(p-side*7*scale, p+side*7*scale, Color("d4e9f4"), 2*scale)
		"offensive":
			c.draw_circle(p, 12*scale, Color("f2909e"))
			c.draw_circle(p-forward*3*scale, 7*scale, Color("b55976"))
			c.draw_line(p, p+forward*20*scale, Color("ffc78c"), 7*scale, true)
			c.draw_circle(p+forward*20*scale, 3*scale, Color("fff0b7"))
		"regenerative":
			c.draw_circle(p, 13*scale, Color("e6a6d7"))
			c.draw_circle(p, 9*scale, Color("9e72b2"))
			c.draw_line(p-side*5*scale, p+side*5*scale, Color("ffe2e5"), 3*scale)
			c.draw_line(p-forward*5*scale, p+forward*5*scale, Color("ffe2e5"), 3*scale)
		"feeding":
			c.draw_circle(p, 14*scale, GOLD)
			c.draw_circle(p+forward*3*scale, 8*scale, Color("527e71"))
			c.draw_arc(p, 14*scale, rotation+0.8, rotation+TAU-0.8, 28, Color("fff0b4"), 3*scale, true)
		"sensing":
			c.draw_line(p-forward*6*scale, p+forward*13*scale, PURPLE, 5*scale, true)
			for sign_value in [-1, 1]:
				var tip: Vector2 = p + forward*19*scale + side*sign_value*9*scale
				c.draw_line(p+forward*10*scale, tip, PURPLE, 4*scale, true)
				c.draw_circle(tip, 4*scale, Color("dcc5ff"))
			c.draw_circle(p, 7*scale, Color("a393d1"))

func _draw_overlays() -> void:
	_draw_legend(overlay)
	var status: String = world.player.state
	_text(overlay,ARENA.position+Vector2(25,571),"MASS %.0f   MEMBRANE %.0f%% OCCUPIED   RECYCLED %.1f" % [world.player.mass,world.player.occupied()/world.player.perimeter()*100,world.recycled],10,MUTED)
	if selected >= 0: status = "ASSEMBLY PAUSED · CLICK MEMBRANE"
	elif paused: status = "OBSERVATION PAUSED"
	_box(overlay, Rect2(ARENA.position + Vector2(16, 45), Vector2(360, 32)), Color(0.04, 0.12, 0.17, 0.87), LINE, 8)
	overlay.draw_circle(ARENA.position + Vector2(30, 61), 3, MINT)
	_text(overlay, ARENA.position + Vector2(43, 65), status, 11, MINT)
	if notice_timer > 0:
		_box(overlay, Rect2(ARENA.position + Vector2(164, 565), Vector2(690, 35)), Color(0.03, 0.1, 0.16, 0.94), LINE, 8)
		_text(overlay, ARENA.position + Vector2(180, 588), notice, 13)
	if world.player.health <= 0:
		_box(overlay, Rect2(305, 357, 470, 174), Color("142b3b"), CORAL, 16)
		_text(overlay, Vector2(337, 402), "A small life, ended.", 28, CORAL)
		_text(overlay, Vector2(337, 438), "Survived %d seconds · processed %.1f food" % [world.time, world.player.processed], 15)
		_text(overlay, Vector2(337, 469), "Try a different anatomy. Every organelle matters.", 14, MUTED)
		_text(overlay, Vector2(337, 504), "Press R or choose NEW LIFE to begin again.", 14, MINT)
