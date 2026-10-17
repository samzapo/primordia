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
	var pond_script = preload("res://scripts/pond.gd")
	test_host.expect(pond_script.catchup_limit(34,8)==1,"Over-budget ticks yield after one step")
	test_host.expect(pond_script.catchup_limit(10,1)==2,"Recovered ticks allow bounded catch-up")
	test_host.expect(pond_script.catchup_limit(14,1)==1 and pond_script.catchup_limit(14,2)==2,"Catch-up hysteresis avoids threshold oscillation")
	host = test_host
	scene = load("res://scenes/pond.tscn").instantiate()
	scene.use_particle_pool = false # Dictionary-edit fixtures; pool UI has separate checks.
	host.root.add_child(scene)
	scene.set_physics_process(false)
	scene.set_process(false)
	await host.process_frame
	# Presentation reads the actual field without drawing RNG or changing ecology.
	var states: Array = [scene.world.rng.state,scene.world.background_rng.state,scene.world.ecology_rng.state]
	var fluid_bytes: PackedByteArray = scene.world.fluid.velocity.to_byte_array()
	var particle_hash: int = hash(scene.world.particles)
	var visual_clock: float = scene.world.time
	scene.flow_view.sync(scene.world,scene.world.player.position,Vector2(632,395),1.0,true,true)
	scene.flow_view.sync(scene.world,scene.world.player.position+Sim.Medium.WORLD,Vector2(632,395),1.0,true,true)
	expect(states == [scene.world.rng.state,scene.world.background_rng.state,scene.world.ecology_rng.state] and fluid_bytes == scene.world.fluid.velocity.to_byte_array() and particle_hash == hash(scene.world.particles) and visual_clock == scene.world.time,"Streamers and wakes do not change fluid, particles, time or random streams")
	expect(scene.flow_view.streamers.material.get_shader_parameter("clock") == scene.world.time,"Flow animation uses simulation time and stops when paused")
	var other = Sim.new(48)
	other.fluid.velocity.fill(Vector2(17,-23))
	scene.flow_view.sync(other,other.player.position,Vector2(632,395),1.0,true,true)
	var new_pixel: Color = scene.flow_view.cached_field.get_pixel(0,0)
	expect(Vector2(new_pixel.r,new_pixel.g) == Vector2(17,-23),"A restart at the same clock immediately replaces the old flow display")
	scene.flow_view.sync(scene.world,scene.world.player.position,Vector2(632,395),1.0,true,true)
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
	expect(scene.light_layer.material.get_shader_parameter("clock") == scene.world.time,"Broad water shimmer pauses with simulation time")
	for view in scene.views.values():
		expect(not view.water_wake.z_as_relative and view.water_wake.z_index < min(2,view.z_index) and view.water_wake.mesh == view.surface.mesh,"Stronger cell wakes share the deformed outline and draw behind all cell bodies")
	# Wakes depend on external water/body slip, never absolute world speed.
	var body = Sim.Cell.new()
	var medium = Sim.Medium.new()
	body.velocity = Vector2(25,-12)
	medium.velocity.fill(body.velocity)
	var slip: Vector2 = scene.CellView.relative_flow(body,medium,0)
	expect(slip.length() < 0.001,"A current-carried cell has no directional wake")
	medium.velocity.fill(Vector2(-15,8))
	slip = scene.CellView.relative_flow(body,medium,0)
	expect(slip.distance_to(Vector2(-40,20)) < 0.001,"Cell wakes follow water velocity minus apparent cell velocity")
	body.velocity += Vector2(100,70)
	medium.velocity.fill(Vector2(85,78))
	expect(scene.CellView.relative_flow(body,medium,0).distance_to(slip) < 0.001,"A common world-frame velocity shift does not change a wake")
	expect(scene.CellView.relative_flow(body,medium,PI/2).distance_to(slip.rotated(-PI/2)) < 0.001,"Wake direction transforms into the membrane's rotating local frame")
	# Bounded diagnostics aggregate catch-up ticks without changing ecology.
	var before_trace: int = hash(scene.world.particles)
	var before_time: float = scene.world.time
	scene.begin_frame_trace()
	scene.begin_frame_trace() # Idempotent; never duplicate render callbacks.
	scene.frame_trace.tick(1000,DT)
	scene.frame_trace.tick(2000,DT)
	scene.frame_trace.work("music",250)
	scene.frame_trace._pre()
	scene.frame_trace._post()
	var trace: Array[Dictionary] = scene.end_frame_trace()
	expect(trace.size() == 1 and trace[0].ticks == 2 and is_equal_approx(trace[0].sim_dt,DT*2) and trace[0].phases_ms.ticks == 3.0 and trace[0].phases_ms.music == 0.25,"Frame trace accounts for every catch-up tick and separately measures music")
	expect(trace[0].counts.has("pheromone_queries") and trace[0].counts.has("cell_contacts"),"Frame traces retain explicit zero workload counters")
	expect(not scene.world.profiling and hash(scene.world.particles) == before_trace and scene.world.time == before_time,"Stopping diagnostics restores the unprofiled simulation without ecological changes")
	# The only permanent pane is settings, which starts hidden.
	var panes := 0
	for node in scene.ui.get_children():
		if node is PanelContainer: panes += 1
	expect(panes == 1 and not scene.settings_panel.visible,"No top, bottom or assembly panes remain")
	expect(scene.batches.size() == Sim.SPECIES_COUNT,"Renderer retains all chemistry species")
	key(KEY_M)
	var identity = scene.world.player
	key(KEY_TAB)
	expect(scene.settings_panel.visible and not scene.build_open and scene.world.player == identity,"Settings pauses and prevents edits behind the modal")
	expect(scene.quit_button.pressed.get_connections().size() == 1,"Settings retains Quit")
	scene.bloom_check.toggled.emit(false)
	expect(scene.microscope_layer.visible and not scene.preferences.bloom,"Turning off bloom preserves the shared blur/lens pass")
	scene.bloom_check.toggled.emit(true)
	scene.ripple_check.toggled.emit(false)
	expect(not scene.preferences.water_ripples and scene.light_layer.material.get_shader_parameter("water_ripples") == false,"Water shimmer can be disabled without changing anatomy or the screen-copy pass")
	scene.ripple_check.toggled.emit(true)
	expect(scene.world.particle_collisions,"Ordinary gameplay restores particle collisions without consulting the old trial preference")
	key(KEY_M)
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
	expect(scene.cell_ui.choices.size() == 5,"Factory offers four choices plus another page")
	scene.cell_ui.choices[-1].pressed.emit()
	var found_cilia := false
	var hunt
	for choice in scene.cell_ui.choices:
		found_cilia = found_cilia or choice.kind == "cilia"
		if choice.kind == "hunting": hunt = choice
	expect(found_cilia and hunt != null,"Cilia and hunting remain illustrated purchases on the second page")
	hunt.pressed.emit()
	expect(scene.selected == 10,"Hunting receptor selection reaches the normal membrane placement flow")
	click(scene.cell_ui.screen_at({"kind":"assembly"}))
	scene.cell_ui.choices[1].pressed.emit()
	expect(scene.selected == 1 and scene.cell_ui.choices.is_empty(),"Factory choice picks a cortex without a build panel")
	var before_zoom: float = scene.manual_zoom
	var cursor := Vector2(80,180)
	click(cursor,MOUSE_BUTTON_WHEEL_UP)
	expect(scene.manual_zoom > before_zoom and scene.camera_offset == Vector2.ZERO and Sim.Medium.offset(scene.render_camera,cell.position).length() < 0.001,"Wheel during placement zooms around the followed cell")
	click(at(cell.local_point(2.15)))
	expect(cell.count("protection") == 1 and cell.organs[-1].scale == 1,"New organs have a fixed standard size")
	var organ_id: int = cell.organs[-1].id
	scene._update_world(1)
	var seen: int = scene.views[cell.id].seen_revision
	click(at(cell.local_point(2.15)),MOUSE_BUTTON_RIGHT)
	expect(scene.selected == -1 and not cell.organ_by_id(organ_id).is_empty(),"Right-click cancels the held ghost without recycling installed anatomy")
	scene.cell_ui.open_context({"kind":"organ","id":organ_id})
	expect(scene.cell_ui.choices.size() == 3 and scene.cell_ui.choices[0].caption == "Move" and scene.cell_ui.choices[1].caption == "Recycle" and scene.cell_ui.choices[2].caption == "Output 100%","An unmodified organ exposes Move, Recycle and output, with no resize or Undo")
	var points: int = scene.world.evolution.points
	scene.cell_ui.choices[1].pressed.emit()
	scene._update_world(1)
	expect(cell.count("protection") == 0 and scene.views[cell.id].seen_revision > seen,"Recycling refreshes the paused drawing before resuming")
	expect(scene.world.evolution.points == points,"Recycling does not refund AP")
	scene.cell_ui.open_context({"kind":"behavior"})
	var behavior_costs: Array = [cell.biomass,cell.energy,scene.world.evolution.points]
	expect(scene.cell_ui.choices[0].caption == "Exploration 25%" and scene.cell_ui.choices[1].caption == "Cycle 4s","The nucleus exposes clear default exploration and response-cycle controls")
	scene.cell_ui.choices[0].pressed.emit()
	scene.cell_ui.choices[1].pressed.emit()
	expect(cell.exploration == 0.5 and cell.response_cycle == 8 and behavior_costs == [cell.biomass,cell.energy,scene.world.evolution.points],"Behavior controls update immediately without charging tissue, ATP or AP")
	cell.set_exploration(0.25)
	cell.set_response_cycle(4)
	# Steering lives on the organ; preview quantities are usable tissue only.
	var pore: Dictionary = cell.organs.filter(func(item):return item.kind == "feeding")[0]
	scene.cell_ui.open_context({"kind":"organ","id":pore.id})
	expect(scene.cell_ui.choices.size() == 2 and scene.cell_ui.choices[0].caption == "Steering 100%" and scene.cell_ui.choices[1].caption == "Output 100%","A pore exposes steering and ATP-funded output as separate choices")
	var resource_state: Array = [cell.biomass,cell.energy,scene.world.evolution.points]
	for i in 3: scene.cell_ui.choices[0].pressed.emit()
	expect(Sim.Cell.steering_strength(pore) == 0 and scene.cell_ui.choices[0].caption == "Steering Off","Clicking the local strength choice cycles to steering Off")
	expect(resource_state == [cell.biomass,cell.energy,scene.world.evolution.points],"Local tuning spends no physical resource or adaptation point")
	expect(scene.cell_ui.describe({"kind":"organ","id":pore.id}).contains("Steering Off"),"Organ inspection immediately reports its steering setting")
	for i in 3: scene.cell_ui.choices[0].pressed.emit()
	var output_choice = scene.cell_ui.choices[1]
	expect(output_choice.caption == "Output 100%" and output_choice.symbol == "Out 100%","Output has a distinct visible label beside steering")
	output_choice.pressed.emit()
	expect(Sim.Genes.output(pore) == 1.5 and scene.cell_ui.choices[1].caption == "Output 150%","The actual output menu applies the validated percentage command")
	expect(resource_state == [cell.biomass,cell.energy,scene.world.evolution.points],"Output tuning itself spends no physical resource or AP")
	scene.cell_ui.close_context()
	# The actual kept upgrade price feeds both the tooltip and visual cost comparison.
	cell.add_organ("propulsion",PI,"graze",false)
	var upgraded: Dictionary = cell.organs[-1]
	var upgrade_gene := ""
	for gene in Sim.Genes.DATA:
		if Sim.Genes.DATA[gene].kind == "propulsion": upgrade_gene = gene; break
	scene.world.evolution.learned.append(upgrade_gene)
	scene.cell_ui.open_context({"kind":"organ","id":upgraded.id})
	scene.cell_ui.sync(0)
	var upgrade = scene.cell_ui.choices[-1]
	upgrade.grab_focus()
	scene.cell_ui.sync(0)
	var upgrade_quote: Dictionary = scene.cell_ui.biomass_view.quote
	expect(upgrade_quote.show_cost and upgrade_quote.cost == Sim.Genes.price(upgraded) and upgrade_quote.ap_needed == Sim.Genes.adaptation_price(upgraded),"Inspecting a real upgrade displays its tissue and AP costs")
	expect(upgrade.description.contains("Free mutation"),"Mutation tooltip states that application is free")
	expect(scene.cell_ui.biomass_view.rate_quote.preview and scene.cell_ui.biomass_view.rate_quote.has_organ and not scene.cell_ui.tip.text.contains("\n"),"Upgrade inspection shows its proposed upkeep before spending")
	var type_scale: float = scene.preferences.hud_scale
	scene.preferences.hud_scale = 1.75
	scene.cell_ui.sync(0)
	expect(not Rect2(scene.cell_ui.tip_box.position,scene.cell_ui.tip_box.size).intersects(scene.cell_ui.biomass_view.comparison_bounds()),"Large upgrade tooltips keep stock, price and ATP sacs visible")
	scene.preferences.hud_scale = type_scale
	scene.cell_ui.sync(0)
	var saved_upgrade_tissue: float = cell.biomass
	var saved_upgrade_ap: int = scene.world.evolution.points
	cell.biomass = 0
	scene.world.evolution.points = 0
	scene.cell_ui.sync(0)
	expect(scene.cell_ui.biomass_view.quote.enough and scene.cell_ui.biomass_view.quote.ap_ready,"Free mutation remains available with empty biomass and AP")
	cell.biomass = saved_upgrade_tissue
	scene.world.evolution.points = saved_upgrade_ap
	scene.cell_ui.close_context()
	expect(not scene.cell_ui.biomass_view.quote.show_cost,"Closing upgrade choices clears the visual price")
	scene.selected = 0
	scene.cell_ui.sync(0)
	var stock = scene.cell_ui.biomass_view
	var quote: Dictionary = stock.quote
	expect(stock.visible and quote.available == cell.biomass and quote.cost == 0 and quote.ap_needed == 1,"The build preview shows AP-only construction alongside usable biomass")
	expect(is_equal_approx(pow(quote.cost_radius/quote.stock_radius,2),quote.cost/quote.available),"Available and required blobs use the same area scale")
	var usable: float = cell.biomass
	cell.biomass = 100000
	stock.sync()
	expect(stock.quote.stock_radius <= stock.quote.maximum+0.0001 and is_equal_approx(pow(stock.quote.cost_radius/stock.quote.stock_radius,2),stock.quote.cost/stock.quote.available),"Huge reserves fit the viewport while preserving the comparison ratio")
	cell.biomass = 0
	stock.sync()
	expect(stock.quote.stock_radius == 0 and stock.quote.cost_radius == 0 and stock.quote.enough,"Zero usable biomass cannot block AP-only construction")
	cell.biomass = 8
	stock.sync()
	expect(stock.quote.enough and stock.quote.cost_radius == 0,"Construction has no required-tissue blob")
	cell.biomass = 7.9
	stock.sync()
	expect(stock.quote.enough,"Low tissue does not create a false construction shortfall")
	cell.biomass = usable
	var reserve_before: float = cell.brood_mass
	cell.reserve(4)
	stock.sync()
	expect(stock.quote.available == usable-4 and stock.quote.available != cell.organic_mass(),"Reserved and structural tissue are excluded from the usable biomass blob")
	cell.reserve(-4)
	expect(cell.brood_mass == reserve_before,"Preview fixture restores the paid offspring reserve")
	scene.selected = -1
	stock.sync()
	expect(stock.quote.cost == 0,"Cancelling placement removes its cost blob without changing biomass")
	var geometry: PackedVector2Array = cell.membrane.points.duplicate()
	var age: float = cell.age
	var energy: float = cell.energy
	scene._process(DT)
	expect(cell.membrane.points != geometry and cell.age == age and cell.energy == energy and scene.world.time == clock,"Paused geometry responds without biological progress")
	key(KEY_M)
	expect(scene.settings_panel.visible and scene.build_open and scene.world.player == cell,"Settings preserves current paid edits")
	key(KEY_M)
	expect(scene.build_open and scene.world.evolution.points == points,"Closing settings returns to the same paused cell")
	key(KEY_TAB)
	expect(not scene.cell_ui.biomass_view.visible,"Biomass comparison disappears during ordinary play")
	expect(not scene.build_open and scene.world.build_original == null and scene.world.evolution.points == points,"Tab keeps edits without an Apply or Undo button")
	settle()
	expect(is_equal_approx(scene.manual_zoom,0.8),"Leaving edit restores the observation magnification")
	# Factory, nucleus, bud and keyboard access retain the run's decision economy.
	key(KEY_TAB)
	settle()
	cell = scene.world.player
	scene.cell_ui.open_context({"kind":"chemistry"})
	expect(scene.cell_ui.choices.size() == 5 and scene.cell_ui.choices.any(func(choice):return choice.kind=="regenerative") and scene.cell_ui.choices.any(func(choice):return choice.kind=="photosynthesis"),"Chemistry factory exposes photosynthesis and glands with compact desktop paging")
	scene.cell_ui.choices[-1].pressed.emit()
	expect(scene.cell_ui.choices.any(func(choice):return choice.caption=="Food vacuoles") and scene.cell_ui.choices.any(func(choice):return choice.kind=="neutralizing"),"The next chemistry page retains neutralization and food/gas inspection")
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
	expect(scene.cell_ui.interior.atp_size == 0,"An empty ATP resource renders an empty sac")
	cell.energy = cell.energy_reference()
	scene.world.evolution.points = 7
	scene.cell_ui.interior.sync()
	expect(scene.cell_ui.interior.atp_size > 0,"Positive ATP produces a nonempty elastic sac")
	scene.cell_ui.biomass_view.sync()
	expect(scene.cell_ui.biomass_view.quote.ap_count == 7,"The cost comparison reads actual available AP")
	scene.world.evolution.points = 0
	scene.cell_ui.biomass_view.sync()
	expect(scene.cell_ui.biomass_view.quote.ap_count == 0,"Empty AP stock shows no available gold blobs")
	scene.world.evolution.points = 7
	scene.cell_ui.biomass_view.sync()
	expect(not scene.cell_ui.interior.anchors.has("coins") and scene.cell_ui.targets().all(func(target): return target.kind != "coins"),"Removed internal coins leave no invisible clickable node")
	var saved_age: float = cell.age
	var saved_selection: int = scene.selected
	cell.age = maxf(1,cell.age)
	scene.selected = -1
	cell.energy_budget = preload("res://scripts/energy_budget.gd").new()
	cell.energy_budget.record(cell.age-1,0,0,0,-1,"upkeep")
	cell.energy_budget.record(cell.age,4,3,1,cell.organs[0].id,"pumping")
	scene.cell_ui.keyboard_target = {"kind":"organ","id":cell.organs[0].id}
	scene.cell_ui.hovered.clear()
	scene.cell_ui.biomass_view.sync()
	var budget: Dictionary = scene.cell_ui.biomass_view.rate_quote
	expect(budget.has_organ and not budget.preview and is_equal_approx(budget.shown,1) and is_equal_approx(budget.rates.spent,1),"Installed organ's sac compares actual ATP/s against total drain on the same scale")
	expect("Recent actual" in scene.cell_ui.describe(scene.cell_ui.keyboard_target) and "Pumping" in scene.cell_ui.describe({"kind":"atp"}),"Organ and ATP-sac hover explain actual costs and the cell's expense breakdown")
	cell.age = saved_age
	scene.selected = saved_selection
	cell.energy_budget = preload("res://scripts/energy_budget.gd").new()
	scene.cell_ui.keyboard_target.clear()

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
	expect(cell.membrane.skeleton.next_group == groups,"Dragging bare membrane cannot edit sampled microtubules")
	var links: Array=cell.membrane.skeleton.links.duplicate(true)
	click(ends[0],MOUSE_BUTTON_WHEEL_UP)
	click(ends[0],MOUSE_BUTTON_RIGHT)
	expect(cell.membrane.skeleton.links==links,"Wheel and right-click preserve procedural anatomy")
	click(ends[0])
	key(KEY_TAB)
	expect(scene.tube_start.is_empty(),"Resuming cancels an unfinished microtubule drag")
	settle()
	groups = scene.world.player.membrane.skeleton.next_group
	click(at(scene.world.player.local_point(0.7)))
	click(at(scene.world.player.local_point(2.5)),MOUSE_BUTTON_LEFT,false)
	expect(scene.world.player.membrane.skeleton.next_group == groups,"Microtubule editing remains unavailable during play")
	# Follow zoom always centers the body; free zoom preserves the cursor's world point.
	scene.camera_locked = true
	scene.camera_offset = Vector2(85,-60)
	scene.world.player.previous_position = scene.world.player.position
	scene.manual_zoom = 1.2
	scene._update_world(1)
	var zoom_cursor: Vector2 = scene.camera_screen+Vector2(120,70)
	scene._zoom_at(zoom_cursor,1.12)
	expect(scene.camera_offset == Vector2.ZERO and Sim.Medium.offset(scene.render_camera,scene.world.player.position).length() < 0.001 and scene.world.camera_follows_player,"Locked wheel zoom recenters the cell even after a paused pan")
	scene._toggle_camera()
	var before: Vector2 = scene.render_camera+(zoom_cursor-scene.camera_screen)/scene.zoom
	scene._zoom_at(zoom_cursor,1/1.12)
	var after: Vector2 = scene.render_camera+(zoom_cursor-scene.camera_screen)/scene.zoom
	expect(Sim.Medium.offset(before,after).length() < 0.001,"Free-view wheel zoom retains the cursor's world position")
	scene._toggle_camera()
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
	_native_pool()
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
		sim.spawn_particle(kind,sim.player.position+Vector2(170+(kind%13)*22,150+(kind/13)*40),Vector2.ZERO,0.3)
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
	expect(through_cell.is_empty(),"Pheromones cannot activate the lens through a cell interior")
	tracer.p = sim.player.position+Vector2(190,-170)
	tracer.previous = tracer.p
	sim.grid.rebuild(sim.particles)
	var tracer_screen: Vector2 = scene.camera_screen+Sim.Medium.offset(scene.render_camera,tracer.p)*scene.zoom
	scene.inspector.update_lens(0.2,tracer_screen,1,true)
	expect(scene.inspector.label.text.contains("Reported size:") and scene.inspector.label.text.contains("unarmed"),"The local tooltip describes the emitted metadata")
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position+Vector2(sim.player.visible_support(0)+10/scene.zoom,0))
	var close_packet: Dictionary = sim.particles[-1]
	sim.grid.rebuild(sim.particles)
	var close_screen: Vector2 = scene.camera_screen+Sim.Medium.offset(scene.render_camera,close_packet.p)*scene.zoom
	expect(scene.inspector.pick(close_screen,1).is_empty(),"Particles just outside a membrane cannot activate the lens")
	var npc = Sim.Cell.new(900001)
	sim.cells.append(npc)
	var saved_pose: Array = [npc.position,npc.previous_position]
	npc.position = tracer.p
	npc.previous_position = tracer.p
	scene.inspector.update_lens(0.01,tracer_screen,1,true)
	expect(scene.inspector.hovered.is_empty() and scene.inspector.lens_amount == 0,"A cell entering a tracked particle's quiet zone immediately dismisses magnification")
	npc.position = saved_pose[0]
	npc.previous_position = saved_pose[1]
	sim.cells.erase(npc)
	scene.inspector.update_lens(0.2,tracer_screen,1,true)
	var prior_text: String = scene.inspector.label.text
	tracer.report.hostile = true
	scene.inspector.update_lens(0.2,tracer_screen,1,true)
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
	expect(scene.build_open and sim.build_original != null and sim.player.organic_mass() < mass and sim.evolution.points == points+2,"Birth awards two AP, commits paid anatomy and resumes editing the depleted parent")
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
	var camera_before_death: Vector2=scene.render_camera
	sim.player.health = 0
	scene._physics_process(DT)
	scene._process(DT)
	expect(scene.world == sim and sim.player.id != identity and sim.time > time and not sim.evolution.terminal(),"The scene continues the same habitat after fatal damage")
	expect(sim.evolution.points == points+2 and sim.evolution.learned == learned,"Scene handoff keeps the expedition economy")
	expect(scene.music.frame_cursor >= score_clock,"Succession does not reset the musical transport")
	var death_at: Vector2 = sim.death_bursts[-1].at
	expect(scene.death_focus_age < 0.1 and Sim.Medium.offset(scene.render_camera,camera_before_death).length() < 0.001,"Rupture relocation begins from the current view without a camera jump")
	expect(not scene.death_view.bursts.is_empty() and not scene.views.has(identity),"The dead membrane becomes visible rupture fragments while real lysis packets remain")
	var biological_state: Array = [sim.time,sim.rng.state,sim.ecology_rng.state,sim.background_rng.state,hash(sim.particles)]
	var before_frame: int = scene.music.frame_cursor
	scene._process(0.5)
	expect(Sim.Medium.offset(scene.render_camera,death_at).length() <= Sim.Medium.offset(camera_before_death,death_at).length()+.001,"Camera eases toward the original death site while the rupture remains visible")
	scene._process(.17)
	expect(Sim.Medium.offset(scene.render_camera,death_at).length()<.001,"Camera arrives at the death site before the successor handoff begins")
	scene._process(0.68)
	expect(scene.death_focus_age > 1.15 and scene.death_focus_age < 1.8,"Camera handoff starts only after the visible death burst")
	scene._process(0.6)
	expect(Sim.Medium.offset(scene.render_camera,sim.player.position).length() < 0.001 and scene.death_view.bursts.is_empty(),"The camera reaches its successor and expired fragments clear")
	expect(biological_state == [sim.time,sim.rng.state,sim.ecology_rng.state,sim.background_rng.state,hash(sim.particles)] and scene.music.frame_cursor >= before_frame,"Death presentation neither advances nor mutates biology and preserves musical transport")
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
	sim.evolution.resistance = "pore"
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

