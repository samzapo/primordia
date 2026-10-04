extends Node2D
const Simulation = preload("res://scripts/simulation.gd")
const PARTICLE_SHADER = preload("res://shaders/particle.gdshader")
const ORIGIN := Vector2(32, 154)
const ARENA := Rect2(ORIGIN, Simulation.WORLD)
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
const DESCRIPTIONS := ["Thrust follows the cell's signals", "Reduces incoming bite damage", "Fires particles that repel hunters", "Spends resources to heal damage", "Absorbs nearby nutrient particles", "Senses food and predator traces"]
const ACCENTS := [MINT, Color("9fcaee"), CORAL, Color("ecacd9"), GOLD, PURPLE]
var world: Simulation = Simulation.new()
var font: Font
var actors: Node2D
var overlay: Node2D
var batches: Array[MultiMeshInstance2D] = []
var selected := -1
var paused := false
var show_senses := false
var ui_time := 0.0
var notice := "Choose an organelle, then an empty socket."
var notice_timer := 0.0
var screenshot_path := ""
var capture_frame := 0

func _ready() -> void:
	font = ThemeDB.fallback_font
	var world_layer := Control.new()
	world_layer.position = ORIGIN
	world_layer.size = Simulation.WORLD
	world_layer.clip_contents = true
	world_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_layer)
	for kind in 5:
		var instance := MultiMeshInstance2D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_2D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = 900
		multi.visible_instance_count = 0
		instance.multimesh = multi
		var material := ShaderMaterial.new()
		material.shader = PARTICLE_SHADER
		instance.material = material
		world_layer.add_child(instance)
		batches.append(instance)
	actors = Node2D.new()
	actors.z_index = 1
	actors.position = -ORIGIN
	world_layer.add_child(actors)
	actors.draw.connect(_draw_organisms)
	overlay = Node2D.new()
	overlay.z_index = 2
	add_child(overlay)
	overlay.draw.connect(_draw_overlays)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			screenshot_path = arg.trim_prefix("--capture=")
			set_physics_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--advance="):
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
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(screenshot_path)
	print("CAPTURE ", screenshot_path, " result=", result)
	get_tree().quit(result)

func _sync_particles() -> void:
	var sizes := [6.5, 3.8, 4.0, 4.5, 9.0]
	var counts := [0, 0, 0, 0, 0]
	for particle in world.particles:
		var kind: int = particle.kind
		var index: int = counts[kind]
		if index >= 900: continue
		var diameter: float = sizes[kind]
		var color: Color = PALETTE[kind]
		if kind == Simulation.OXYGEN: color.a = 0.56
		if kind == Simulation.DANGER: color.a = 0.5
		if particle.life > 0: color.a *= minf(1, particle.life)
		batches[kind].multimesh.set_instance_transform_2d(index, Transform2D(0, Vector2.ONE * diameter, 0, particle.p))
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
					for slot in 8:
						if mouse.distance_to(ORIGIN + world.slot_position(slot)) < 19:
							if world.install(Simulation.KINDS[selected], slot):
								_message(TITLES[selected] + " attached. Watch your cell adapt.")
								selected = -1
							else:
								_message("Use an empty socket. Right-click to recycle an organelle.")
		elif event.button_index == MOUSE_BUTTON_RIGHT and ARENA.has_point(mouse):
			for slot in 8:
				if mouse.distance_to(ORIGIN + world.slot_position(slot)) < 19 and world.remove(slot):
					_message("Organelle recycled. Half its biomass returned.")
					break

func _select(index: int) -> void:
	if world.health <= 0:
		_message("This cell has perished. Start a new life to continue.")
		return
	if selected == index:
		selected = -1
		return
	if world.biomass < Simulation.COST[index]:
		_message("More biomass needed. Feed and metabolize to grow.")
		return
	selected = index
	_message("Assembly paused. Choose a glowing empty socket.")

func _message(value: String) -> void:
	notice = value
	notice_timer = 5.0

func _restart() -> void:
	world = Simulation.new()
	selected = -1
	paused = false
	_message("A new life begins. Your organelles do the steering.")

func _card(index: int) -> Rect2:
	return Rect2(1090, 212 + index * 82, 316, 73)

