extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Client=preload("res://scripts/network/network_client.gd")
const Host=preload("res://scripts/network/world_host.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
var checks:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func fixture():
	var sim=Sim.new(29,0,false);sim.server_mode=true
	sim.cells=[sim.player];sim.particles=[];sim.player.organs.clear()
	sim.habitat_geometry=sim.Habitat.new(29,sim.cells);sim.habitat_geometry.enabled=false
	sim.Lifecycle.migrate(sim);sim.player.reproduction_retry_at=0
	return sim
func run() -> void:
	var sim=fixture();var cell=sim.player;cell.biomass=100
	check(sim.install("feeding",0) and cell.biomass==100,"First place is free and allows an oral groove")
	check(sim.install("photosynthesis",PI) and cell.biomass==100,"Second place is free")
	check(cell.membrane.skeleton.links.any(func(link):return link.get("oral",false) and link.tension==1),"Optional oral groove has a full-tension tether")
	check(sim.install("propulsion",1) and cell.biomass==92,"Third organ uses biomass, without AP")
	var amount=cell.biomass
	check(sim.remove(0) and cell.biomass==amount,"Free oral groove returns no biomass")
	check(not is_finite(cell.membrane.oral_angle) and not cell.membrane.skeleton.links.any(func(link):return link.get("oral",false)),"Removing a groove removes the mouth and tether")
	check(sim.remove(1) and cell.biomass==amount+4,"Paid flagellum returns half its actual biomass")
	amount=cell.biomass
	check(sim.install("feeding",0) and cell.biomass==amount,"Reabsorption reopens a free place")
	cell.biomass=200;cell.energy=100;cell.reproduction_retry_at=0
	var before=cell.biomass;var body=cell.body;var organs=cell.organs.size()
	check(sim.Lifecycle.reproduce(sim,cell,sim.lineage,"mitosis"),"Mitosis commits directly")
	var child=sim.cells[-1]
	check(cell.biomass==before*.5 and child.biomass==before*.5-30 and cell.body==body,"Mitosis splits biomass budget without duplicating the body")
	check(cell.organs.size()==organs and child.organs.size()==2,"Parent keeps build; daughter receives the two starter organs")
	check(cell.energy==40 and child.energy==40,"Mitosis pays20ATP then splits the rest")
	check(not sim.Lifecycle.reproduce(sim,cell,sim.lineage,"budding") and not sim.Lifecycle.quote(sim,child,"budding").ready,"Both birth modes and newborns respect one minute")
	sim.time=60;cell.biomass=100;cell.energy=100
	check(sim.Lifecycle.reproduce(sim,cell,sim.lineage,"budding"),"Budding becomes available after cooldown")
	check(cell.biomass==58 and cell.energy==40 and sim.cells[-1].biomass==12,"Budding directly funds a minimal daughter")
	var restored=Codec.new().restore(Codec.new().capture(sim))
	check(restored.cells[0].reproduction_retry_at==120,"Reproduction cooldown survives a checkpoint")
	var spare=Sim.Cell.new(503,cell.position);spare.lineage=cell.lineage_id();sim.cells.append(spare)
	check(sim._birth_position(cell,spare).is_finite(),"Crowded birth positions have a finite collision-resolved fallback")
	cell.brood_mass=20;cell.brood_energy=30;cell.lifecycle_version=0
	var mass=cell.biomass;var energy=cell.energy
	sim.Lifecycle.migrate(sim);sim.Lifecycle.migrate(sim)
	check(cell.biomass==mass+20 and cell.energy==energy+30 and cell.brood_mass==0 and cell.brood_energy==0,"Old reserves return exactly once")
	cell.energy=0;cell.biomass=10
	sim._metabolize(cell,1)
	check(cell.energy>0 and cell.biomass<10 and cell.chemistry.amount("food")==0,"Emergency reserves make ATP directly without a regenerative food loop")
	cell.unattended_protected=true;cell.health=1
	check(cell.damage(100,0)==0 and cell.health==1,"Protected favorite rejects combat damage")
	var hunter=Sim.Cell.new(902);hunter.biomass=100;hunter.energy=0
	for kind in ["hunting","propulsion","poreforming"]:hunter.add_organ(kind,0,"graze",false)
	for i in 120:sim._metabolize(hunter,.25)
	check(hunter.energy>0 and hunter.biomass<100 and hunter.health==100,"Leafless Hunter can pay maintenance from reserves during a food gap")
	check(not sim.evolution.terminal() and not sim.evolution.forecast().contains("crisis"),"Persistent progression has no crisis ending")
	await controls()
	roles_and_presence()
	print("LIFECYCLE: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)


func roles_and_presence() -> void:
	var sim=fixture();var cell=sim.player
	cell.add_organ("feeding",0,"graze",false);cell.add_organ("cilia",1,"graze",false)
	check(cell.synergy()=="grazer","Groove and cilia automatically form a Grazer")
	cell.organs.clear()
	for kind in ["hunting","propulsion","poreforming"]:cell.add_organ(kind,0,"graze",false)
	check(cell.synergy()=="hunter" and not cell.accept_surface(sim.TAG,.03,0,cell.id),"Hunter anatomy rejects its own pore particles")
	check(cell.accept_surface(sim.TAG,.03,0,991),"Hunter still receives another cell's pore particles")
	cell.organs.clear()
	for kind in ["photosynthesis","photosynthesis","mitochondrion"]:cell.add_organ(kind,0,"graze",false)
	check(cell.synergy()=="producer","Two leaves and respiration automatically form a Producer")
	var host=Host.new();host.world=sim
	host.accounts={"fixture":{"root":cell.lineage_id(),"selected":cell.id,"favorite_name":"Ada"}}
	host._update_favorites()
	check(cell.favorite and cell.favorite_name=="Ada" and cell.unattended_protected,"Offline last-controlled cell is named and protected")
	host.peers={1:{"account":"fixture","presence":"active"}};host._update_favorites()
	check(not cell.unattended_protected,"Active account restores vulnerability")
	host.peers[1].presence="paused";host._update_favorites()
	check(cell.unattended_protected,"Pause protects the favorite")
	host.peers[2]={"account":"fixture","presence":"active"};host._update_favorites()
	check(not cell.unattended_protected,"Another active session prevents unattended protection")
	host.peers.clear();host._update_favorites()
	var restored=Codec.new().restore(Codec.new().capture({"world":sim,"accounts":host.accounts}))
	check(restored.accounts.fixture.favorite_id==cell.id and not restored.world.player.unattended_protected,"Favorite identity persists; protection is derived from authenticated sessions")
	host.free()
	cell.unattended_protected=false;cell.body=30;cell.biomass=4000
	var before=cell.organic_mass();sim.Lifecycle.physiology(sim,cell,1)
	check(cell.biomass<4000 and cell.holes.any(func(h):return h.get("stress",false)),"Overfilled cells leak gradually through a visible stress hole")
	var mass=sim.particles.reduce(func(total,p):return total+p.amount*sim.Catalog.material(p.kind),0.0)
	check(absf(cell.organic_mass()+mass-before)<.00001 and sim.particle_count()==1,"Stress leak is one finite coalesced parcel, with conserved material")
	var investing=fixture();var investor=investing.player;investor.body=500;investor.biomass=100;investor.update_geometry()
	investor.add_organ("feeding",0,"graze",false);investing.investment.cells[investor.id]="producer"
	investing.step_autonomous_builds();var count=investor.organs.size()
	check(count==2 and investor.investment_retry_at==60,"Opted-in investment makes one ordinary purchase per minute")
	investing.time=59;investing.step_autonomous_builds()
	check(investor.organs.size()==count,"Investment cannot buy again before the cooldown")
	var saved=Codec.new().restore(Codec.new().capture(investing))
	check(saved.player.investment_retry_at==60,"Investment cooldown survives a checkpoint")
	var model=Sim.Cell.new(991);model.lineage=cell.lineage_id();model.add_organ("feeding",0,"graze",false);sim.cells.append(model)
	check(sim.Investment.save_template(sim,"lineage",model.id),"Investment snapshots a living relative")
	model.add_organ("toxin",0,"graze",false)
	check(sim.investment.templates[cell.lineage_id()].size()==1,"Later edits do not change the remembered build")
	cell.chemistry.emit("food",8,Vector2(20,0),-1,-1,144);cell.chemistry.emit("oxygen",3,Vector2(20,0))
	var child=Sim.Cell.new(555)
	child.chemistry.partition(cell.chemistry,.5)
	check(is_equal_approx(child.substrate,4) and is_equal_approx(cell.substrate,4) and is_equal_approx(child.oxygen+cell.oxygen,3),"Birth partitions finite contents without duplication")
	check(is_equal_approx(child.raw_fuel+cell.raw_fuel,144),"Birth preserves food fuel")

func controls() -> void:
	var game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false;root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
	game.build_open=true;var sim=game.world;sim.server_mode=true
	for mobile in [false,true]:
		game.touch_zoom.enabled=mobile
		var cell=sim.player;cell.organs.clear();cell.biomass=100;cell.update_geometry()
		for kind in ["feeding","photosynthesis","propulsion"]:sim.install(kind,1)
		var organ=cell.organs[-1];var before=cell.biomass
		game.cell_ui.open_context({"kind":"organ","id":organ.id})
		var button=game.cell_ui.choices.filter(func(choice):return choice.caption=="Reabsorb")[0]
		cell.organs=cell.organs.duplicate(true);button.pressed.emit();button.pressed.emit()
		check(cell.organ_by_id(organ.id).is_empty() and cell.biomass==before+4,"Desktop/mobile reabsorption resolves the stable ID once after a snapshot")
	game.queue_free();await process_frame
