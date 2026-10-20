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
	check(cell.membrane.skeleton.links.any(func(link):return link.get("oral",false) and link.tension==1 and link.b.kind=="center"),"Optional oral groove has a full-tension tether fixed at the cell center")
	check(sim.install("propulsion",1) and cell.biomass==90,"Third organ uses biomass, without AP")
	var amount=cell.biomass
	check(sim.remove(0) and cell.biomass==amount,"Free oral groove returns no biomass")
	check(not is_finite(cell.membrane.oral_angle) and not cell.membrane.skeleton.links.any(func(link):return link.get("oral",false)),"Removing a groove removes the mouth and tether")
	check(sim.remove(1) and cell.biomass==amount+5,"Paid flagellum returns half its actual biomass")
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
	var legacy=fixture();legacy.player.lifecycle_version=0;legacy.player.ap=9;legacy.player.brood_mass=20;legacy.player.brood_energy=30
	var retention=preload("res://scripts/network/cell_retention.gd")
	var original={"world_id":"fixture","tick":legacy.revision,"graph":Codec.new().capture(legacy)}
	var reloaded=Codec.new().restore(original.graph)
	var recovered={"world_id":"fixture","tick":reloaded.revision,"graph":Codec.new().capture(reloaded)}
	check(retention.compare(retention.manifest(original),retention.manifest(recovered)).ok,"Strict startup retention validates the intact legacy save before game-rule migration")
	reloaded.step(.01)
	check(reloaded.player.lifecycle_version==1 and reloaded.player.ap==0 and reloaded.player.brood_mass==0 and reloaded.player.brood_energy==0,"The first authority tick retires AP and returns old reserves")
	await controls()
	roles_and_presence()
	producer_wall()
	synergy_shapes()
	build_prices()
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
	var copying=fixture();var copier=copying.player;copier.biomass=100
	copier.add_organ("feeding",0,"graze",false)
	copying.Investment.save_template(copying,"lineage",copier.id)
	copying.Investment.template_decision(copying,copier)
	copier.add_organ("protection",1,"graze",false)
	var next=copying.Investment.template_decision(copying,copier)
	check(next.get("action","")!="remove","Completed exemplar build can expand without reabsorbing its own fallback purchases")
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
		check(cell.organ_by_id(organ.id).is_empty() and cell.biomass==before+5,"Desktop/mobile reabsorption resolves the stable ID once after a snapshot")
	game.queue_free();await process_frame


func producer_wall() -> void:
	var sim=fixture();var cell=sim.player
	for kind in ["photosynthesis","photosynthesis","mitochondrion"]:cell.add_organ(kind,0,"graze",false)
	check(cell.synergy()=="producer" and cell.membrane.cell_wall,"Mouthless Producer anatomy forms a wall")
	var restored=Codec.new().restore(Codec.new().capture(sim))
	check(restored.player.membrane.cell_wall and restored.player.membrane.points==cell.membrane.points,"Checkpoint restores the anatomy-derived wall without rewriting saved shape")
	var a=Sim.Cell.clone_state(cell);var b=Sim.Cell.clone_state(cell)
	a.membrane.native_constraints=false;a.membrane.native_compression=false;a.membrane.native_outline=false
	for i in 120:
		for c in [a,b]:c.membrane.step(1.0/60,c.radius,Vector2(200,-80),i/60.0)
	var ratio=a.visible_support(PI/4)/a.visible_support(0)
	check(ratio>1.20 and ratio<1.4,"Producer wall has a boxy rounded-square outline")
	var area=preload("res://tests/paramecium.gd").area(a)
	check(absf(area-cell.membrane.COUNT*cell.radius*cell.radius*sin(TAU/cell.membrane.COUNT)*.5)<.01,"Boxy walls preserve represented tissue area")
	print("WALL_PARITY ",{"distance":a.membrane.points[0].distance_to(b.membrane.points[0]),"ratio":ratio})
	check(a.membrane.points[0].distance_to(b.membrane.points[0])<.01,"Native and reference wall constraints agree")
	var soft=Sim.Cell.clone_state(a);soft.membrane.cell_wall=false
	var hard_before=a.support(0);var soft_before=soft.support(0)
	a.membrane.compress(0,cell.radius*.06,cell.radius);soft.membrane.compress(0,cell.radius*.06,cell.radius)
	print("WALL_DENT ",{"hard":hard_before-a.support(0),"soft":soft_before-soft.support(0),"radius":cell.radius})
	check(hard_before-a.support(0)<(soft_before-soft.support(0))*.25,"The wall resists contact dents more strongly than a soft membrane")
	cell.add_organ("feeding",1,"graze",false)
	check(cell.synergy()=="" and not cell.membrane.cell_wall,"Any installed mouth disqualifies a Producer wall")
	var mouth=cell.organs[-1]
	sim.investment.cells[cell.id]="producer"
	var decision=sim.Investment.decision(sim,cell)
	check(decision.get("action","")=="remove" and decision.id==mouth.id,"Opted-in Producer investment reabsorbs its mouth after establishing photosynthesis")
	cell.recycle(cell.organs.find(mouth))
	check(cell.membrane.cell_wall and not cell.membrane.skeleton.links.any(func(link):return link.get("oral",false)),"Reabsorbing the mouth removes its center tether and restores the wall")


