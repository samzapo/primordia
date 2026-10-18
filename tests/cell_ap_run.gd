extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func fixture():
	var sim=Sim.new(640,0,false);sim.server_mode=true;sim.evolution.sandbox=true
	sim.cells=[sim.player];sim.player.body=500;sim.player.update_geometry()
	sim.player.add_organ("feeding",0,"graze",false)
	sim.lineage.register(sim.player,-1,0,"active",0)
	sim.habitat_geometry=Sim.Habitat.new(640,sim.cells);sim.habitat_geometry.enabled=false
	return sim
func schedule(sim,at: float) -> void:
	sim.time=at;sim.autonomous_build_retry_at=0;sim.step_autonomous_builds()
func run() -> void:
	var sim=fixture();var parent=sim.player
	var relative=Sim.Cell.new(88,Vector2(1400,1000));relative.lineage=parent.lineage_id()
	relative.body=500;relative.update_geometry();relative.add_organ("feeding",0,"graze",false)
	sim.cells.append(relative);sim.lineage.register(relative,parent.id,1,"living",0)
	parent.ap=20;relative.ap=0
	for kind in ["cilia","photosynthesis","mitochondrion","regenerative"]:
		check(sim.install(kind,1),"Fixture buys four added organs with the parent's AP")
	var before: int=parent.ap
	check(sim.remove(parent.organs.size()-1) and sim.remove(parent.organs.size()-1),"Both real reabsorption transactions succeed")
	check(parent.ap==before+5 and relative.ap==0,"Four then three added organs return3+2 to their own cell only")
	check(not sim.remove(999) and parent.ap==before+5,"An invalid removal cannot award AP")
	sim.player=relative
	check(not sim.install("photosynthesis",1) if relative.construction_price()>0 else sim.install("photosynthesis",1),"First free construction uses the selected cell's actual price")
	check(relative.ap==0 and parent.ap==before+5,"Switching cells never transfers AP")
	check(not sim.install("cilia",2),"An unfunded relative cannot borrow the parent's AP")
	check(sim.Investment.strategy(sim,relative)=="manual","Unchosen relatives default to Manual")
	sim.investment.npc[relative.id]="hunter";sim.Investment.npc_assignments(sim)
	check(sim.investment.npc.is_empty() and sim.Investment.strategy(sim,relative)=="manual","Retired NPC quota assignments cannot activate a strategy")
	sim.player=parent;sim.managed_cells=[parent.id]
	sim.investment.cells[relative.id]="producer";relative.ap=10
	var count: int=relative.organs.size()
	schedule(sim,0)
	check(relative.organs.size()==count+1 and relative.investment_retry_at==60,"Opted-in unattended cell makes one purchase and starts a minute cooldown")
	var balance: int=relative.ap
	schedule(sim,59.99)
	check(relative.organs.size()==count+1 and relative.ap==balance,"No further auto purchase before one minute")
	var restored=Codec.new().restore(Codec.new().capture(sim))
	var saved_relative=restored.cells.filter(func(body):return body.id==relative.id)[0]
	check(saved_relative.investment_retry_at==60 and saved_relative.ap==balance,"Cooldown and independent AP survive checkpoint restore")
	schedule(sim,60);schedule(restored,60)
	check(relative.organs.size()==count+2 and saved_relative.organs==relative.organs and saved_relative.ap==relative.ap,"At the minute boundary restored and uninterrupted purchases agree")
	check(parent.ap==before+5,"Relative investment cannot debit the parent's refund")
	# Retiring an off-role organ uses the ordinary finite salvage/refund path.
	sim=fixture();parent=sim.player;parent.ap=0
	parent.add_organ("toxin",2,"graze",false);parent.add_organ("mitochondrion",1,"graze",false)
	sim.investment.cells[parent.id]="producer"
	var mass: float=parent.organic_mass();var removed: int=parent.organs[1].id
	schedule(sim,0)
	check(parent.organ_by_id(removed).is_empty() and parent.count("feeding")==1 and parent.count("mitochondrion")==1,"A Producer without a leaf may reabsorb off-role toxin, retaining feeding and ATP support")
	check(parent.ap==1 and absf(parent.organic_mass()+sim.particles.reduce(func(total,p):return total+p.amount,0.0)-mass)<.00001,"Automatic reabsorption refunds the cell's tier and conserves salvage/debris")
	count=parent.organs.size();schedule(sim,59.99)
	check(parent.organs.size()==count and parent.ap==1,"Reabsorption shares the minute cooldown with buying")
	schedule(sim,60)
	check(parent.count("photosynthesis")==1 and parent.ap==0,"After the cooldown the refunded AP funds a role-appropriate leaf")
	check(not sim.edit("move",{"id":parent.organs[-1].id,"angle":2}) and not parent.move_organ(parent.organs[-1].id,2),"Old Move commands and direct organ moving are retired")
	# A readiness query cannot create AP; only the committed birth awards1+1.
	sim=fixture();parent=sim.player;parent.ap=9
	parent.brood_mass=sim.offspring_quote().material;parent.brood_energy=60
	var proposal=sim.make_offspring(parent,sim.offspring_quote())
	check(proposal.ap==0 and sim.division_status().ready and parent.ap==9,"Birth proposals/readiness never grant AP")
	check(sim.divide_lineage(false,false),"Funded division succeeds")
	var daughter=sim.cells[-1]
	check(parent.ap==10 and daughter.ap==1,"Committed division gives parent1AP and daughter1AP")
	check(sim.Investment.strategy(sim,daughter)=="manual","A Manual parent never gives an automatic strategy to its daughter")
	check(not sim.divide_lineage(false,false) and parent.ap==10 and daughter.ap==1,"Rejected division cannot repeat AP awards")
	# Legacy family pools migrate once, using authenticated selection over world.player.
	sim=fixture();parent=sim.player
	relative=Sim.Cell.new(88);relative.lineage=parent.lineage_id();relative.add_organ("feeding",0,"graze",false);sim.cells.append(relative)
	sim.lineage.register(relative,parent.id,1,"living",0)
	var npc=Sim.Cell.new(99);npc.add_organ("feeding",0,"graze",false);sim.cells.append(npc)
	var ledger=sim._family_ledger(npc)
	sim.evolution.points=11;ledger.progression.points=7
	sim.investment.cells[relative.id]="hunter";sim.investment.npc[npc.id]="grazer"
	var accounts={"fixture":{"root":parent.lineage_id(),"selected":relative.id,"current":relative,"evolution":sim.evolution,"lineage":sim.lineage}}
	var graph: Dictionary=Codec.new().capture({"world":sim,"accounts":accounts})
	for record in graph.objects:
		if record.kind=="simulation":record.fields.erase("ap_model_version")
		if record.kind=="cell":record.fields.erase("ap");record.fields.erase("investment_retry_at")
	var rng: int=sim.rng.state
	restored=Codec.new().restore(graph)
	var world=restored.world;var selected=restored.accounts.fixture.current
	check(selected.ap==11 and world.player.ap==0 and world.cells[-1].ap==7,"Legacy pools go to the selected player body and existing NPC owner without duplicating gifts")
	check(world.cells.reduce(func(total,body):return total+body.ap,0)==18 and world.evolution.points==0,"Total old AP is conserved and the consumed shared pool is empty")
	check(world.ap_model_version==1 and world.rng.state==rng and selected.organs==relative.organs,"Migration marks its version and preserves anatomy/RNG")
	check(world.investment=={"npc":{},"lineages":{},"cells":{}},"This transition starts every existing cell in Manual")
	var twice=Codec.new().restore(Codec.new().capture(restored))
	check(twice.accounts.fixture.current.ap==11 and twice.world.cells.reduce(func(total,body):return total+body.ap,0)==18,"Re-saving/restarting cannot regrant migrated AP")
	check(twice.accounts.fixture.current==twice.world.cells[1],"AP migration keeps the account attached to its actual saved cell")
	print("CELL AP: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
