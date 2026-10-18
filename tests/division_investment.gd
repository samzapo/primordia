extends RefCounted
## Division progression, exact transfer and immutable parent/failed proposals.
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
static func fixture(seed_value: int=610):
 var sim=Sim.new(seed_value,0,false);sim.server_mode=true
 sim.cells=[sim.player];sim.player.add_organ("feeding",0,"graze",false)
 sim.lineage.register(sim.player,-1,0,"active",0)
 sim.lineage.progression=sim.evolution
 sim.habitat_geometry=Sim.Habitat.new(seed_value,sim.cells);sim.habitat_geometry.enabled=false
 return sim
static func fund(sim,cell) -> void:
 var quote: Dictionary=sim.offspring_quote(cell)
 cell.biomass+=quote.material
 cell.energy=100
 cell.reserve(maxf(60,quote.material),quote.material)
static func material(sim) -> float:
 return sim.lineage.stored_material()+sim.cells.reduce(func(total,cell):return total+cell.organic_mass(),0.0)
static func run(check: Callable) -> void:
 pricing(check)
 var sim=fixture();var parent=sim.player
 parent.body=500;parent.update_geometry()
 for kind in ["photosynthesis","mitochondrion","toxin","propulsion","regenerative"]:
  check.call(parent.add_organ(kind,1,"graze",false),"Parent fixture fits "+kind)
 parent.organs[1].mutation="shade_leaf"
 parent.organs[1]["photo_elapsed"]=.2
 var quote: Dictionary=sim.offspring_quote(parent)
 check.call(quote.total_material==42 and quote.material==12 and quote.body_transfer==30,"Birth quote funds only basic body and biomass; its inherent oral groove is part of the body")
 var before: PackedByteArray=var_to_bytes(Codec.new().capture(parent))
 var proposal=sim.make_offspring(parent,quote)
 check.call(proposal.organs.size()==1 and proposal.count("feeding")==1 and proposal.next_organ_id==1,"A new daughter has one fresh inherent oral groove, no copied purchased organs")
 check.call(proposal.organs[0].get("mutation","")=="" and proposal.chemistry.particle_count()==0 and proposal.lost_organs.is_empty(),"Daughters do not duplicate adaptations, internal contents or repair history")
 check.call(var_to_bytes(Codec.new().capture(parent))==before,"Preparing a daughter never edits the parent's anatomy")
 check.call(proposal.membrane.skeleton!=parent.membrane.skeleton,"The daughter owns its own sampled skeleton")
 for role in ["hunter","producer","grazer"]:
  sim=fixture();parent=sim.player
  sim.investment.lineages[parent.lineage_id()]="producer"
  sim.investment.cells[parent.id]=role
  parent.add_organ("photosynthesis",1,"graze",false)
  fund(sim,parent)
  var mass: float=material(sim);var energy: float=parent.energy+parent.brood_energy
  var points: int=sim.player.ap
  check.call(sim.divide_lineage(false,false),"Funded living division commits")
  var child=sim.cells[-1]
  check.call(sim.Investment.strategy(sim,child)==role and sim.investment.cells[child.id]==role,"Daughter inherits the effective body strategy, including a family override")
  check.call(child.organs.size()==1 and child.count("photosynthesis")==0 and parent.count("photosynthesis")==1,"Division keeps parent organs and lets the daughter build its own")
  check.call(absf(material(sim)-mass)<.00001 and absf(parent.energy+parent.brood_energy+child.energy-(energy-20))<.00001,"Basic daughter conserves paid tissue and the existing division ATP transfer")
  check.call(parent.ap==points+1 and child.ap==1,"Committed division awards one AP each to parent and daughter")
  var restored=Codec.new().restore(Codec.new().capture(sim))
  var saved=restored.cells[-1]
  check.call(restored.Investment.strategy(restored,saved)==role and saved.organs.size()==1,"Daughter strategy and basic anatomy survive checkpoint recovery")
 # Manual remains Manual, without consuming a strategy RNG draw.
 var observed: Dictionary={}
 for seed_value in range(60):
  sim=fixture(seed_value);parent=sim.player;fund(sim,parent)
  check.call(sim.divide_lineage(false,false),"Manual parent's funded division commits")
  var child=sim.cells[-1];var role: String=sim.Investment.strategy(sim,child)
  observed[role]=true
  check.call(role=="manual" and sim.Investment.strategy(sim,parent)=="manual","Manual parent and daughter both keep automatic spending disabled")
 check.call(observed.keys()==["manual"],"Manual births never opt into random strategies")
 # NPC balancing cannot overwrite inherited birth intent, even in a tiny family.
 sim=fixture();var npc=Sim.Cell.new(77,Vector2(1200,1200))
 npc.add_organ("feeding",0,"graze",false);sim.cells.append(npc)
 sim.next_id=100;sim.investment.cells[npc.id]="hunter";fund(sim,npc)
 check.call(sim._divide_paid(npc,sim._family_ledger(npc)),"Unowned parent divides using the same path")
 var child=sim.cells[-1]
 sim.Investment.npc_assignments(sim)
 check.call(sim.Investment.strategy(sim,child)=="hunter" and sim.investment.cells[child.id]=="hunter","Population quotas preserve a daughter's inherited strategy")
 sim._die(child)
 check.call(not sim.investment.cells.has(child.id) and not sim.investment.npc.has(child.id),"Death removes obsolete per-body strategy records")
 # Blocked births neither draw a random strategy nor leave an unused override.
 sim=fixture();parent=sim.player;fund(sim,parent)
 var blocker=Sim.Cell.new(999,parent.position);blocker.body=10000000;blocker.update_geometry();blocker.membrane=Sim.Cell.Membrane.new(blocker.radius)
 sim.cells.append(blocker)
 var state: int=sim.rng.state;var policies: Dictionary=sim.investment.duplicate(true)
 var mass: float=material(sim);var identity: int=sim.next_id
 check.call(not sim.divide_lineage(false,false),"Blocked birth is rejected")
 check.call(sim.rng.state==state and sim.investment==policies and sim.next_id==identity and is_equal_approx(material(sim),mass),"Blocked birth preserves RNG, strategy maps, identity and finite material")