func _text(canvas: Node2D, p: Vector2, value: String, size: int = 16, color: Color = TEXT) -> void:
	canvas.draw_string(font, p, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _box(canvas: Node2D, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, corner: int = 12) -> void:
	var style := StyleBoxFlat.new()
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
	_stat(468, "MEMBRANE", "%03d%%" % int(world.health), world.health / 100.0, MINT if world.health > 35 else CORAL)
	_stat(656, "ENERGY / ATP", "%03d" % int(world.energy), world.energy / 100.0, GOLD)
	_stat(844, "BIOMASS", "%02d" % int(world.biomass), minf(world.biomass / 50, 1), PURPLE)
	_box(self, Rect2(1124, 40, 128, 37), PANEL, LINE, 9)
	_text(self, Vector2(1143, 64), "RESUME" if paused else "PAUSE  II", 13)
	_box(self, Rect2(1264, 40, 142, 37), PANEL, LINE, 9)
	_text(self, Vector2(1284, 64), "NEW LIFE  ↻", 13)
	draw_line(Vector2(32, 119), Vector2(1406, 119), LINE, 1)
	_text(self, Vector2(32, 143), "01  /  THE SHALLOWS", 12, MUTED)
	_text(self, Vector2(850, 143), "%02d:%02d  ALIVE" % [int(world.time + 0.001) / 60, int(world.time + 0.001) % 60], 12, MINT)
	_box(self, ARENA, Color("102d39"), LINE, 18)
	_draw_habitat()
	_text(self, Vector2(56, 185), "NUTRIENT-RICH TIDAL POOL", 10, Color("688d94"))
	_draw_legend()
	_text(self, Vector2(1090, 160), "BUILD YOUR CELL", 19)
	_text(self, Vector2(1090, 184), "Choose an organelle. Place it in a socket.", 13, MUTED)
	for i in 6:
		var rect := _card(i)
		var hover := rect.has_point(get_global_mouse_position())
		var active := selected == i
		_box(self, rect, Color("1b3945") if active or hover else PANEL, ACCENTS[i] if active else LINE, 11)
		_box(self, Rect2(rect.position + Vector2(12, 14), Vector2(44, 44)), Color("193541"), Color.TRANSPARENT, 10)
		_icon(self, rect.position + Vector2(34, 36), Simulation.KINDS[i], 0, 0.77)
		_text(self, rect.position + Vector2(68, 27), TITLES[i], 16)
		_text(self, rect.position + Vector2(68, 49), DESCRIPTIONS[i], 10, MUTED)
		_text(self, rect.position + Vector2(268, 27), "%d" % Simulation.COST[i], 15, ACCENTS[i] if world.biomass >= Simulation.COST[i] else MUTED)
		_text(self, rect.position + Vector2(294, 62), str(i + 1), 10, MUTED)
	_box(self, Rect2(1090, 721, 316, 115), Color("162f3a"), LINE)
	_text(self, Vector2(1107, 747), "YOUR FIRST ADAPTATION", 11, MINT)
	_text(self, Vector2(1107, 773), "Metabolize 40 nutrients. Live 90 seconds.", 12)
	var progress: float = minf(1, minf(world.processed / 40, world.time / 90))
	_box(self, Rect2(1107, 787, 280, 5), LINE, Color.TRANSPARENT, 2)
	if progress > 0:
		_box(self, Rect2(1107, 787, 280 * progress, 5), MINT, Color.TRANSPARENT, 2)
	_text(self, Vector2(1107, 817), "ADAPTED · keep exploring" if world.won else "%d / 40 processed     ·     %d / 90 sec" % [int(world.processed), int(world.time + 0.001)], 12, MINT if world.won else MUTED)
	_text(self, Vector2(32, 818), "METABOLISM", 11, MINT)
	_text(self, Vector2(32, 843), "Nutrient + oxygen  →  ATP + biomass + waste", 16)
	_text(self, Vector2(500, 818), "SUBSTRATE  %.1f" % world.substrate, 12, PALETTE[0])
	_text(self, Vector2(666, 818), "OXYGEN  %.1f" % world.oxygen, 12, PALETTE[1])
	_box(self, Rect2(879, 804, 168, 32), PANEL, MINT if show_senses else LINE, 8)
	_text(self, Vector2(898, 825), "SENSE VIEW  [S]", 12, MINT if show_senses else MUTED)
	draw_line(Vector2(32, 858), Vector2(1406, 858), LINE)
	_text(self, Vector2(32, 884), "NO STEERING. JUST ADAPTATION.", 11, MINT)
	_text(self, Vector2(363, 884), "1–6 select   ·   click socket to attach   ·   right-click to recycle   ·   Space pause   ·   R restart", 12, MUTED)
	_text(self, Vector2(1270, 884), "FIRST CELL / 0.1", 11, MUTED)

func _stat(x: float, label: String, value: String, fraction: float, color: Color) -> void:
	_text(self, Vector2(x, 44), label, 10, MUTED)
	_text(self, Vector2(x, 79), value, 28, color)
	_box(self, Rect2(x, 92, 150, 4), LINE, Color.TRANSPARENT, 2)
	if fraction > 0:
		_box(self, Rect2(x, 92, 150 * fraction, 4), color, Color.TRANSPARENT, 2)

func _draw_habitat() -> void:
	# Authored background shapes are decorative; small colored specks are simulated.
	var patches := [Vector3(143, 340, 74), Vector3(910, 112, 84), Vector3(587, 528, 61), Vector3(125, 106, 50)]
	for patch in patches:
		var center := ORIGIN + Vector2(patch.x, patch.y)
		for j in 5:
			var offset: Vector2 = Vector2.from_angle(j * 2.1) * patch.z * 0.36
			draw_circle(center + offset, patch.z * 0.58, Color("153745"))
			for k in 3:
				draw_arc(center + offset, patch.z * (0.2 + k * 0.10), 0, TAU, 40, Color("1b404b"), 1.0, true)
	for x in range(62, 1030, 38):
		for y in range(210, 754, 38):
			draw_circle(Vector2(x, y), 0.7, Color("234552"))
	# Water contour lines anchor the composition without implying collisions.
	for i in 3:
		var points := PackedVector2Array()
		for j in 60:
			points.append(ORIGIN + Vector2(22 + j * 16.4, 557 + sin(j * 0.095 + i * 0.3) * 18 + i * 13))
		draw_polyline(points, Color(0.2, 0.4, 0.45, 0.12), 1.0, true)

func _draw_legend() -> void:
	var x := 59.0
	for i in 3:
		var names := ["NUTRIENTS", "OXYGEN", "PREDATOR TRACE"]
		var colors := [PALETTE[0], PALETTE[1], CORAL]
		draw_circle(Vector2(x, 759), 3.5, colors[i])
		_text(self, Vector2(x + 12, 763), names[i], 10, MUTED)
		x += [131.0, 108.0, 170.0][i]

func _draw_organisms() -> void:
	var c := actors
	var p: Vector2 = ORIGIN + world.position
	if show_senses:
		for slot in 8:
			if world.organs[slot] == "sensing":
				var center: Vector2 = ORIGIN + world.slot_position(slot)
				for i in 48:
					c.draw_arc(center, 185, i * TAU / 48, (i + 0.45) * TAU / 48, 3, Color(0.7, 0.64, 0.95, 0.26), 1, true)
				c.draw_line(center, center + world.target_vector * 90, PURPLE, 1, true)
	_draw_predator(c)
	var outline: PackedVector2Array = world.membrane.outline()
	var poly := PackedVector2Array()
	var inner := PackedVector2Array()
	var shadow := PackedVector2Array()
	for v in outline:
		var rotated: Vector2 = v.rotated(world.angle)
		poly.append(p + rotated)
		inner.append(p + rotated * 0.87)
		shadow.append(p + rotated * 1.07 + Vector2(0, 7))
	c.draw_colored_polygon(shadow, Color(0.01, 0.07, 0.12, 0.40))
	c.draw_colored_polygon(poly, Color("8de8c7").lerp(CORAL, world.hurt_flash * 0.7))
	c.draw_colored_polygon(inner, Color("44ab9f"))
	var closed := poly.duplicate()
	closed.append(poly[0])
	c.draw_polyline(closed, Color("b2ffe0"), 2, true)
	c.draw_circle(p + Vector2(-9, -6).rotated(world.angle), world.radius * 0.38, Color("338985"))
	c.draw_circle(p + Vector2(-7, -9).rotated(world.angle), world.radius * 0.28, Color("a99bde"))
	c.draw_circle(p + Vector2(-5, -11).rotated(world.angle), world.radius * 0.18, Color("d7b3e9"))
	for i in 7:
		var r: float = world.radius * (0.43 + 0.13 * sin(i * 7.0))
		var q: Vector2 = p + Vector2.from_angle(i * 2.3 + world.angle) * r
		c.draw_circle(q, 3.5 + i % 2, Color("92d6af"))
		c.draw_circle(q + Vector2(1, -1), 1.2, Color("cef1b8"))
	for slot in 8:
		if world.organs[slot] != "":
			var q: Vector2 = ORIGIN + world.slot_position(slot)
			_icon(c, q, world.organs[slot], world.angle + TAU * slot / 8.0, 1.0)
	if world.reaction_flash > 0:
		c.draw_arc(p, world.radius + 16 + (1 - world.reaction_flash) * 16, -0.4, 0.6, 30, Color(0.7, 1, 0.55, world.reaction_flash), 2, true)
	var label := "YOUR CELL"
	var label_p := p + Vector2(-39, -world.radius - 54)
	_text(c, label_p, label, 11, MINT)
	c.draw_line(label_p + Vector2(39, 7), p + Vector2(0, -world.radius - 14), Color(0.5, 0.9, 0.8, 0.5), 1)
	if selected >= 0:
		for slot in 8:
			var q: Vector2 = ORIGIN + world.slot_position(slot)
			if world.organs[slot] == "":
				c.draw_circle(q, 15, Color("143f48"))
				c.draw_arc(q, 15 + sin(ui_time * 4) * 1.5, 0, TAU, 40, MINT, 2, true)
				c.draw_line(q - Vector2(5, 0), q + Vector2(5, 0), MINT, 1.5)
				c.draw_line(q - Vector2(0, 5), q + Vector2(0, 5), MINT, 1.5)

func _draw_predator(c: Node2D) -> void:
	var p: Vector2 = ORIGIN + world.predator
	var heading: float = (world.position - world.predator).angle()
	var poly := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 72:
		var a := TAU * i / 72.0
		var r: float = world.predator_radius * (1.0 + sin(a * 7 + world.time) * 0.05)
		poly.append(p + Vector2.from_angle(a) * r)
		inner.append(p + Vector2.from_angle(a) * r * 0.85)
	c.draw_circle(p + Vector2(0, 7), world.predator_radius + 3, Color(0.07, 0.08, 0.14, 0.4))
	c.draw_colored_polygon(poly, Color("ff9995"))
	c.draw_colored_polygon(inner, Color("c96379") if world.predator_stun <= 0 else Color("a989b6"))
	for i in 8:
		var a := TAU * i / 8.0 + world.time * 0.05
		var q := p + Vector2.from_angle(a) * world.predator_radius
		var spike := PackedVector2Array([q + Vector2.from_angle(a + 1.6) * 7, q + Vector2.from_angle(a) * 13, q + Vector2.from_angle(a - 1.6) * 7])
		c.draw_colored_polygon(spike, Color("ffc5a3"))
	c.draw_circle(p + Vector2(-8, 4), 23, Color("98475f"))
	c.draw_circle(p + Vector2(-12, 0), 14, Color("f190a4"))
	for i in 4:
		c.draw_circle(p + Vector2.from_angle(i * 2.5) * 32, 5, Color("ed9f9a"))
	var mouth := p + Vector2.from_angle(heading) * 45
	c.draw_circle(mouth, 15, Color("703a53"))
	for i in 3:
		var q := mouth + Vector2.from_angle(heading + PI * 0.7 + i * 0.65) * 10
		c.draw_circle(q, 3.8, Color("ffdfb9"))
	_text(c, p + Vector2(-29, -83), "HUNTER" if world.predator_stun <= 0 else "REPELLED", 10, CORAL)

func _icon(c: Node2D, p: Vector2, kind: String, rotation: float, scale: float) -> void:
	var forward := Vector2.from_angle(rotation)
	var side := forward.orthogonal()
	match kind:
		"propulsion":
			var path := PackedVector2Array()
			for i in 22:
				var t := i / 21.0
				path.append(p + forward * (t * 43 * scale) + side * sin(t * 7 - ui_time * 9) * t * 10 * scale)
			c.draw_polyline(path, MINT, 4 * scale, true)
			c.draw_circle(p, 8 * scale, Color("cee8a5"))
			c.draw_circle(p, 4 * scale, Color("418e8d"))
		"protection":
			var polygon := PackedVector2Array()
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
	var status: String = world.state
	if selected >= 0: status = "ASSEMBLY PAUSED · CHOOSE A SOCKET"
	elif paused: status = "OBSERVATION PAUSED"
	_box(overlay, Rect2(ARENA.position + Vector2(16, 45), Vector2(360, 32)), Color(0.04, 0.12, 0.17, 0.87), LINE, 8)
	overlay.draw_circle(ARENA.position + Vector2(30, 61), 3, MINT)
	_text(overlay, ARENA.position + Vector2(43, 65), status, 11, MINT)
	if notice_timer > 0:
		_box(overlay, Rect2(ARENA.position + Vector2(164, 565), Vector2(690, 35)), Color(0.03, 0.1, 0.16, 0.94), LINE, 8)
		_text(overlay, ARENA.position + Vector2(180, 588), notice, 13)
	if world.health <= 0:
		_box(overlay, Rect2(305, 357, 470, 174), Color("142b3b"), CORAL, 16)
		_text(overlay, Vector2(337, 402), "A small life, ended.", 28, CORAL)
		_text(overlay, Vector2(337, 438), "Survived %d seconds · absorbed %d nutrients" % [world.time, world.eaten], 15)
		_text(overlay, Vector2(337, 469), "Try a different anatomy. Every organelle matters.", 14, MUTED)
		_text(overlay, Vector2(337, 504), "Press R or choose NEW LIFE to begin again.", 14, MINT)