func build_prices() -> void:
	var sim=fixture();var cell=sim.player;cell.body=100000;cell.biomass=10000;cell.update_geometry()
	for expected in [0,0,10,10,20,30,50,80]:
		var before=cell.biomass;var material=cell.organic_mass();var external=sim.external_input
		check(cell.construction_price("mitochondrion")==expected and sim.install("mitochondrion",0),"Build price follows two free places then Fibonacci times10")
		check(cell.biomass==before-expected and is_equal_approx(cell.organic_mass()-material,sim.external_input-external),"Tier price is paid once and construction material is accounted for")
	var next=cell.construction_price("propulsion")
	check(sim.install("hunting",1) and cell.construction_price("propulsion")==next,"Free receptors do not advance the price sequence")
	var saved=Codec.new().restore(Codec.new().capture(sim))
	check(saved.player.construction_price("propulsion")==next,"A saved cell retains its next quote without a separate purchase counter")
	var organ=cell.organs[6]
	var paid=organ.paid_material
	check(sim.remove(cell.organs.find(organ)) and cell.construction_price("propulsion")==80 and cell.biomass==saved.player.biomass+paid*.5,"Reabsorption lowers the next tier and returns half the actual paid biomass")

	cell.lost_organs.append(organ.duplicate(true))
	var quote=cell.construction_price(organ.kind);var before=cell.biomass
	check(sim.restore(organ.id) and cell.biomass==before-quote and cell.organs[-1].paid_material==quote and cell.construction_refund(cell.organs[-1])==quote*.5,"Restoring lost anatomy uses the same current tier and records its real payment")

func synergy_shapes() -> void:
	var ShapeArt=preload("res://scripts/synergy_art.gd")
	var Portrait=preload("res://scripts/cell_portrait.gd")
	var Retention=preload("res://scripts/network/cell_retention.gd")
	for mouth_angle in [0.0,.7,-2.1]:
		var sim=fixture();var hunter=sim.player;hunter.body=120
		for kind in ["feeding","hunting","propulsion","toxin"]:hunter.add_organ(kind,0,"graze",false)
		var mouth=hunter.organs.filter(func(organ):return organ.kind=="feeding")[0]
		mouth.a=mouth_angle;hunter.update_geometry()
		var axis: float=hunter.membrane.hunter_angle
		check(absf(wrapf(axis-mouth.a,-PI,PI)-PI/2)<.00001,"Hunter front is perpendicular to its oral groove")
		var ref=Sim.Cell.clone_state(hunter);ref.membrane.native_constraints=false;ref.membrane.native_outline=false
		for tick in 120:
			for body in [hunter,ref]:body.membrane.step(1.0/60,body.radius,Vector2(90,-60),tick/60.0)
		var width=hunter.visible_support(axis+PI/2)+hunter.visible_support(axis-PI/2)
		var length=hunter.visible_support(axis)+hunter.visible_support(axis+PI)
		check(length/width>1.75 and hunter.visible_support(axis)>hunter.visible_support(axis+PI)*1.2,"Hunter is elongated with a longer pointed front")
		var area=preload("res://tests/paramecium.gd").area(hunter)
		check(absf(area-hunter.membrane.COUNT*hunter.radius*hunter.radius*sin(TAU/hunter.membrane.COUNT)*.5)<.05,"Hunter silhouette preserves tissue area")
		var error:=0.0
		for i in hunter.membrane.COUNT:error=maxf(error,hunter.membrane.points[i].distance_to(ref.membrane.points[i]))
		check(error<.02,"Native/reference Hunter shape constraints agree")
		var original={"world_id":"shape","tick":sim.revision,"graph":Codec.new().capture(sim)}
		var restored=Codec.new().restore(original.graph)
		var recovered={"world_id":"shape","tick":sim.revision,"graph":Codec.new().capture(restored)}
		check(Retention.compare(Retention.manifest(original),Retention.manifest(recovered)).ok and is_equal_approx(restored.player.membrane.hunter_angle,axis),"Checkpoint derives Hunter axis without changing saved points or anatomy")
		var model=Portrait.capture(hunter)
		check(model.synergy.role=="hunter" and model.synergy.spine[-1].length()>hunter.radius,"Portrait includes the live membrane's supported pointed front")
		hunter.recycle(hunter.organs.find(mouth))
		var receptor=hunter.organs.filter(func(organ):return organ.kind=="hunting")[0]
		check(hunter.synergy()=="hunter" and hunter.membrane.hunter_angle==receptor.a,"Mouthless Hunter uses its receptor as the anatomical front")
		hunter.organs.filter(func(organ):return organ.kind=="toxin")[0].hp=0;hunter.update_geometry()
		check(not is_finite(hunter.membrane.hunter_angle),"Losing Hunter eligibility removes the shape scaffold")
	var sim=fixture();var grazer=sim.player
	grazer.add_organ("feeding",0,"graze",false);grazer.add_organ("cilia",PI,"graze",false);grazer.update_geometry()
	for i in 60:grazer.membrane.step(1.0/60,grazer.radius,Vector2.ZERO,i/60.0)
	var snapshot=Codec.new().capture(sim)
	var art=ShapeArt.capture(grazer);var portrait=Portrait.capture(grazer)
	check(art.roots.size()==10 and art.normals.size()==10 and portrait.synergy.roots==art.roots,"Grazers and their portraits have exactly ten shared follicle roots")
	var clear:=true;var within:=true
	for i in 10:
		clear=clear and absf(wrapf(art.roots[i].angle()-grazer.membrane.oral_angle,-PI,PI))>.5
		within=within and ShapeArt.hair(art,i,grazer.radius,grazer.age)[-1].length()<portrait.extent
	check(clear and within,"Follicles leave the mouth clear and portrait bounds include every hair")
	var after=Codec.new().capture(sim)
	check(Retention.digest(Retention.canonical(snapshot.root,snapshot.objects))==Retention.digest(Retention.canonical(after.root,after.objects)),"Synergy illustrations only warm geometry caches, without changing biology or random state")
	grazer.organs[-1].hp=0;grazer.update_geometry()
	check(ShapeArt.capture(grazer).roots.is_empty(),"Losing Grazer eligibility removes the decorative hairs")
