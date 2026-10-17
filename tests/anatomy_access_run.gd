extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool,text: String) -> void:
	assertions += 1
	if not ok: failures += 1; push_error(text)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1170,2100)
	var game = load("res://scenes/pond.tscn").instantiate()
	game.use_particle_pool = false
	root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	game.music.enabled = false; game.music.player.stop()
	game.touch_zoom.enabled = true; game.touch_zoom.pixels = 3
	var cell = game.world.player
	var family = game.Simulation.Cell.clone_state(cell)
	family.id = 901; family.lineage = cell.lineage_id()
	family.position += Vector2(160,0); family.previous_position = family.position
	var foreign = game.Simulation.Cell.clone_state(cell)
	foreign.id = 902; foreign.lineage = 902
	foreign.position = cell.position; foreign.previous_position = foreign.position
	game.world.cells = [cell,family,foreign]
	game.manual_zoom = 3; game._update_world(1)
	for mode in ["exteroception","interoception"]:
		game.perception = mode; game._update_world(1)
		check(game.views[cell.id].z_index > game.views[foreign.id].z_index+game.views[foreign.id].appendages.z_index,"Controlled body covers unrelated bodies and appendages in either perception")
		check(game.views[family.id].z_index > game.views[foreign.id].z_index+1,"Owned family draws over uncontrolled lineages")
		check(game.cell_ui.interior.z_index > game.views[cell.id].z_index+1,"Factories remain above the controlled cell's appendages")
	game.perception = "exteroception"; game._update_world(1)
	game._toggle_build()
	cell = game.world.player
	var ui = game.cell_ui
	var anchors: Dictionary = ui.interior.anchors.duplicate()
	ui.interior.anchors.chemistry = ui.interior.anchors.assembly
	var target: Dictionary = ui.pick(ui.screen_at({"kind":"chemistry"}))
	check(target.kind == "overlap" and target.targets.any(func(t):return t.kind == "chemistry") and target.targets.any(func(t):return t.kind == "assembly"),"An overlapping factory cannot be lost to the nearest drawn control")
	ui.open_context(target)
	var chemical_choices: Array = ui.choices.filter(func(choice):return choice.caption == "Chemistry factory")
	check(chemical_choices.size() == 1 and chemical_choices[0].get_parent() == ui.mobile_flow,"Overlapping mobile structures have separate top-tray choices")
	chemical_choices[0].pressed.emit()
	check(ui.context.kind == "chemistry" and ui.choices.any(func(choice):return choice.kind == "acidifying"),"The obscured factory still opens its functional gland actions")
	ui.interior.anchors = anchors
	ui.close_context()
	cell.biomass = 100
	cell.add_organ("photosynthesis",2,"graze",false)
	var leaf: Dictionary = cell.organs[-1]
	game.world.evolution.learned.clear()
	var stock: Array = [cell.biomass,cell.energy,game.world.evolution.points,leaf.material,leaf.hp,leaf.max_hp]
	for gene in ["shade_leaf","sun_leaf","shade_leaf"]:
		check(game.world.edit("mutate",{"id":leaf.id,"gene":gene}) and leaf.mutation == gene,"Sun/shade changes are accepted without random blueprint discovery")
	check(stock == [cell.biomass,cell.energy,game.world.evolution.points,leaf.material,leaf.hp,leaf.max_hp],"Changing light adaptation never creates resources or compounds organ health")
	ui.open_context({"kind":"organ","id":leaf.id})
	# Mobile has no desktop page limit.
	check(ui.choices.any(func(choice):return choice.caption == "Sun specialist") and ui.choices.any(func(choice):return choice.caption == "Shade specialist (active)" and choice.disabled),"Both light adaptations stay visible with the active choice marked")
	check(not game.world.edit("mutate",{"id":leaf.id,"gene":"pulse_vesicle"}),"Photosynthesis availability never authorizes a mismatched mutation")
	game._toggle_build()
	game.manual_zoom = 2; game.camera_locked = false; game.free_camera = cell.position
	game._update_world(1)
	var at: Vector2 = game.views[family.id].get_global_transform_with_canvas().origin
	var clock: float = game.world.time
	var random: int = game.world.rng.state
	game.touch_zoom._tap(at)
	check(game.world.player == cell,"A single tap does not transfer control")
	game.touch_zoom._tap(at)
	check(game.world.player == family and game.camera_locked,"Double tap adopts the existing living family member and follows it")
	check(game.world.time == clock and game.world.rng.state == random and game.world.cells.size() == 3,"Family switching advances no world time and creates no cell")
	check(not game._switch_family(foreign.id),"Family gestures cannot select another player's or uncontrolled lineage")
	family.dead = true
	game.world.player = cell
	check(not game._switch_family(family.id),"A dead family member cannot be adopted")
	# AP construction introduces explicitly accounted organ tissue.
	var sim = game.Simulation.new(993)
	sim.cells = [sim.player]
	sim.player.organs.clear(); sim.player.biomass = 0; sim.player.energy = 0
	sim.player.update_geometry(); sim.evolution.points = 2
	var original_mass: float = sim.player.organic_mass()
	var original_input: float = sim.external_input
	check(sim.install("regenerative",0) and sim.evolution.points == 2,"The first organ is free and requires no biomass/ATP")
	check(sim.player.biomass == 0 and sim.player.energy == 0,"Construction never debits cell biomass or ATP")
	check(is_equal_approx(sim.player.organic_mass()-original_mass,sim.external_input-original_input),"AP construction tissue is an exact explicit material source")
	var installed: Dictionary = sim.player.organs[-1]
	sim.player.lost_organs.append(installed.duplicate(true)); sim.player.organs.clear()
	check(sim.edit("restore",{"id":installed.id}) and sim.evolution.points == 2 and sim.player.biomass == 0,"Restoring the only absent organ uses the zero-AP next price")
	sim.evolution.points = 0
	var no_ap_state: Array = [sim.player.organic_mass(),sim.external_input,sim.player.organs.size()]
	check(not sim.install("photosynthesis",1) and no_ap_state == [sim.player.organic_mass(),sim.external_input,sim.player.organs.size()],"A rejected AP purchase introduces no material or organ")
	sim.evolution.points = 1
	var source_before: float = sim.external_input
	sim.begin_build(); check(sim.install("photosynthesis",2),"A local plan can use its AP-only build path")
	sim.cancel_build()
	check(sim.external_input == source_before and sim.evolution.points == 1,"Cancelling a local plan rolls back its material source and AP")
	var npc = game.Simulation.Cell.new(994)
	npc.body = 70; npc.biomass = 0; npc.energy = 0; npc.update_geometry()
	npc.add_organ("feeding",0,"graze",false)
	var managed = game.Simulation.Cell.clone_state(npc); managed.id = 995; managed.lineage = 995
	sim.cells.append(npc); sim.cells.append(managed)
	sim.managed_lineages = [managed.lineage_id()]
	var ledger = sim._family_ledger(npc); ledger.progression.sandbox = true; ledger.progression.points = 2
	var player_ap: int = sim.evolution.points
	var npc_input: float = sim.external_input; var npc_mass: float = npc.organic_mass()
	sim.step_autonomous_builds()
	check(npc.organs.size() == 2 and ledger.progression.points == 2,"An unmanaged lineage buys one strategy-selected fitting organ with its own AP")
	check(managed.organs.size() == 1 and sim.evolution.points == player_ap,"Offline player-owned roots and the selected lineage keep their AP")
	check(npc.biomass == 0 and npc.energy == 0 and is_equal_approx(npc.organic_mass()-npc_mass,sim.external_input-npc_input),"NPC builds use the same AP-only material accounting")
	sim.step_autonomous_builds()
	check(ledger.progression.points == 2,"NPC purchases are bounded by a simulation-time retry interval")
	sim.time += 2; sim.step_autonomous_builds()
	check(ledger.progression.points == 1 and npc.organs.size() == 3,"NPC purchases spend existing AP once per successful build")
	sim.time += 2; sim.step_autonomous_builds()
	check(npc.organs.size() == 3,"An unmanaged lineage stops buying when its AP is exhausted")
	ledger.progression.points = 2
	var codec = preload("res://scripts/network/state_codec.gd").new()
	var recovered = codec.restore(codec.capture(sim))
	sim.time += 2; recovered.time += 2
	sim.step_autonomous_builds(); recovered.step_autonomous_builds()
	var recovered_npc = recovered.cells.filter(func(body):return body.id == npc.id)[0]
	check(recovered_npc.organs == npc.organs and recovered._family_ledger(recovered_npc).progression.points == ledger.progression.points,"NPC AP and strategy purchase sequence survive a checkpoint restart")
	game.queue_free(); await process_frame
	print("ANATOMY ACCESS: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
