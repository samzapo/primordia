extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
var host
var scene
const DT := 1.0/60

func expect(ok: bool, message: String) -> void: host.expect(ok,message)
func key(code: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	scene._input(event)
func click(at: Vector2, button: int = MOUSE_BUTTON_LEFT, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = button
	event.pressed = pressed
	scene._unhandled_input(event)
func at(local: Vector2) -> Vector2:
	var view = scene.views[scene.world.player.id]
	return scene.world_layer.to_global(view.position+local.rotated(view.rotation))
func settle() -> void:
	for i in 45: scene._process(DT)
	scene.focus_animating = false
	scene._update_world(1)

func run(test_host) -> void:
	host = test_host
	scene = load("res://scenes/pond.tscn").instantiate()
	host.root.add_child(scene)
	scene.set_physics_process(false)
	scene.set_process(false)
	await host.process_frame
	# Preserve redraw throttling coverage from the previous presentation suite.
	var npc = scene.world.cells[1]
	var npc_view = scene.views[npc.id]
	var revision: int = scene.world.revision
	var draw_revision: int = npc.render_revision
	scene.world.revision = 1
	npc.render_revision += 1
	npc_view.sync(Vector2.ZERO,0,0.01,1)
	scene.world.revision += 8
	npc.render_revision += 8
	npc_view.sync(Vector2.ZERO,0,0.01,1)
	expect(npc_view.seen_revision == npc.render_revision,"Small-cell drawings survive multiple catch-up ticks")
	scene.world.revision = revision
	npc.render_revision = draw_revision
	scene._update_world(1)
	# The only permanent pane is settings, which starts hidden.
	var panes := 0
	for node in scene.ui.get_children():
		if node is PanelContainer: panes += 1
	expect(panes == 1 and not scene.settings_panel.visible,"No top, bottom or assembly panes remain")
	expect(scene.batches.size() == Sim.SPECIES_COUNT,"Renderer retains all chemistry species")
	key(KEY_ESCAPE)
	var identity = scene.world.player
	key(KEY_TAB)
	expect(scene.settings_panel.visible and not scene.build_open and scene.world.player == identity,"Settings pauses and prevents edits behind the modal")
	expect(scene.quit_button.pressed.get_connections().size() == 1,"Settings retains Quit")
	scene.bloom_check.toggled.emit(false)
	expect(scene.microscope_layer.visible and not scene.preferences.bloom,"Turning off bloom preserves the shared blur/lens pass")
	scene.bloom_check.toggled.emit(true)
	key(KEY_ESCAPE)
	key(KEY_SPACE)
	expect(not scene.camera_locked and not scene.is_paused(),"Space unlocks view without pausing")
	key(KEY_SPACE)
	var rotation: float = scene.world_layer.rotation
	scene.world.player.angle += 1
	scene._update_world(1)
	expect(scene.world_layer.rotation == rotation,"Follow view never rotates with the organism")
	# Camera focus, fixed-size construction and no reversible purchase control.
	scene.manual_zoom = 0.8
	scene._update_world(1)
	key(KEY_TAB)
	settle()
	var cell = scene.world.player
	var clock: float = scene.world.time
	scene._physics_process(DT)
	expect(scene.build_open and scene.world.time == clock and scene.manual_zoom > 0.8,"Tab pauses biology and focuses inside the cell")
	click(scene.cell_ui.screen_at({"kind":"assembly"}))
	expect(scene.cell_ui.choices.size() == 6,"Clicking the assembly factory reveals six local illustrated choices")
	scene.cell_ui.choices[1].pressed.emit()
	expect(scene.selected == 1 and scene.cell_ui.choices.is_empty(),"Factory choice picks a cortex without a build panel")
	var before_zoom: float = scene.manual_zoom
	var cursor := Vector2(80,180)
	var world_before: Vector2 = scene.render_camera+(cursor-scene.camera_screen)/scene.zoom
	click(cursor,MOUSE_BUTTON_WHEEL_UP)
	var world_after: Vector2 = scene.render_camera+(cursor-scene.camera_screen)/scene.zoom
	expect(scene.manual_zoom > before_zoom and Sim.Medium.offset(world_before,world_after).length() < 0.001,"Wheel during placement zooms around the cursor")
	click(at(cell.local_point(2.15)))
	expect(cell.count("protection") == 1 and cell.organs[-1].scale == 1,"New organs have a fixed standard size")
	var organ_id: int = cell.organs[-1].id
	scene._update_world(1)
	var seen: int = scene.views[cell.id].seen_revision
	click(at(cell.local_point(2.15)),MOUSE_BUTTON_RIGHT)
	expect(scene.selected == -1 and not cell.organ_by_id(organ_id).is_empty(),"Right-click cancels the held ghost without recycling installed anatomy")
	scene.cell_ui.open_context({"kind":"organ","id":organ_id})
	expect(scene.cell_ui.choices.size() == 2 and scene.cell_ui.choices[0].caption == "Move" and scene.cell_ui.choices[1].caption == "Recycle","An unmodified organ exposes Move and Recycle, with no resize or Undo")
	var points: int = scene.world.evolution.points
	scene.cell_ui.choices[1].pressed.emit()
	scene._update_world(1)
	expect(cell.count("protection") == 0 and scene.views[cell.id].seen_revision > seen,"Recycling refreshes the paused drawing before resuming")
	expect(scene.world.evolution.points == points,"Recycling does not refund AP")
	var geometry: PackedVector2Array = cell.membrane.points.duplicate()
	var age: float = cell.age
	var energy: float = cell.energy
	scene._process(DT)
	expect(cell.membrane.points != geometry and cell.age == age and cell.energy == energy and scene.world.time == clock,"Paused geometry responds without biological progress")
	key(KEY_ESCAPE)
	expect(scene.settings_panel.visible and scene.build_open and scene.world.player == cell,"Settings preserves current paid edits")
	key(KEY_ESCAPE)
	expect(scene.build_open and scene.world.evolution.points == points,"Closing settings returns to the same paused cell")
	key(KEY_TAB)
	expect(not scene.build_open and scene.world.build_original == null and scene.world.evolution.points == points,"Tab keeps edits without an Apply or Undo button")
	settle()
	expect(is_equal_approx(scene.manual_zoom,0.8),"Leaving edit restores the observation magnification")
	# Factory, nucleus, bud and keyboard access retain the run's decision economy.
	key(KEY_TAB)
	settle()
	cell = scene.world.player
	scene.cell_ui.open_context({"kind":"chemistry"})
	expect(scene.cell_ui.choices.size() == 4,"Chemistry factory exposes exactly the existing four organs")
	scene.cell_ui.close_context()
	key(KEY_BRACKETRIGHT)
	key(KEY_ENTER)
	expect(scene.cell_ui.context.kind == "assembly" and scene.cell_ui.choices[0].has_focus(),"Keyboard cycles to cell targets and opens a focused choice")
	key(KEY_ENTER)
	expect(scene.selected == 0,"Enter activates the focused factory choice")
	click(Vector2.ZERO,MOUSE_BUTTON_RIGHT)
	scene.cell_ui.open_context({"kind":"nucleus"})
	var offered: String = scene.world.evolution.offers[0]
	scene.cell_ui.choices[0].pressed.emit()
	expect(scene.world.evolution.chosen and offered in scene.world.evolution.learned,"Nucleus keeps a blueprint using the existing run rules")
	scene.cell_ui.open_context({"kind":"bud"})
	var reserved: float = cell.brood_mass
	var reserved_atp: float = cell.brood_energy
	scene.cell_ui.choices[0].pressed.emit()
	expect(cell.brood_mass > reserved and cell.brood_energy > reserved_atp,"Offspring bud funds existing tissue and energy reserves")
	scene.cell_ui.choices[1].pressed.emit()
	expect(cell.brood_mass == reserved and cell.brood_energy == reserved_atp,"Offspring reserves can still be reclaimed")
	scene.world.evolution.offspring_id = cell.id
	scene.cell_ui.open_context({"kind":"bud"})
	expect(scene.cell_ui.choices.size() >= 4 and "viability" in scene.cell_ui.describe({"kind":"bud"}),"The bud retains reproduction choices and reports independent viability after division")
	scene.world.evolution.offspring_id = -1
	scene.cell_ui.close_context()
	cell.energy = 0
	scene.cell_ui.interior.sync()
	expect(scene.cell_ui.interior.atp_fraction == 0,"An empty ATP resource renders an empty sac")
	cell.energy = cell.energy_capacity()
	scene.world.evolution.points = 7
	scene.cell_ui.interior.sync()
	expect(scene.cell_ui.interior.atp_fraction == 1 and scene.cell_ui.interior.coin_count == 7,"Full ATP and one coin per AP reflect real resources")
	# Internal controls must not be mistaken for microtubule endpoints.
	var groups: int = cell.membrane.skeleton.next_group
	click(scene.cell_ui.screen_at({"kind":"assembly"}))
	expect(scene.tube_start.is_empty() and cell.membrane.skeleton.next_group == groups,"Factory clicks take priority over underlying tension links")
	scene.cell_ui.close_context()
	scene.cell_ui.keyboard_target.clear()
	var ends: Array[Vector2] = []
	for angle in [0.7,1.4,2.5,3.1,4.1,5.0,5.8]:
		var point := at(cell.local_point(angle))
		if scene.cell_ui.hit(point).is_empty(): ends.append(point)
	expect(ends.size() >= 2,"There are unoccupied membrane endpoints for direct editing")
	click(ends[0])
	click(ends[1],MOUSE_BUTTON_LEFT,false)
	expect(cell.membrane.skeleton.next_group == groups+1,"Dragging bare membrane endpoints still places microtubules")
	var link: Dictionary = cell.membrane.skeleton.links[-1]
	var hover := Vector2.ZERO
	for fraction in [0.1,0.2,0.7,0.85]:
		var point: Vector2 = cell.membrane.skeleton.point(link.a,cell.membrane).lerp(cell.membrane.skeleton.point(link.b,cell.membrane),fraction)
		if scene.cell_ui.hit(at(point)).is_empty(): hover = at(point); break
	var tension: float = link.tension
	click(hover,MOUSE_BUTTON_WHEEL_UP)
	expect(link.tension > tension,"Wheel over an unobstructed microtubule still changes tension")
	click(ends[0])
	key(KEY_TAB)
	expect(scene.tube_start.is_empty(),"Resuming cancels an unfinished microtubule drag")
	settle()
	groups = scene.world.player.membrane.skeleton.next_group
	click(at(scene.world.player.local_point(0.7)))
	click(at(scene.world.player.local_point(2.5)),MOUSE_BUTTON_LEFT,false)
	expect(scene.world.player.membrane.skeleton.next_group == groups,"Microtubule editing remains unavailable during play")
	# Camera limits, large cells and readable physical calibration.
	scene.cell_ui.close_context()
	scene.selected = -1
	scene.manual_zoom = 0.01
	scene.focus_animating = false
	scene.world.player.radius = 600
	scene._update_world(1)
	var fitted: float = minf(scene.get_viewport_rect().size.x/Sim.VIEW.x,scene.get_viewport_rect().size.y/Sim.VIEW.y)
	expect(is_equal_approx(scene.zoom,0.8*fitted),"Giant cells cannot widen the camera past 80%")
	scene.manual_zoom = 99
	scene._update_world(1)
	expect(is_equal_approx(scene.zoom,12*fitted),"Large cells can still be inspected at 12×")
	scene.show_debug = true
	scene._update_hud()
	expect("FPS" in scene.debug_label.text and not "Zoom" in scene.debug_label.text,"Optional diagnostics retain FPS without a zoom readout")
	scene._apply_ui_scale(1.75)
	expect(scene.ui.theme.default_font_size == 35,"Text sizing still affects actual UI fonts")
	scene.set_fullscreen(true)
	key(KEY_F11)
	expect(not scene.preferences.fullscreen,"F11 still toggles fullscreen")
	for factor in [0.8,3.0,12.0]:
		scene.scale_bar.configure(Vector2(1440,900),fitted*factor,1.75)
		expect(is_equal_approx(scene.scale_bar.length_pixels/(fitted*factor)*0.2,scene.scale_bar.micrometers),"Physical scale stays calibrated through close editing and accessibility scaling")
	await _lineage()
	await _particles()
	scene.queue_free()
	await host.process_frame

func _particles() -> void:
	scene.world = Sim.new(41)
	var sim = scene.world
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.grid.clear()
	scene.build_open = false
	scene.cell_ui.close_context()
	scene.selected = -1
	scene.moving_id = -1
	scene.manual_zoom = 0.8
	scene.camera_locked = true
	scene.camera_offset = Vector2.ZERO
	scene.focus_animating = false
	for kind in Sim.SPECIES_COUNT:
		sim.spawn_particle(kind,sim.player.position+Vector2(170+kind*22,150),Vector2.ZERO,0.3)
		var p: Dictionary = sim.particles[-1]
		p.previous_angle = 0
		p.angle = PI/2
		p.updated = sim.revision
	scene._update_world(0.5)
	var original: Array = sim.particles.duplicate(true)
	for kind in Sim.SPECIES_COUNT:
		var p: Dictionary = sim.particles[kind]
		var screen: Vector2 = scene.camera_screen+Sim.Medium.offset(scene.render_camera,p.p)*scene.zoom
		var data: PackedFloat32Array = scene.buffers[kind]
		expect(Vector2(data[0],data[4]).normalized().distance_to(Vector2.from_angle(PI/4)) < 0.0001,"Batched artwork retains the interpolated chemical binding orientation")
		var picked: Dictionary = scene.inspector.pick(screen,0.5)
		expect(not picked.is_empty() and picked.kind == kind and is_equal_approx(picked.angle,PI/4),"Particle hover identifies the displayed species and interpolated orientation")
		scene.inspector.update_lens(0,screen,0.5,false)
		scene.inspector.update_lens(0.2,screen,0.5,true)
		expect(scene.inspector.label.text.begins_with(scene.ParticleArt.NAMES[kind]) and scene.inspector.lens_amount == 1,"Hover activates a local lens and names every chemical species")
	expect(sim.particles == original,"Inspection cannot change particle mass, motion, orientation or chemistry")
	_track_particle()
	expect(sim.particles == original,"Tracking and inspection preserve the simulation state")
	scene.diagnostic_zoom = true
	scene.manual_zoom = 0.15
	scene._update_world(1)
	for kind in Sim.SPECIES_COUNT:
		var data: PackedFloat32Array = scene.buffers[kind]
		expect(Vector2(data[0],data[4]).normalized().distance_to(Vector2.DOWN) < 0.0001,"Historical wide-view glyph LOD preserves orientation")
	expect(sim.particles == original,"Artwork LOD leaves particle state unchanged")
	var style: Dictionary = scene.views[sim.player.id].art.duplicate(true)
	sim.player.role = "hunter"
	sim.player.render_revision += 1
	scene._update_world(1)
	expect(scene.views[sim.player.id].art == style,"Body artwork remains independent of occupation")
	scene.diagnostic_zoom = false
	scene.manual_zoom = 0.8
	scene._update_world(1)
	scene.inspector.update_lens(0.2,Vector2(20,20),0.5,true)
	expect(scene.inspector.hovered.is_empty() and scene.inspector.lens_amount == 0 and not scene.inspector.box.visible,"Moving off particles dismisses their magnifier and tooltip")
	sim.spawn_particle(Sim.TOXIN,sim.player.position)
	expect(scene.inspector.pick(scene.camera_screen,1).is_empty(),"Covered particles cannot be picked through a cell body")
	var tracer: Dictionary = sim._emit_pheromone(sim.player)
	tracer.p = sim.player.position
	tracer.previous = tracer.p
	sim.grid.rebuild(sim.particles)
	tracer.expires_at = sim.time+10
	scene._update_world(1)
	for native in [false,true] if sim.kernels != null else [false]:
		sim.native_render = native
		scene._sync_particles(1)
		var buffer: PackedFloat32Array = scene.buffers[Sim.PHEROMONE]
		var found := false
		for i in scene.batches[Sim.PHEROMONE].multimesh.visible_instance_count:
			if Vector2(buffer[i*12+3],buffer[i*12+7]).length() < 0.01: found = true
		expect(found,"Pheromone artwork stays at its true location inside the cell in both rendering paths")
	var through_cell: Dictionary = scene.inspector.pick(scene.camera_screen,1)
	expect(not through_cell.is_empty() and through_cell.kind == Sim.PHEROMONE,"Pheromones remain inspectable through cell interiors")
	scene.inspector.update_lens(0.2,scene.camera_screen,1,true)
	expect(scene.inspector.label.text.contains("Reported size:") and scene.inspector.label.text.contains("unarmed"),"The local tooltip describes the emitted metadata")
	var prior_text: String = scene.inspector.label.text
	tracer.report.hostile = true
	scene.inspector.update_lens(0.2,scene.camera_screen,1,true)
	expect(scene.inspector.label.text != prior_text and scene.inspector.label.text.contains("armed"),"Inspection reads the packet rather than the live unarmed cell")
	expect(scene.batches[Sim.PHEROMONE].z_index > scene.batches[Sim.NUTRIENT].z_index,"Point tracers are drawn above physical cells")
	scene.camera_locked = false
	scene.free_camera = Vector2(4090,1000)
	sim.player.position = Vector2(2000,1200)
	sim.player.previous_position = sim.player.position
	sim.particles.clear()
	sim.grid.clear()
	sim.spawn_particle(Sim.ENZYME,Vector2(2,1000))
	var p: Dictionary = sim.particles[-1]
	p.previous = Vector2(4094,1000)
	p.updated = sim.revision
	for i in 400: sim.spawn_particle(Sim.NUTRIENT,Vector2(1700+i%50,1700))
	scene._update_world(0.5)
	expect(not scene.cell_ui.interior.visible and scene.cell_ui.hit(scene.camera_screen).is_empty(),"Panning away from the player hides its resource artwork and click targets")
	var screen: Vector2 = scene.camera_screen+Vector2(6,0)*scene.zoom
	var picked: Dictionary = scene.inspector.pick(screen,0.5)
	expect(not picked.is_empty() and picked.kind == Sim.ENZYME,"Picking follows wrapped interpolation at the invisible world seam")
	expect(scene.inspector.candidates_examined < 20,"Particle inspection queries local buckets rather than scanning the ecosystem")
	scene.inspector.update_lens(0,screen,0.5,false)
	scene.inspector.update_lens(0.2,screen,0.5,true)
	p.previous = p.p
	p.p = Vector2(26,1000)
	scene.inspector.update_lens(0.1,screen,1,true)
	expect(is_same(scene.inspector.hovered.packet,p) and scene.inspector.lens_center.distance_to(scene.camera_screen+Vector2(32,0)*scene.zoom) < 0.001,"Tracking follows wrapped motion with the actual free camera")
	p.p = Vector2(1700,1700)
	p.previous = p.p
	scene.inspector.update_lens(0.1,screen,1,true)
	expect(scene.inspector.hovered.is_empty(),"A tracked particle leaving the visible rectangle releases the lens")
	p.p = Vector2(2,1000)
	p.previous = Vector2(4094,1000)
	sim.grid.rebuild(sim.particles)
	scene.inspector.update_lens(0.2,screen,0.5,true)
	p.kind = Sim.PHEROMONE
	p.expires_at = sim.time
	scene.inspector.update_lens(0.1,screen,0.5,true)
	expect(scene.inspector.hovered.is_empty(),"Expired pheromones dismiss tracking even before array cleanup")
	p.kind = Sim.ENZYME
	scene.inspector.update_lens(0.2,screen,0.5,true)
	scene.world = Sim.new(123)
	scene.inspector.update_lens(0.1,Vector2(20,20),1,true)
	expect(scene.inspector.hovered.is_empty() and scene.inspector.tracked_packet.is_empty(),"Restarting clears the old world's tracked packet")
	scene.world = sim

	scene.inspector.update_lens(0.2,screen,0.5,false)
	expect(scene.inspector.lens_amount == 0,"Modal UI disables the lens immediately")

func _track_particle() -> void:
	var sim = scene.world
	var inspector = scene.inspector
	var target: Dictionary = sim.particles[2]
	var original: Dictionary = target.duplicate(true)
	var cursor: Vector2 = scene.camera_screen+Sim.Medium.offset(scene.render_camera,target.p)*scene.zoom
	inspector.update_lens(0,cursor,1,false)
	inspector.update_lens(0.05,cursor,1,true)
	target.p = Sim.Medium.wrap_position(target.p+Vector2(30,0))
	target.previous = target.p
	var rival: Dictionary = sim.particles[1]
	var rival_original: Dictionary = rival.duplicate(true)
	rival.p = original.p
	rival.previous = rival.p
	sim.grid.rebuild(sim.particles)
	inspector.update_lens(0.2,cursor,1,true)
	expect(is_same(inspector.hovered.packet,target),"A nearby rival cannot steal a briefly tracked particle")
	expect(inspector.lens_center.distance_to(cursor+Vector2(30,0)*scene.zoom) < 0.001 and inspector.lens_amount == 1,"Lens follows the drifting particle without flickering off")
	# Actual compaction changes indices without changing the tracked dictionary.
	var removed: Dictionary = sim.particles.pop_front()
	sim.grid.rebuild(sim.particles)
	inspector.update_lens(0.1,cursor+Vector2(2,0),1,true)
	expect(inspector.hovered.index == 1 and is_same(inspector.hovered.packet,target),"Tracking survives compaction and small hand jitter")
	target.kind = Sim.NUTRIENT
	inspector.update_lens(0.1,cursor,1,true)
	expect(inspector.label.text.begins_with("Nutrient"),"A tracked packet displays its new chemical identity after reaction")
	rival.alive = false
	inspector.update_lens(1,cursor,1,true)
	expect(inspector.hovered.is_empty(),"Tracking expires after its short grace period when the cursor no longer covers the particle")
	var now: Vector2 = scene.camera_screen+Sim.Medium.offset(scene.render_camera,target.p)*scene.zoom
	inspector.update_lens(0.2,now,1,true)
	inspector.update_lens(0.2,now+Vector2(80,80),1,true)
	expect(inspector.hovered.is_empty(),"Deliberately moving the pointer releases tracking immediately")
	inspector.update_lens(0.2,now,1,true)
	target.alive = false
	inspector.update_lens(0.02,now,1,true)
	expect(inspector.hovered.is_empty(),"Consumed or decayed particles cannot leave a ghost magnifier")
	target.clear()
	target.merge(original)
	rival.clear()
	rival.merge(rival_original)
	sim.particles.push_front(removed)
	sim.grid.rebuild(sim.particles)
	inspector.update_lens(0,cursor,1,false)

func _lineage() -> void:
	# Exercise the real UI transitions: no hidden build clone may swallow a birth.
	scene.world = Sim.new(821)
	var sim = scene.world
	sim.habitat_geometry.enabled = false
	sim.pending_replacements.clear()
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.grid.clear()
	scene.build_open = false
	scene.settings_panel.hide()
	scene.cell_ui.reset()
	scene.show_debug = false
	scene.camera_locked = true
	scene.camera_offset = Vector2.ZERO
	scene.manual_zoom = 0.8
	scene._update_world(1)
	key(KEY_TAB)
	settle()
	var parent = sim.player
	var quote: Dictionary = sim.offspring_quote()
	parent.biomass += quote.material+50 # Explicit fixture endowment; actions still pay.
	parent.energy = 100
	parent.reserve(maxf(60,quote.material),quote.material)
	var mass: float = parent.organic_mass()
	var points: int = sim.evolution.points
	scene.cell_ui.open_context({"kind":"bud"})
	parent.brood_energy = 50
	scene.cell_ui.sync(0)
	expect(not scene.cell_ui.choices[2].affordable,"The bud marks an unfunded successor")
	parent.brood_energy = 60
	scene.cell_ui.sync(0)
	expect(scene.cell_ui.choices[2].affordable,"Funding refreshes readiness while the bud choices remain open")
	scene.cell_ui.choices[2].pressed.emit()
	scene._update_world(1)
	expect(sim.lineage.births == 1 and sim.cells.size() == 2 and sim.player.id == parent.id,"Release from the bud creates a real autonomous family member")
	expect(scene.build_open and sim.build_original != null and sim.player.organic_mass() < mass and sim.evolution.points == points,"Birth commits paid anatomy and resumes editing the depleted parent")
	var child = sim.cells[-1]
	expect(scene.views.has(child.id) and scene.views[sim.player.id].cell == sim.player,"Parent and offspring drawings update immediately during editing")
	scene.cell_ui.open_context({"kind":"bud"})
	scene.cell_ui.choices[-1].pressed.emit()
	expect(sim.player.id == child.id and scene.camera_locked and sim.build_original != null,"Following a released successor attaches the camera and correct build clone")
	key(KEY_TAB)
	settle()
	expect(sim.build_original == null and not scene.is_paused(),"Resuming after handoff cannot leave the world trapped in a hidden build")
	# Family history is also available without entering edit mode.
	scene.cell_ui.open_context({"kind":"lineage"})
	for choice in scene.cell_ui.choices:
		if choice.get_meta("family_id",-1) == parent.id: choice.pressed.emit(); break
	expect(sim.player.id == parent.id and not scene.build_open and sim.build_original == null and not scene.is_paused(),"A family-tree handoff outside edit mode preserves active simulation")
	expect(sim.lineage.record_for(child.id).state == "living" and sim.lineage.record_for(parent.id).state == "active","Family cards distinguish the current body from living relatives")
	var identity: int = sim.player.id
	var time: float = sim.time
	var learned: Array = sim.evolution.learned.duplicate()
	scene.music.frame_cursor = 137123
	var score_clock: int = scene.music.frame_cursor
	sim.player.health = 0
	scene._physics_process(DT)
	scene._process(DT)
	expect(scene.world == sim and sim.player.id != identity and sim.time > time and not sim.evolution.terminal(),"The scene continues the same habitat after fatal damage")
	expect(sim.evolution.points == points and sim.evolution.learned == learned,"Scene handoff keeps the expedition economy")
	expect(scene.music.frame_cursor >= score_clock,"Succession does not reset the musical transport")
	scene.cell_ui.open_context({"kind":"lineage"})
	scene._process(DT)
	expect(scene.is_paused() and scene.cell_ui.visible and not scene.build_open,"History can pause observation without enabling anatomical edits")
	var bounds := Rect2(Vector2.ZERO,scene.get_viewport_rect().size)
	for choice in scene.cell_ui.choices:
		expect(bounds.encloses(choice.get_global_rect()),"Family choices fit the screen at 175% UI scale")
	click(Vector2.ZERO,MOUSE_BUTTON_RIGHT)
	expect(not scene.is_paused() and scene.cell_ui.context.is_empty(),"Right-click dismisses observation history and resumes")
	# Large goal text reflows; panel bounds must shrink with the text.
	scene.cell_ui.keyboard_target = {"kind":"nucleus"}
	for i in 4:
		scene._process(DT)
		await host.process_frame
	expect(bounds.encloses(scene.cell_ui.tip_box.get_global_rect()),"Nucleus goals remain inside the viewport after 175% text reflow")
	sim.evolution.clock = 620
	sim.evolution.tide = 5
	sim.evolution.resistance = "spike"
	for i in 4:
		scene._process(DT)
		await host.process_frame
	expect(bounds.encloses(scene.cell_ui.tip_box.get_global_rect()),"Late-crisis forecasts and resistance details also fit at 175%")
	scene.cell_ui.keyboard_target.clear()
	# Exhaust the fixture's actual family and bank; terminal feedback must win over death notices.
	sim.lineage.dormant.clear()
	for cell in sim.cells.duplicate():
		if cell != sim.player: sim._die(cell)
	sim.player.health = 0
	scene._physics_process(DT)
	scene._process(DT)
	expect(sim.evolution.status == "lost" and scene.notice.begins_with("EXPEDITION ENDED"),"Last-family loss gives an actionable expedition ending")
	scene.cell_ui.open_context({"kind":"lineage"})
	scene._process(DT)
	expect(scene.cell_ui.choices.size() > 2 and scene.is_paused(),"Family history remains readable after terminal loss")
	var gene: String = sim.evolution.offers[0]
	scene.archive.discovered.append(gene)
	scene.archive.sync(sim)
	scene._restart()
	expect(scene.world != sim and gene in scene.archive.discovered and not scene.archive.expeditions.is_empty(),"An explicit new expedition retains history and blueprint discoveries")
	expect(scene.world.evolution.points == 3 and scene.world.evolution.learned.is_empty(),"Discoveries never create a free starting stat or AP advantage")
	await host.process_frame
