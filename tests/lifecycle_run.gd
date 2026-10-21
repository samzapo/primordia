extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Client=preload("res://scripts/network/network_client.gd")
const Host=preload("res://scripts/network/world_host.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
var checks:=0
var failures:=0
class GrowthWorld:
	extends "res://scripts/simulation.gd"
	var illumination:=1.0
	func light_at(_at: Vector2) -> float:return illumination
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
	if "--parasite-balanced" in OS.get_cmdline_user_args():
		parasite_balanced()
		await parasite_picker()
		if "--gpu" in OS.get_cmdline_user_args():await parasite_gpu()
		print("PARASITE_BALANCED: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1);return
	if "--synergy-priority" in OS.get_cmdline_user_args():
		synergy_anatomy()
		synergy_investment()
		print("SYNERGY_INVESTMENT: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1);return
	if "--smooth-motion" in OS.get_cmdline_user_args():
		smooth_motion_and_venting()
		print("SMOOTH_MOTION: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1);return
	smooth_motion_and_venting()
	investment_growth()
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
	for kind in ["feeding","hunting","propulsion","poreforming"]:hunter.add_organ(kind,0,"graze",false)
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
	for kind in ["feeding","hunting","propulsion","poreforming"]:cell.add_organ(kind,0,"graze",false)
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
	check(absf(cell.organic_mass()+mass-before)<.00001 and sim.particle_count()==2,"Surplus vent emits finite nutrient and waste parcels with conserved material")
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

# Run the actual paid policies, chemistry and birth transactions against finite
# local inputs. This isolates investment balance from wandering/contact/combat.
func investment_growth() -> void:
	for scenario in [{"role":"producer","light":1.0,"food":0.0},{"role":"producer","light":.02,"food":0.0},{"role":"producer","light":.02,"food":0.0,"bloated":true},{"role":"hunter","light":1.0,"food":.15},{"role":"grazer","light":1.0,"food":.15}]:
		var role: String=scenario.role
		var sim=GrowthWorld.new(29,0,false);sim.server_mode=true;sim.cells=[sim.player];sim.player.organs.clear();sim.particles.clear()
		sim.illumination=scenario.light;sim.habitat_geometry=sim.Habitat.new(29,sim.cells);sim.habitat_geometry.enabled=false
		var parent=sim.player
		parent.body=30;parent.biomass=18;parent.energy=60;parent.update_geometry()
		parent.add_organ("feeding",0,"graze",false);parent.add_organ("photosynthesis",PI,"graze",false)
		if scenario.get("bloated",false):
			parent.body=120;parent.biomass=.4;parent.energy=4.5;parent.update_geometry()
			for kind in ["protection","protection","regenerative","neutralizing","toxin_sac"]:parent.add_organ(kind,1,"graze",false)
		sim.investment.cells[parent.id]=role
		var first_birth:=-1.0;var purchases:=0
		var previous: int=parent.next_organ_id
		for tick in 2400:
			sim.time+=.5;sim.revision+=1
			for cell in sim.cells.duplicate():
				cell.age+=.5
				# Each parcel is consumed through the existing finite chemistry. Record its
				# material source; no ATP or biomass balance is assigned during the run.
				for organ in cell.organs:
					if organ.kind=="photosynthesis":
						cell.chemistry.emit("carbon",.35,cell.local_point(organ.a)*.72)
						sim.external_input+=.35
				if scenario.food>0:
					cell.chemistry.emit("food",scenario.food,Vector2.ZERO,-1,-1,scenario.food*18.0)
					cell.chemistry.emit("oxygen",.5,Vector2.ZERO);sim.external_input+=scenario.food
				sim._photosynthesize(cell,.5);sim._metabolize(cell,.5)
				for organ in cell.organs:cell.spend_energy(.5*cell.organ_upkeep(organ),organ,"fixture_operation")
				cell.heal(.5);cell.chemistry.excrete(sim,cell,.5)
			sim.step_autonomous_builds();sim.Lifecycle.step(sim)
			if parent.next_organ_id>previous:
				purchases+=parent.next_organ_id-previous;previous=parent.next_organ_id
			if sim.lineage.births>0 and first_birth<0:first_birth=sim.time
			if sim.cells.size()>=4:break
			if tick%20==0:sim._compact_particles();sim.grid.rebuild(sim.particles)
		print("INVESTMENT_GROWTH ",{"role":role,"light":scenario.light,"food":scenario.food,"bloated":scenario.get("bloated",false),"seconds":sim.time,"first_birth":first_birth,"births":sim.lineage.births,"living":sim.cells.size(),"purchases":purchases,"biomass":parent.biomass,"ATP":parent.energy,"organs":parent.organs.map(func(o):return o.kind)})
		check(first_birth>0 and first_birth<900 and sim.cells.size()>=2,"Unattended "+role+" grows and reproduces through paid chemistry and investment")
		check(sim.cells.all(func(c):return c.health>0 and is_finite(c.biomass) and is_finite(c.energy) and sim.Investment.strategy(sim,c)==role),"Growing "+role+" family retains finite living cells")
		check(sim.cells.size()<=12 and sim.cells.all(func(c):return c.reproduction_retry_at<=sim.time+60),"Growth preserves family cap and bounded birth cooldown")
	var defaults=fixture()
	check(defaults.Investment.DEFAULT=="balanced" and defaults.Investment.strategy(defaults,defaults.player)==defaults.Investment.balanced_path(defaults,defaults.player),"An unchosen player family defaults to the stable Balanced mix")
	defaults.Investment.set_strategy(defaults,"lineage","manual")
	var saved=Codec.new().restore(Codec.new().capture(defaults))
	check(saved.Investment.strategy(saved,saved.player)=="manual" and saved.Investment.owned_settings(saved,saved.player.lineage_id()).lineages.values()==["manual"],"Explicit Manual survives checkpoint and owner settings")
	var cell=saved.player;cell.biomass=90;cell.energy=100
	cell.add_organ("feeding",0,"graze",false);cell.add_organ("photosynthesis",PI,"graze",false)
	cell.add_organ("photosynthesis",1,"graze",false);cell.add_organ("mitochondrion",0,"graze",false)
	saved.investment.cells[cell.id]="producer"
	check(not saved.Investment.can_purchase(saved,cell,"protection") and cell.biomass==90,"Optional purchases cannot consume the next birth's biomass")
	cell.biomass=200;cell.energy=60
	check(not saved.Investment.can_purchase(saved,cell,"protection"),"Optional support needs ATP headroom for its own upkeep")
	cell.energy=120
	check(saved.Investment.can_purchase(saved,cell,"protection"),"Surplus resources still allow optional investment")
	cell.recycle(0);cell.add_organ("toxin_sac",0,"graze",false)
	var excess: int=cell.organs[-1].id;cell.energy=4;cell.biomass=.4
	var recovery: Dictionary=saved.Investment.decision(saved,cell)
	check(recovery.get("action","")=="remove" and recovery.id==excess,"Underpowered Producer sheds excess support instead of expanding")
	cell.unattended_protected=true
	check(saved.Investment.shed_support(cell,"producer").is_empty(),"Unattended favorite keeps its anatomy during energy shortage")

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
	for mouth_angle in [0.0,.7,-2.1,-PI/2+PI/28]:
		var sim=fixture();var hunter=sim.player;hunter.body=120
		for kind in ["feeding","hunting","propulsion","toxin"]:hunter.add_organ(kind,0,"graze",false)
		var mouth=hunter.organs.filter(func(organ):return organ.kind=="feeding")[0]
		mouth.a=mouth_angle;hunter.update_geometry()
		var axis: float=hunter.membrane.hunter_angle
		check(absf(wrapf(axis-mouth.a,-PI,PI)-PI/2)<.00001,"Hunter front is perpendicular to its oral groove")
		var ref=Sim.Cell.clone_state(hunter);ref.membrane.native_constraints=false;ref.membrane.native_outline=false
		for tick in 120:
			for body in [hunter,ref]:body.membrane.step(1.0/60,body.radius,Vector2(90,-60),tick/60.0)
		var pronounced:=0;var curve: PackedVector2Array=hunter.membrane.outline()
		for i in curve.size():
			var reach:=curve[i].length()
			if reach>hunter.radius*1.25 and reach>curve[posmod(i-1,curve.size())].length() and reach>curve[(i+1)%curve.size()].length():pronounced+=1
		check(pronounced==6,"Hunter has exactly six pronounced pointed membrane projections")
		var concave:=true;var supported:=true
		for i in 6:
			var tip: float=axis+i*TAU/6
			concave=concave and hunter.visible_support(tip)>hunter.visible_support(tip+PI/6)*1.7
			supported=supported and absf(hunter.support(hunter.angle+tip)-hunter.visible_support(tip))<hunter.radius*.01
		check(concave and supported,"Concave spans separate six tips present in both collision support and artwork")
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
		check(model.synergy.role=="hunter" and model.synergy.spine.size()==12 and model.synergy.spine[-1].length()>hunter.radius,"Live portraits include all six center-to-tip support strands")
		hunter.recycle(hunter.organs.find(mouth))
		check(hunter.synergy()=="" and not is_finite(hunter.membrane.hunter_angle),"Removing the required oral groove ends Hunter synergy and its shape scaffold")
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

func smooth_motion_and_venting() -> void:
	# Actual shared body integrator, without chemistry/ecology or a speed benchmark.
	for dt in [1.0/30,1.0/60,1.0/120]:
		var sim=fixture();var cell=sim.player
		cell.body=70;cell.biomass=20;cell.energy=100;cell.angle=0;cell.angular_velocity=0
		cell.velocity=Vector2.ZERO;cell.activity=1;cell.add_organ("propulsion",0,"graze",false)
		cell.target=Vector2.RIGHT;cell.facing=Vector2.RIGHT;cell.target_mouth=0
		sim.fluid.velocity.fill(Vector2.ZERO)
		var unchanged=sim.fluid.velocity.duplicate();var state=sim.rng.state
		var smooth:=true;var reversed:=false
		for i in roundi(3.0/dt):
			if i==roundi(1.0/dt):
				cell.target=Vector2.LEFT;cell.facing=Vector2.LEFT
			if i==roundi(2.0/dt):sim.fluid.velocity.fill(Vector2(45,-25))
			var before: Vector2=cell.velocity;var turn: float=cell.angular_velocity
			sim._motion_cell(cell,dt)
			smooth=smooth and cell.velocity.distance_to(before)<=Sim.Cell.LINEAR_ACCELERATION*dt+.0001 and absf(cell.angular_velocity-turn)<=Sim.Cell.TURN_ACCELERATION*dt+.0001
			if i==roundi(1.0/dt):reversed=cell.velocity.x>0 and absf(cell.angular_velocity)<.1
		check(smooth,"Steering/current changes respect both acceleration bounds at "+str(dt))
		check(reversed,"Reversed instinct retains motion and turns gradually rather than snapping")
		check(sim.rng.state==state,"Body smoothing adds no navigation random draws")
		check(unchanged[0]==Vector2.ZERO and sim.fluid.velocity[0]==Vector2(45,-25),"Body response does not inject feedback into water")
	var sim=fixture();var cell=sim.player
	cell.activity=1;cell.energy=100;cell.biomass=20;cell.add_organ("propulsion",0,"graze",false)
	cell.velocity=Vector2.ZERO;cell.angle=0;cell.angular_velocity=0;cell.target=Vector2.RIGHT;cell.facing=Vector2.RIGHT;cell.target_mouth=0
	sim.fluid.velocity.fill(Vector2.ZERO)
	for i in 240:sim._motion_cell(cell,1.0/60)
	var motor: Dictionary=cell.organs[0]
	var previous_speed: float=13000.0*motor.scale*motor.scale/float(cell.fluid_drag())
	check(absf(cell.velocity.length()/previous_speed-1.12)<.01,"Settled swimming is twelve percent faster with unchanged anatomy")
	var flow=Vector2(30,15);sim.fluid.velocity.fill(flow);cell.target=Vector2.ZERO
	for i in 240:sim._motion_cell(cell,1.0/60)
	check(cell.velocity.distance_to(flow)<.01,"Idle relative velocity decays back to the actual local current")
	# Real contact wrappers keep geometric collision resolution, but cannot
	# produce an instantaneous spin/launch in the final body velocity.
	var other=Sim.Cell.new(988,cell.position+Vector2(cell.radius*1.4,0))
	other.activity=1;sim.cells.append(other);other.velocity=Vector2(-100,-20);cell.velocity=Vector2(100,20)
	cell.target=Vector2.ZERO;cell.angular_velocity=0;other.angular_velocity=0
	var velocities=[cell.velocity,other.velocity];var turns=[cell.angular_velocity,other.angular_velocity]
	sim._step_cell_motion(1.0/30)
	for i in 2:
		check(sim.cells[i].velocity.distance_to(velocities[i])<=Sim.Cell.LINEAR_ACCELERATION/30+.001 and absf(sim.cells[i].angular_velocity-turns[i])<=Sim.Cell.TURN_ACCELERATION/30+.001,"Detailed contacts remain within the same acceleration budget")
	var coarse=fixture();coarse.coarse_mode=true;cell=coarse.player
	cell.activity=1;cell.velocity=Vector2.ZERO;cell.angular_velocity=0;cell.add_organ("propulsion",0,"graze",false);cell.target=Vector2.LEFT;cell.facing=Vector2.LEFT
	coarse.fluid.velocity.fill(Vector2(60,0));coarse.offscreen_ecology.advance_body(coarse,cell,.25)
	check(cell.velocity.length()<=Sim.Cell.LINEAR_ACCELERATION*.25+.001 and absf(cell.angular_velocity)<=Sim.Cell.TURN_ACCELERATION*.25+.001,"Coarse/resident body call uses the same smooth response")
	# A large meal has no venting cost, including a saved old stress marker.
	var fed=fixture();cell=fed.player;cell.biomass=25;cell.health=100
	cell.chemistry.emit("food",7000,Vector2.ZERO)
	cell.holes=[{"a":PI,"size":.15,"stress":true},{"a":0.0,"size":.1}]
	cell.behavior={"stress":true}
	var food: float=cell.substrate;var fuel: float=cell.chemistry.raw_fuel()
	fed.Lifecycle.physiology(fed,cell,1)
	check(cell.biomass==25 and cell.substrate==food and cell.chemistry.raw_fuel()==fuel and fed.particle_count()==0,"Stored food neither triggers nor pays for biomass venting")
	check(cell.health==100 and cell.holes.size()==1 and not cell.holes[0].get("stress",false),"Food-only surplus vent clears while actual wounds remain")
	for biomass in [500.0,600.0,1000.0]:
		var vent=fixture();cell=vent.player;cell.biomass=biomass
		var body: float=cell.body;var health: float=cell.health;var material: float=cell.organic_mass()
		vent.Lifecycle.physiology(vent,cell,1)
		var lost: float=biomass-cell.biomass
		if biomass==500:
			check(lost==0 and vent.particle_count()==0 and cell.holes.is_empty(),"Venting begins strictly above500 biomass")
		else:
			var nutrient:=0.0;var waste:=0.0;var emitted_fuel:=0.0
			for packet in vent.particles:
				if packet.kind==Sim.NUTRIENT:nutrient+=packet.amount;emitted_fuel+=minf(packet.amount,packet.capacity)*cell.Chemistry.FOOD_FUEL
				if packet.kind==Sim.WASTE:waste+=packet.amount
			check(absf(lost-(biomass-500)*(1-exp(-.01)))<.000001,"Outward rate ramps smoothly with biomass surplus")
			check(absf(nutrient-lost*.7)<.000001 and absf(waste-lost*.3)<.000001 and vent.particle_count()==2,"Actual vent loss becomes visible nutrient and waste particles")
			check(absf(cell.organic_mass()+nutrient+waste-material)<.000001 and emitted_fuel<=lost*cell.Chemistry.TISSUE_FUEL+.000001,"Reverse release conserves material and cannot create fresh-food energy")
			check(cell.body==body and cell.health==health and cell.biomass>=500,"Venting preserves anatomy, health and the first500 biomass")
	var delayed=fixture();delayed.player.biomass=1000
	delayed.Lifecycle.physiology(delayed,delayed.player,10000)
	check(delayed.player.biomass>=500 and is_finite(delayed.player.biomass),"A delayed vent cannot overshoot below its biomass threshold")

func synergy_anatomy() -> void:
	var sim=fixture();var cell=sim.player;var policy=sim.Investment
	for kind in ["feeding","hunting","propulsion","poreforming","proboscis"]:cell.add_organ(kind,cell.organs.size(),"graze",false)
	check(cell.synergy()=="hunter" and policy.synergy_blocker(cell,"hunter").is_empty(),"A Hunter may keep a proboscis alongside its required mouth and gland")
	var mouth: Dictionary=cell.organs.filter(func(organ):return organ.kind=="feeding")[0]
	mouth.hp=0;cell.update_geometry()
	check(cell.synergy()=="" and policy.missing_synergy_part(sim,cell,"hunter")=="feeding","A proboscis cannot substitute for a damaged Hunter mouth")
	mouth.hp=mouth.max_hp
	var gland: Dictionary=cell.organs.filter(func(organ):return organ.kind=="poreforming")[0]
	gland.hp=0
	check(cell.synergy()=="","A mouth and proboscis cannot substitute for a Hunter offensive gland")
	gland.hp=gland.max_hp;cell.energy=0
	var shed: Dictionary=policy.shed_support(cell,"hunter")
	check(not shed.has("id") or int(shed.id)!=int(gland.id),"A spare proboscis never makes the sole Hunter gland disposable")
	cell.organs.erase(mouth);cell.energy=100;cell.biomass=400;sim.investment.cells[cell.id]="hunter"
	check(policy.decision(sim,cell).get("kind","")=="feeding" and cell.count("proboscis")==1,"A mouthless Hunter strategy repairs its mouth without discarding a compatible proboscis")
	for role in ["grazer","producer"]:
		cell.organs.clear()
		for kind in (["feeding","cilia"] if role=="grazer" else ["photosynthesis","photosynthesis","mitochondrion"]):cell.add_organ(kind,0,"graze",false)
		check(cell.synergy()==role,"The minimal "+role+" retains its ordinary synergy")
		cell.add_organ("proboscis",1,"graze",false);var probe: Dictionary=cell.organs[-1]
		for hp in [1.0,0.0]:
			probe.hp=hp
			check(cell.synergy()=="" and policy.synergy_blocker(cell,role).get("id",-1)==probe.id,"Any installed proboscis blocks "+role+", including damaged organs")
	cell.organs.clear()
	for kind in ["proboscis","propulsion","hunting","sensing"]:cell.add_organ(kind,0,"graze",false)
	check(cell.synergy()=="parasite","A mouthless Parasite keeps its distinct synergy")
	cell.add_organ("photosynthesis",1,"graze",false)
	for hp in [1.0,0.0]:
		cell.organs[-1].hp=hp
		check(cell.synergy()!="parasite" and policy.synergy_blocker(cell,"parasite").get("id",-1)==cell.organs[-1].id,"Any installed leaf blocks Parasite and is reabsorbed before its core, including damaged leaves")
	cell.organs.pop_back()
	cell.add_organ("feeding",1,"graze",false)
	for hp in [1.0,0.0]:
		cell.organs[-1].hp=hp
		check(cell.synergy()!="parasite" and policy.synergy_blocker(cell,"parasite").get("id",-1)==cell.organs[-1].id,"Any installed oral groove blocks Parasite, including a damaged mouth")

func synergy_investment() -> void:
	for role in ["hunter","producer","grazer","parasite"]:
		for seed_value in [28,29]:
			var sim=fixture();sim.seed_value=seed_value;var cell=sim.player
			sim.investment.lineages[cell.lineage_id()]=role;cell.biomass=2000;cell.energy=200
			for kind in ["feeding","photosynthesis","protection"]:cell.add_organ(kind,cell.organs.size()*1.5,"graze",false)
			if role in ["producer","grazer"]:cell.add_organ("poreforming",2,"graze",false)
			var steps:=0
			while cell.synergy()!=role and steps<12:
				var choice: Dictionary=sim.Investment.decision(sim,cell)
				check(not choice.is_empty(),"An assigned "+role+" keeps progressing toward its synergy")
				if choice.is_empty():break
				var pore: bool=choice.get("kind","")=="poreforming"
				if pore:check(cell.working("feeding") and cell.working("hunting") and cell.working("propulsion") and cell.count("photosynthesis")==0,"Pore gland waits for mouth, receptor, flagellum and no leaves")
				var before: Array=cell.organs.duplicate(true);var input: float=sim.external_input;var mass: float=cell.organic_mass()
				for packet in sim.particles:
					if packet.alive:mass+=packet.amount*Sim.Catalog.material(packet.kind)
				sim.step_autonomous_builds();steps+=1
				check(cell.organs!=before and cell.investment_retry_at==sim.time+60,"A real strategy action respects its one-minute cooldown")
				var after: float=cell.organic_mass()
				for packet in sim.particles:
					if packet.alive:after+=packet.amount*Sim.Catalog.material(packet.kind)
				check(is_equal_approx(after-mass,sim.external_input-input),"Core building and blocker reabsorption keep ordinary material accounting")
				if pore:check(cell.synergy()=="hunter" and not cell.accept_surface(Sim.Cell.Surface.SUBUNIT,1,0,cell.id),"Gland installation gains actual self-pore immunity immediately")
				before=cell.organs.duplicate(true);sim.step_autonomous_builds()
				check(cell.organs==before,"No second action runs in the same minute")
				sim.time+=60
			check(cell.synergy()==role and steps<=7,"Every assigned role reaches its synergy before optional support")
	var old=fixture();var cell=old.player;old.investment.cells[cell.id]="hunter"
	for kind in ["feeding","photosynthesis","hunting","propulsion","poreforming"]:cell.add_organ(kind,cell.organs.size(),"graze",false)
	cell.energy=100;cell.biomass=60
	old.step_autonomous_builds()
	check(cell.synergy()=="hunter" and cell.count("photosynthesis")==0,"Existing leaf-blocked Hunter reabsorbs its last leaf at its next investment opportunity")
	var protected_cell=fixture();cell=protected_cell.player;protected_cell.investment.cells[cell.id]="hunter"
	for kind in ["feeding","photosynthesis","hunting","propulsion"]:cell.add_organ(kind,cell.organs.size(),"graze",false)
	cell.unattended_protected=true;cell.biomass=200;cell.energy=100
	check(protected_cell.Investment.decision(protected_cell,cell).is_empty(),"Protected favorite neither loses its leaf nor installs an unsafe pore gland")
	cell.unattended_protected=false;protected_cell.managed_cells=[cell.id]
	check(protected_cell.Investment.decision(protected_cell,cell).is_empty(),"Connected selected cell stays under manual control")
	protected_cell.managed_cells=[];protected_cell.investment.cells[cell.id]="manual"
	check(protected_cell.Investment.decision(protected_cell,cell).is_empty(),"Explicit Manual remains untouched")
	cell.organs.clear()
	for kind in ["feeding","hunting","poreforming","cilia"]:cell.add_organ(kind,cell.organs.size(),"graze",false)
	protected_cell.investment.cells[cell.id]="hunter";cell.biomass=23;cell.energy=100
	check(protected_cell.Investment.decision(protected_cell,cell).get("kind","")=="propulsion","Existing weapon/cilia cannot make the missing Hunter flagellum discretionary")
	cell.add_organ("propulsion",3,"graze",false);cell.energy=0
	var shed: Dictionary=protected_cell.Investment.shed_support(cell,"hunter")
	check(not shed.has("id") or cell.organ_by_id(shed.id).kind not in ["propulsion","poreforming"],"Recovery preserves the actual last Hunter weapon and required flagellum")
	var custom=fixture();cell=custom.player
	for kind in ["photosynthesis","hunting","propulsion","proboscis"]:cell.add_organ(kind,cell.organs.size(),"graze",false)
	check(custom.Investment.save_template(custom,"cell",cell.id),"An explicit mixed custom build can still be saved")
	var chosen: Dictionary=custom.Investment.decision(custom,cell)
	check(chosen.get("action","")!="remove","Completed custom example is not dismantled by a randomly different role fallback")
	preload("res://tests/behavior_tree.gd").investment(check)


class PickerUI extends RefCounted:
	func ui_scale() -> float:return 1.0
	func mobile() -> bool:return true
	func open_context(_context: Dictionary) -> void:pass
class PickerGame extends Control:
	var world
	var cell_ui=PickerUI.new()
	func _message(_text: String) -> void:pass

func parasite_fixture():
	var cell=Sim.Cell.new(900)
	cell.body=60;cell.biomass=40;cell.energy=72;cell.update_geometry()
	for pair in [["proboscis",0.0],["propulsion",PI],["hunting",.85],["sensing",-.85]]:
		cell.add_organ(pair[0],pair[1],"graze",false)
	cell.update_geometry()
	return cell

func parasite_balanced() -> void:
	var sim=fixture();var policy=sim.Investment
	var counts={}
	for ticket in policy.MIX_TOTAL:
		var path: String=policy.path_at(ticket);counts[path]=int(counts.get(path,0))+1
	check(counts==policy.MIX,"The weighted lottery is exactly2 Hunter/4 Parasite/10 Grazer/20 Producer slots")
	var state: int=sim.rng.state
	var before: String=policy.strategy(sim,sim.player)
	sim.cells.append(Sim.Cell.new(501))
	policy.npc_assignments(sim)
	check(policy.DEFAULT=="balanced" and policy.strategy(sim,sim.player)==before and sim.rng.state==state,"Balanced defaults are stable and do not consume physics/ecology randomness")
	check(policy.set_strategy(sim,"lineage","balanced") and policy.set_strategy(sim,"cell","parasite") and policy.strategy(sim,sim.player)=="parasite","An explicit role overrides a Balanced family")
	policy.set_strategy(sim,"cell","balanced")
	var child=Sim.Cell.new(44);child.lineage=sim.player.lineage_id()
	policy.inherit_strategy(sim,sim.player,child)
	check(sim.investment.cells[child.id]=="balanced" and policy.strategy(sim,child)==policy.balanced_path(sim,child),"Balanced daughters keep the mixed policy, not their parent's resolved role")
	policy.set_strategy(sim,"cell","manual")
	var restored=Codec.new().restore(Codec.new().capture(sim))
	check(policy.strategy(restored,restored.player)=="manual" and restored.investment.lineages[sim.player.lineage_id()]=="balanced","Checkpointing preserves explicit Manual and Balanced choices")
	var parasite=parasite_fixture()
	check(parasite.synergy()=="parasite" and not is_finite(parasite.membrane.hunter_angle),"A mouthless proboscis/flagellum/Hunt/Flight build is Parasite rather than Hunter")
	for kind in ["feeding","photosynthesis","poreforming","toxin","counterattack","acidifying"]:
		var incompatible=Sim.Cell.clone_state(parasite);incompatible.add_organ(kind,2,"graze",false)
		check(incompatible.synergy()!="parasite","Installed "+kind+" excludes the Parasite role")
	for kind in ["proboscis","propulsion","hunting","sensing"]:
		var damaged=Sim.Cell.clone_state(parasite)
		for organ in damaged.organs:
			if organ.kind==kind:organ.hp=0
		check(damaged.synergy()!="parasite","Parasite requires a working "+kind)
	for axis in [0.0,.41,1.6]:
		var body=Sim.Cell.clone_state(parasite)
		body.organs[0].a=axis;body.update_geometry()
		for i in 60:body.membrane.step(1.0/60,body.radius,Vector2.ZERO,i/60.0)
		var front: float=body.visible_support(axis);var side: float=body.visible_support(axis+PI/2)
		check(front>side*2.0 and body.membrane.parasite_angle==axis,"The smooth short-worm profile faces its proboscis at arbitrary mounting angles")
		var area:=0.0
		for i in body.membrane.COUNT:area+=body.membrane.points[i].cross(body.membrane.points[(i+1)%body.membrane.COUNT])*.5
		check(absf(area-body.membrane.COUNT*body.radius*body.radius*sin(TAU/body.membrane.COUNT)*.5)<.05,"The elongated physical ring preserves tissue area")
		var portrait=preload("res://scripts/cell_portrait.gd").capture(body)
		check(portrait.outline==body.membrane.outline() and portrait.synergy.role=="parasite","Family art captures the actual parasite outline")
		var codec=Codec.new();var saved_points=body.membrane.points.duplicate()
		var recovered=codec.restore(codec.capture(body))
		check(recovered.membrane.points==saved_points and recovered.membrane.parasite_angle==axis,"Checkpoint derives the parasite axis without rewriting saved cell points")
	parasite.chemistry.emit("food",8,Vector2.ZERO,-1,-1,8*parasite.Chemistry.TISSUE_FUEL)
	parasite.chemistry.emit("oxygen",8,Vector2.ZERO)
	var matter: float=parasite.organic_mass()
	var potential: float=parasite.biomass*parasite.Chemistry.TISSUE_FUEL+parasite.energy+parasite.chemistry.potential()+parasite.chemistry.heat
	var biomass: float=parasite.biomass
	parasite.chemistry.advance(parasite,1.0/30)
	check(parasite.substrate<.000001 and parasite.biomass>biomass,"Parasite food converts promptly to biomass instead of remaining in food vacuoles")
	check(absf(parasite.organic_mass()-matter)<.000001 and absf(parasite.biomass*parasite.Chemistry.TISSUE_FUEL+parasite.energy+parasite.chemistry.potential()+parasite.chemistry.heat-potential)<.00001,"Prompt digestion conserves actual material and finite fuel")
	parasite.biomass=200;parasite.update_geometry()
	check(sim.Behavior.sated(parasite) and sim.Behavior.priority(parasite,"hunt")==0,"A parasite rests on its own biomass reserves")
	var hunter=Sim.Cell.new(901);hunter.body=parasite.body;hunter.biomass=200
	for kind in ["feeding","hunting","propulsion","poreforming"]:hunter.add_organ(kind,0,"graze",false)
	hunter.update_geometry()
	check(parasite.storage_volume()>hunter.storage_volume(),"Parasite biomass occupies the same bulkier storage tier as Grazer reserves")
	var contact=parasite_fixture();var donor=Sim.Cell.new(902,preload("res://scripts/proboscis.gd").tip(contact,contact.organs[0]))
	donor.biomass=40;sim.cells=[contact,donor];sim.player=contact;sim.spatial_queries=false
	var total: float=contact.organic_mass()+donor.organic_mass()
	preload("res://scripts/proboscis.gd").step(sim,contact,.1)
	contact.chemistry.advance(contact,.1)
	check(contact.eaten>0 and donor.biomass<40 and contact.substrate<.000001 and absf(contact.organic_mass()+donor.organic_mass()-total)<.00001,"Real proboscis contact feeds biomass storage without creating food or donor material")
	var fixture_world=preload("res://tests/ecology_balance.gd").new()
	var pond=fixture_world.fixture(9601)
	var phenotypes={}
	for body in pond.cells:
		var role: String=body.synergy();phenotypes[role]=int(phenotypes.get(role,0))+1
	check(phenotypes==policy.MIX,"The minimal36-cell reference pond replaces its four proboscis hunters with four true Parasites")
	pond.disable_particle_pool();fixture_world.free()

func parasite_picker() -> void:
	var fake=PickerGame.new();fake.world=fixture();root.add_child(fake)
	fake.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel=preload("res://scripts/investment_picker.gd").new();fake.add_child(panel);panel.initialize(fake)
	for viewport in [Vector2i(320,568),Vector2i(393,740),Vector2i(740,393),Vector2i(1280,720)]:
		root.content_scale_size=Vector2i.ZERO;root.size=viewport
		panel.open();await process_frame;await process_frame;panel.sync();await process_frame
		check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(panel.get_global_rect()),"All five investment choices fit "+str(viewport))
		for card in panel.cards:check(panel.get_global_rect().encloses(card.get_global_rect()),card.strategy+" portrait stays within its menu")
		var balanced=panel.cards[-1]
		balanced.pressed.emit()
		check(fake.world.investment.lineages[fake.world.player.lineage_id()]=="balanced" and balanced.active,"Balanced portrait selects the actual family setting")
		if not DisplayServer.get_name()=="headless" and viewport==Vector2i(393,740):
			await RenderingServer.frame_post_draw
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--capture="):root.get_texture().get_image().save_png(arg.substr(10))
	fake.queue_free();await process_frame

func parasite_gpu() -> void:
	var beacon=ColorRect.new();beacon.size=Vector2(8,8);root.add_child(beacon)
	await process_frame;await process_frame
	var gpu=preload("res://scripts/resident_particles.gd").new()
	gpu.rd=RenderingServer.get_rendering_device()
	check(gpu.rd!=null,"Parasite digestion hardware rendering device exists")
	if gpu.rd==null:beacon.queue_free();return
	for dt in [1.0/30,.25]:
		var cpu=parasite_fixture()
		cpu.chemistry.emit("food",8,Vector2.ZERO,-1,-1,8*cpu.Chemistry.TISSUE_FUEL)
		cpu.chemistry.emit("oxygen",8,Vector2.ZERO)
		var resident=Sim.Cell.clone_state(cpu)
		var component=preload("res://scripts/resident_cytoplasm.gd").new()
		check(component.attach(gpu,resident.chemistry,resident),"Parasite attaches to real resident cytoplasm")
		resident.chemistry.advance(resident,dt);cpu.chemistry.advance(cpu,dt)
		check(resident.substrate<.000001 and absf(resident.biomass-cpu.biomass)<.00001 and absf(resident.energy-cpu.energy)<.00001,"CPU/resident prompt digestion agrees at "+str(dt))
		check(component.exports==0,"Prompt digestion does not download a particle pose mirror")
		resident.chemistry.ensure_cpu()
	gpu.close();beacon.queue_free();await process_frame