func _native_pool() -> void:
	var sim = Sim.new(271)
	if sim.kernels == null: return
	sim.cells = [sim.player]
	sim.pending_replacements.clear()
	sim.habitat_geometry.enabled = false
	sim.particles.clear()
	sim.pheromones.clear()
	sim.grid.rebuild(sim.particles)
	sim.spawn_particle(Sim.OXYGEN,sim.player.position+Vector2(220,30),Vector2.ZERO,0.3,900)
	sim.particles[0].alive = false
	sim.spawn_particle(Sim.ENZYME,sim.player.position+Vector2(180,0),Vector2.ZERO,0.3,900)
	sim.enable_particle_pool()
	scene.world = sim
	scene.camera_locked = true
	scene.build_open = false
	scene.manual_zoom = 0.8
	scene.focus_animating = false
	scene._update_world(1)
	var cursor: Vector2 = scene.camera_screen+Vector2(180,0)*scene.zoom
	scene.inspector.update_lens(0,cursor,1,false)
	var exports: int = sim.kernels.pool_metrics().exports
	scene._sync_particles(1)
	expect(sim.kernels.pool_metrics().exports==exports,"Native scene drawing reads the pool without particle snapshots")
	scene.inspector.update_lens(0.2,cursor,1,true)
	expect(not scene.inspector.hovered.is_empty() and scene.inspector.hovered.kind==Sim.ENZYME,"Native pool particles remain locally inspectable")
	if scene.inspector.hovered.is_empty(): return
	var handle: int = scene.inspector.hovered.packet._handle
	sim._compact_particles()
	sim.grid.rebuild(sim.particles)
	scene.inspector.update_lens(0.1,cursor,1,true)
	expect(not scene.inspector.hovered.is_empty() and scene.inspector.hovered.packet._handle==handle and scene.inspector.hovered.index==0,"The real lens keeps its handle through native slot compaction")
	expect(scene.inspector.pick(scene.camera_screen,1).is_empty(),"Native picking still suppresses cell-adjacent particles")
	scene.set_particle_collisions(true)
	expect(sim.particle_collisions and sim.particle_pool,"Collision setting switches the live native pool without a fallback")
	sim._chemistry(100000)
	scene.inspector.update_lens(0.1,cursor,1,true)
	expect(scene.inspector.hovered.is_empty(),"A consumed/decayed native handle cannot leave a ghost lens")
	scene._restart()
	expect(scene.world.particle_pool==false,"Dictionary fixture restart honors its explicit ownership setting")
	scene.set_particle_collisions(false)
	scene.use_particle_pool = true
	scene._restart()
	expect(scene.world.particle_pool and scene.world.particles.is_empty(),"Explicit CPU-reference restart enables authoritative pool ownership")
	expect(scene.world.particle_collisions,"Ordinary restart restores collisions after any diagnostic override")
	scene.set_particle_collisions(false)
