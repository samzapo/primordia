extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Sac=preload("res://scripts/toxin_sac.gd")
var assertions:=0
var failures:=0
func check(ok: bool,why: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func fixture():
	var sim=Sim.new(77,0,false);sim.server_mode=true;sim.evolution.sandbox=true
	sim.player.add_organ("feeding",0,"graze",false);sim.cells=[sim.player]
	sim.habitat_geometry=Sim.Habitat.new(77,sim.cells);sim.habitat_geometry.enabled=false;sim.automatic_reproduction=false
	return sim
func total(sim) -> float:
	var amount:=0.0
	for cell in sim.cells:
		if not cell.dead:amount+=cell.organic_mass()
	for packet in sim.particle_snapshots():
		if packet.alive:amount+=packet.amount*Sim.Catalog.material(packet.kind)
	return amount+sim.build_waste
func funded(sim) -> void:
	sim.player.biomass=200;sim.player.energy=100
	sim.player.brood_mass=sim.offspring_quote().material;sim.player.brood_energy=60
func run() -> void:
	var sim=fixture();var parent=sim.player
	for i in 3:
		var relative=Sim.Cell.new(100+i,Vector2(-1500+i*500,-1000))
		relative.lineage=parent.lineage_id();relative.add_organ("feeding",0,"graze",false)
		sim.cells.append(relative);sim.lineage.register(relative,parent.id,1,"living",0)
	funded(sim)
	var before=var_to_bytes(Codec.new().capture(sim));var rng: int=sim.rng.state
	var readiness: Dictionary=sim.division_status()
	check(readiness.ready and var_to_bytes(Codec.new().capture(sim))==before and sim.rng.state==rng,"Readiness examines the whole family and safe placement without changing ecology, AP or RNG")
	var points: int=sim.player.ap
	var mass:=total(sim)
	check(sim.divide_lineage(false,false) and sim.lineage.active_family(sim).size()==5,"A funded family can divide past four living members")
	check(sim.player.ap==points+1 and absf(total(sim)-mass)<.00001 and sim.player==parent,"Only committed division awards one AP to each body and conserves paid tissue without changing control")
	funded(sim);before=var_to_bytes(Codec.new().capture(sim))
	for i in range(sim.cells.size(),sim.MAX_LIVE_CELLS):
		var extra=Sim.Cell.new(200+i,Vector2(1200,800));sim.cells.append(extra)
	var full: Dictionary=sim.division_status();mass=total(sim);points=sim.player.ap;rng=sim.rng.state
	check(not full.ready and full.reason.contains("pond is full") and not sim.divide_lineage(false,false),"Whole-pond capacity is explicit and still enforced")
	check(total(sim)==mass and sim.rng.state==rng and sim.player.ap==points,"Capacity rejection spends nothing and draws no strategy randomness")
	sim=fixture();parent=sim.player;funded(sim)
	var blocker=Sim.Cell.new(999,parent.position);blocker.body=10000000;blocker.update_geometry();blocker.membrane=Sim.Cell.Membrane.new(blocker.radius);sim.cells.append(blocker)
	check(not sim.division_status().ready and sim.division_status().reason.contains("clear water"),"A fully funded but physically blocked birth explains clear-water waiting")
	sim.cells.erase(blocker);parent.brood_mass=0
	check(not sim.division_status().ready and sim.division_status().reason.contains("still needed"),"Incomplete growth cannot be shown as ready")
	sim=fixture();parent=sim.player;parent.biomass=50;parent.energy=100
	check(parent.add_organ("toxin_sac",1,"graze",false),"Toxin sac installs with ordinary anatomy and progressive AP pricing")
	var sac: Dictionary=parent.organs[-1];mass=total(sim)
	var energy: float=parent.energy;Sac.fill(parent,25)
	check(is_equal_approx(sac.stored_toxin,1) and absf(total(sim)-mass)<.00001 and is_equal_approx(parent.energy,energy-1),"Filling converts only paid biomass into one finite unit and charges actual ATP")
	Sac.fill(parent,1000)
	check(is_equal_approx(sac.stored_toxin,2) and absf(total(sim)-mass)<.00001,"Storage is bounded and cannot create material when full")
	var report: Dictionary=sim._emit_pheromone(parent).report
	check(report.defended and not report.hostile,"A filled sac appears as defense in an immutable emitted cue, without a new sense or aggression")
	sac.stored_toxin=0
	check(report.defended and not sim._emit_pheromone(parent).report.defended,"Old cues retain their emission-time defense while new cues see an emptied sac")
	sac.stored_toxin=2
	var restored=Codec.new().restore(Codec.new().capture(sim))
	check(restored.player.organs[-1].stored_toxin==2 and is_equal_approx(restored.player.organic_mass(),parent.organic_mass()),"Actual stored contents survive a checkpoint exactly")
	check(parent.internal_organ("toxin_sac") and parent.organ_local_position(sac).length()<parent.radius,"The sac is placed inside the cell")
	var clone=Sim.Cell.clone_state(parent);clone.energy=0;clone.update_power_state();clone.organs[-1].stored_toxin=0
	var biomass: float=clone.biomass;Sac.fill(clone,10)
	check(is_equal_approx(clone.organs[-1].stored_toxin,.1) and clone.energy==0 and clone.biomass<biomass,"Low ATP gives quarter filling without negative ATP")
	clone.biomass=12;biomass=clone.organs[-1].stored_toxin;Sac.fill(clone,100)
	check(clone.organs[-1].stored_toxin==biomass,"Filling leaves the operating biomass floor")
	var recycle=Sim.Cell.clone_state(parent);mass=recycle.organic_mass();var debris: float=recycle.recycle(recycle.organs.size()-1)
	check(absf(recycle.organic_mass()+debris-mass)<.00001 and recycle.count("toxin_sac")==0,"Recycling safely dismantles every stored unit through ordinary salvage and debris")
	mass=total(sim);sim._die(parent)
	var toxins: Array=sim.particle_snapshots().filter(func(packet):return packet.alive and packet.kind==sim.TOXIN)
	check(toxins.size()==25 and is_equal_approx(toxins.reduce(func(amount,packet):return amount+packet.amount,0.0),2),"Death emits exactly the paid contents as bounded ordinary toxin parcels")
	check(absf(total(sim)-mass)<.0001,"Stored toxin is not duplicated into nutrient lysis")
	var count: int=sim.particle_count();sim._die(parent)
	check(sim.particle_count()==count,"Repeated death cannot release a second toxin cloud")
	var victim=Sim.Cell.new(700,toxins[0].p);var family=Sim.Cell.new(701,toxins[0].p);family.lineage=parent.lineage_id()
	sim.cells=[victim,family];sim.camera_views=[Vector4(parent.position.x,parent.position.y,1500,1000)];sim.grid.rebuild(sim.particles);sim._toxin_contacts()
	check(victim.health<100 and family.health==100,"An overlapping toxin parcel is consumed by one contacted cell only")
	sim.cells=[family];sim.spawn_particle(sim.TOXIN,family.position,Vector2.ZERO,.1,parent.id);sim.grid.rebuild(sim.particles);sim._toxin_contacts()
	check(family.health<100,"A separate actual toxin contact harms the emitting lineage too")
	var bound=Sim.Cell.new(800);bound.add_organ("feeding",0,"graze",false)
	var surface=preload("res://scripts/surface_chemistry.gd")
	check(surface.bind(bound,sim.TAG,.03,0) and surface.bind(bound,sim.PORE_SUBUNIT,.0375,0),"Free pore pieces still bind into existing membrane assembly")
	var complexes: Array=bound.surface_complexes.duplicate(true)
	check(Sim.Catalog.decay(sim.TAG)==.8 and Sim.Catalog.decay(sim.PORE_SUBUNIT)==.8,"Both free pore species share the new short lifetime")
	check(bound.surface_complexes==complexes,"Free-particle lifetime does not rewrite bound complexes")
	queued_division()
	await ui()
	print("DIVISION ACCESS: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
func ui() -> void:
	var game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false;root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
	game.world.habitat_geometry.enabled=false;game.world.cells=[game.world.player]
	game.world.evolution.sandbox=true;game.build_open=true
	for mobile in [false,true]:
		game.touch_zoom.enabled=mobile;game.cell_ui.open_context({"kind":"bud"})
		check(game.cell_ui.choices.map(func(button):return button.symbol)==["Divide","Invest","Family"],"Desktop and mobile bud expose direct division, Investment and Family")
		game.cell_ui.choices[1].pressed.emit()
		check(game.cell_ui.investment_picker.visible and game.cell_ui.investment_picker.cards.size()==3,"Investment opens all three illustrated strategies from the bud")
		game.cell_ui.open_context({"kind":"nucleus"})
		var investment: Array=game.cell_ui.choices.filter(func(button):return button.caption=="Investment")
		check(not investment.is_empty(),"Nucleus keeps direct Investment access")
	var sim=game.world;funded(sim);sim.remote_client=true
	sim.remote_division={"cell":sim.player.id,"ready":false,"progress":1.0,"reason":"The pond is full."}
	game.cell_ui.open_context({"kind":"bud"});game.cell_ui.sync(0)
	check(game.cell_ui.choices[0].affordable and game.cell_ui.choices[0].description=="The pond is full." and game.cell_ui.choices[0].radial_progress==1 and not game.cell_ui.choices[0].progress_ready,"A partial browser camera uses authoritative readiness, not its local cell count")
	# Readiness may arrive before the interpolated body snapshot catches up.
	sim.remote_division["queued"]=true;sim.remote_division["automatic"]=true
	var commands: Array=[]
	sim.command_sink=func(action,args):commands.append({"action":action,"args":args})
	game.cell_ui.open_context({"kind":"division"})
	game.cell_ui.choices[0].pressed.emit();game.cell_ui.choices[1].pressed.emit()
	check(commands.size()==2 and commands[0].action=="division_policy" and not commands[0].args.automatic and commands[1].action=="division_request" and not commands[1].args.active,"Browser toggle/cancel commands use the same authoritative mode shown by the buttons, even before body playback catches up")
	sim.command_sink=Callable()
	sim.remote_division.cell+=100
	check(not sim.division_status().ready and sim.division_status().reason.contains("Checking"),"A previous selected body's readiness cannot enable a new body's division")
	sim.remote_client=false;game.queue_free();await process_frame


func queued_division() -> void:
	var sim=fixture();sim.automatic_reproduction=true;var parent=sim.player
	parent.brood_mass=0;parent.brood_energy=0;parent.automatic_division=true
	var ap: int=parent.ap;var mass: float=total(sim);var random: int=sim.rng.state
	check(sim.edit("division_request",{"active":true}) and parent.division_requested and not parent.automatic_division,"An unfunded manual request queues exactly one birth and supersedes continuous auto")
	check(sim.cells.size()==1 and parent.ap==ap and total(sim)==mass and sim.rng.state==random,"Queuing alone spends/grants no material, AP or randomness")
	var restored=Codec.new().restore(Codec.new().capture(sim))
	check(restored.player.division_requested and not restored.player.automatic_division,"A queued single birth survives checkpoint and account-visible state restore")
	funded(restored);var owner=restored.player
	restored._step_reproduction()
	check(restored.cells.size()==2 and not owner.division_requested and not owner.automatic_division and restored.evolution.offspring_id==restored.cells[-1].id,"The next funded safe opportunity commits once and clears its request")
	var daughter=restored.cells[-1]
	check(not daughter.division_requested and not daughter.automatic_division and owner.ap==ap+1 and daughter.ap==1,"A one-shot request is not inherited and awards exactly1AP per body")
	funded(restored);owner.reproduction_retry_at=0;restored._step_reproduction()
	check(restored.cells.size()==2 and owner.ap==ap+1,"Fresh funding cannot cause another automatic birth after the one-shot")
	check(restored.request_division() and restored.cells.size()==3 and not owner.division_requested,"An already-ready manual request divides immediately without arming another birth")
	owner.brood_mass=0;owner.brood_energy=0
	check(restored.request_division() and restored.request_division(false) and not owner.division_requested,"The player can cancel a waiting request without changing resources")
	check(restored.request_division() and restored.edit("division_policy",{"automatic":true}) and owner.automatic_division and not owner.division_requested,"Choosing continuous Auto divide replaces a pending one-shot")
	check(not restored.edit("division_request",{"active":"true"}),"Untrusted request types are rejected")
	# Old checkpoints do not gain an unsolicited division request.
	var graph=Codec.new().capture(sim)
	for record in graph.objects:
		if record.kind=="cell":record.fields.erase("division_requested")
	var legacy=Codec.new().restore(graph)
	check(not legacy.player.division_requested,"An older cell restores with no queued birth")

	# A funded but crowded request waits rather than disappearing.
	sim=fixture();sim.automatic_reproduction=true;parent=sim.player;funded(sim)
	var blocker=Sim.Cell.new(999,parent.position);blocker.body=10000000;blocker.update_geometry();blocker.membrane=Sim.Cell.Membrane.new(blocker.radius);sim.cells.append(blocker)
	check(sim.request_division() and parent.division_requested and sim.cells.size()==2,"A funded but physically blocked manual request remains queued")
	sim._step_reproduction();sim.cells.erase(blocker);sim.time+=.6;sim._step_reproduction()
	check(sim.cells.size()==2 and not parent.division_requested,"The queued birth commits once when the obstruction clears")

	sim=fixture();sim.player.division_requested=true;sim.begin_build()
	var editing=sim.player;var original=sim.build_original
	check(sim.request_division(false) and sim.player==editing and sim.build_original==original and not editing.division_requested,"Cancellation preserves the current local edit transaction and body identity")