static func pricing(check: Callable) -> void:
 var sim=fixture();var cell=sim.player
 sim.player.ap=0
 check.call(cell.construction_price()==0 and sim.install("cilia",1) and sim.player.ap==0,"Inherent oral anatomy permits a first free organ at zero AP")
 var mass: float=cell.organic_mass();var source: float=sim.external_input
 check.call(cell.construction_price()==1 and not sim.install("photosynthesis",2) and cell.organic_mass()==mass and sim.external_input==source,"Second organ requires one AP and rejects atomically without material")
 sim.player.ap=20
 check.call(sim.install("photosynthesis",2) and sim.player.ap==19,"The second added organ costs one AP")
 check.call(sim.install("mitochondrion",0) and sim.player.ap==17 and cell.construction_price()==3,"The third internal organ costs two AP and counts toward the next price")
 var organ: Dictionary=cell.organs[-1]
 check.call(organ.construction_ap==2 and sim.remove(cell.organs.find(organ)) and sim.player.ap==19 and cell.construction_price()==2,"Selling from three added organs returns two AP and lowers the next price")
 var leaf: Dictionary=cell.organs.filter(func(o):return o.kind=="photosynthesis")[0]
 cell.organs.erase(leaf);cell.lost_organs.append(leaf);cell.update_geometry()
 check.call(sim.restore(leaf.id) and sim.player.ap==18 and cell.construction_price()==2 and cell.organs[-1].construction_ap==1,"Restoration pays and records the same current-count price as new construction")
 check.call(sim.remove(cell.organs.find(cell.organs.filter(func(o):return o.kind=="photosynthesis")[0])) and sim.player.ap==19 and cell.construction_price()==1,"Selling from two added organs returns one AP")
 check.call(sim.remove(cell.organs.find(cell.organs.filter(func(o):return o.kind=="cilia")[0])) and sim.player.ap==19 and cell.construction_price()==0,"Selling a free first organ returns zero and restores the free next price")
 check.call(not sim.remove(0) and sim.player.ap==19,"The inherent oral groove cannot be sold for AP")
 var saved=Codec.new().restore(Codec.new().capture(sim))
 check.call(saved.player.construction_price()==0 and saved.player.ap==19,"Current-count pricing and AP refunds survive checkpoint recovery")
 var npc=Sim.Cell.new(77,Vector2(1100,1200));npc.add_organ("feeding",0,"graze",false)
 sim.cells.append(npc);sim.managed_cells=[cell.id]
 var ledger=sim._family_ledger(npc);npc.ap=0;sim.investment.cells[npc.id]="grazer"
 sim.step_autonomous_builds()
 check.call(npc.organs.size()==2 and npc.ap==0,"An unattended cell can buy its first organ with zero AP")
 sim.time+=2;sim.step_autonomous_builds()
 check.call(npc.organs.size()==2,"Unattended cells wait when the next price exceeds AP")
 npc.ap=1;sim.time+=60;sim.step_autonomous_builds()
 check.call(npc.organs.size()==3 and npc.ap==0,"Unattended cells pay the same progressive price for their second organ")
