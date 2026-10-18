extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Supply=preload("res://scripts/ambient_carbon.gd")
class BrightWorld:
 extends "res://scripts/simulation.gd"
 func light_at(_at: Vector2) -> float:return 1.0
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize() -> void:run.call_deferred()
func fixture():
 var sim=Sim.new(951,0,false)
 sim.cells=[sim.player];sim.habitat_geometry=Sim.Habitat.new(951,sim.cells);sim.habitat_geometry.enabled=false
 sim.lineage.initialize(sim);sim.evolution.sandbox=true
 sim.player.position=Vector2(320,320);sim.player.previous_position=sim.player.position
 sim.player.body=150;sim.player.biomass=20;sim.player.update_geometry()
 sim.player.add_organ("feeding",0,"graze",false)
 return sim
func run() -> void:
 var sim=fixture();var cell=sim.player
 check(not cell.automatic_division,"All cells default to manual division")
 var child=sim.make_offspring(cell,sim.offspring_quote(cell))
 check(child.count("photosynthesis")==1 and child.ap==0,"A paid daughter preview has one leaf without minting AP")
 check(absf(child.organic_mass()-sim.offspring_quote(cell).total_material)<.00001,"The division quote includes every starter organ material")
 sim.investment.lineages[cell.lineage_id()]="producer"
 sim.Investment.inherit_strategy(sim,cell,child)
 check(not sim.investment.cells.has(child.id) and sim.Investment.strategy(sim,child)=="producer","Family followers remain followers through division")
 sim.investment.cells[cell.id]="hunter"
 sim.Investment.inherit_strategy(sim,cell,child)
 check(sim.investment.cells[child.id]=="hunter","A deliberate individual exception is inherited")
 sim.Investment.set_strategy(sim,"lineage","grazer")
 check(sim.Investment.strategy(sim,cell)=="hunter","Family changes preserve individual exceptions")
 sim.Investment.set_strategy(sim,"family_adopt","inherit")
 check(sim.Investment.strategy(sim,cell)=="grazer","Explicit family adoption clears overrides")
 # Matching chemistry preserves true fuel while allocating bounded extra ATP.
 var neutral: float=sim.Catalog.nutrient_capacity(1,1,1,1,0)
 var mild: float=sim.Catalog.nutrient_capacity(1,1,1,1,.25)
 check(mild>neutral and mild<=3,"Mild acid accelerates bounded nutrient benefit")
 check(sim.Catalog.nutrient_capacity(1,0,1,0,.25)==0,"Acid never restores spent food fuel")
 # One of twenty groups is processed, with both gas additions separately accounted.
 sim.ambient_carbon_enabled=true;sim.time=5;Supply.step(sim)
 var carbon:=0.0;var oxygen:=0.0
 for p in sim.particles:
  if p.kind==sim.CARBON:carbon+=p.amount
  if p.kind==sim.OXYGEN:oxygen+=p.amount
 check(sim.particle_count()<=Supply.COUNT/10+2,"Gradual exchange does not emit a whole pond of gas in one tick")
 check(carbon>0 and oxygen>0 and oxygen<carbon*.1,"A small atmospheric oxygen contribution accompanies CO2")
 check(absf(carbon-sim.ambient_carbon_added)<.00001 and absf(oxygen-sim.ambient_oxygen_added)<.00001,"Gas additions are explicitly accounted by species")
 check(absf(sim.external_input-carbon)<.00001,"Oxygen does not masquerade as organic carbon input")
 # A vortical field exchanges more gas than a stationary field at equal clocks.
 var calm=fixture();var swirl=fixture()
 for i in swirl.fluid.velocity.size():
  var x: float=i%swirl.fluid.COLS
  var y: float=int(i/swirl.fluid.COLS)
  swirl.fluid.velocity[i]=Vector2(-y,x)*10
 calm.fluid.velocity.fill(Vector2.ZERO)
 for sample in [calm,swirl]:
  sample.ambient_carbon_enabled=true;sample.time=5;Supply.step(sample)
 check(swirl.ambient_carbon_added>calm.ambient_carbon_added and swirl.ambient_oxygen_added>calm.ambient_oxygen_added,"Higher absolute curl enhances both gas exchange rates")
 # A donor first pays the ordinary 3+2+1+0 Reabsorb refunds.
 sim=fixture();cell=sim.player;cell.ap=2
 var donor=Sim.Cell.new(1,cell.position+Vector2(100,0))
 donor.lineage=cell.lineage_id();donor.body=100;donor.biomass=10;donor.energy=50;donor.ap=3;donor.age=90
 donor.add_organ("feeding",0,"graze",false)
 for kind in ["photosynthesis","mitochondrion","sensing","toxin_sac"]:donor.add_organ(kind,2,"graze",false)
 donor.organs[-1].stored_toxin=.5
 donor.chemistry.emit("food",2,Vector2.ZERO,-1,-1,15)
 donor.chemistry.particles[0].age=6
 donor.chemistry.emit("waste",.5,Vector2.ZERO,-1,donor.chemistry.particles[0].compartment,0)
 donor.chemistry.emit("oxygen",1,Vector2.ZERO)
 sim.cells.append(donor);sim.lineage.register(donor,cell.id,1,"living",0)
 donor.position=cell.position+Vector2(cell.extent()+donor.extent()-2,0)
 var before: float=cell.organic_mass()+donor.organic_mass()
 sim.managed_cells=[donor.id]
 check(not sim.FamilyMerging.request(sim,donor.id),"A connected player's selected donor cannot be consumed")
 sim.managed_cells=[cell.id]
 donor.lineage=42
 check(not sim.FamilyMerging.request(sim,donor.id),"Unrelated lineages cannot merge")
 donor.lineage=cell.lineage_id()
 check(sim.FamilyMerging.request(sim,donor.id) and sim.cells.size()==1,"Same-family contact commits merging")
 check(cell.ap==11,"All four organs reabsorb first, then donor AP transfers exactly once")
 check(cell.count("toxin_sac")==0 and cell.count("feeding")==1,"The receiver keeps its build without donor organ duplication")
 var after: float=cell.organic_mass()
 for p in sim.particles:after+=p.amount*sim.Catalog.material(p.kind)
 check(absf(after-before)<.0001,"Merging and Reabsorb waste preserve all material")
 check(absf(cell.substrate-2)<.000001 and absf(cell.oxygen-1)<.000001,"Internal food, true fuel and oxygen transfer")
 check(cell.chemistry.particles.filter(func(p):return p.species=="food")[0].age==6 and cell.chemistry.vacuoles.filter(func(v):return not v.has("species")).size()==1,"Transferred food and waste retain their shared vacuole and digestion age")
 check(not sim.FamilyMerging.request(sim,donor.id) and cell.ap==11,"Duplicate merging cannot repeat AP or contents")
 check(sim.lineage.total_cells==2 and sim.lineage.records.size()==1,"Merging neither awards a birth nor retains a deceased family portrait")
 check(sim.death_bursts.is_empty(),"Living reabsorption does not burst a toxin sac or play death")
 var restored=Codec.new().restore(Codec.new().capture(sim))
 check(restored.player.ap==11 and restored.player.merge_after==cell.merge_after and not restored.player.automatic_division,"AP, division choice and merge cooldown survive a checkpoint")
 # Navigation and weapons consume the same immutable cues independently.
 sim=fixture();cell=sim.player;cell.energy=10
 cell.add_organ("hunting",1,"hunt",false);var receptor: Dictionary=cell.organs[-1]
 cell.add_organ("toxin",2,"graze",false)
 cell.add_organ("poreforming",3,"graze",false)
 var report: Dictionary={"id":999,"lineage":999,"at":cell.position+Vector2(100,0),"mass":10.0,"hostile":false,"defended":false,"emitted_at":sim.time}
 var received: Dictionary={cell.organs[0].id:{"food":{},"reports":{},"patch":{"at":cell.position+Vector2(20,0),"mass":10.0}},
 receptor.id:{"food":{},"reports":{999:{"report":report,"distance":20.0,"expires_at":sim.time+10}}}}
 cell.sense_clock=0;sim._sense(cell,.15,received)
 check(cell.behavior.has("weapon_cue"),"A hungry cell retains eligible weapon cues independently of foraging")
 sim._emit_and_attack(cell,.01)
 check(sim.particles.any(func(packet):return packet.kind==Sim.TOXIN) and sim.particles.any(func(packet):return packet.kind==Sim.PORE_SUBUNIT),"Both glands fire while navigation is occupied by another need")
 receptor.hp=0
 var bursts: int=sim.particles.size();sim._emit_and_attack(cell,1)
 check(sim.particles.size()==bursts or sim.particles.slice(bursts).all(func(packet):return packet.kind==Sim.PHEROMONE),"Breaking the real receptor removes the permission to target")
 crowded_merging()
 combat_support()
 print("FEEDBACK PASS THREE: ",checks," assertions, ",failures," failures")
 quit(1 if failures else 0)

func combat_support() -> void:
 var sim=BrightWorld.new(951,0,false);var cell=sim.player
 sim.cells=[cell];cell.organs.clear();cell.chemistry.particles.clear();cell.chemistry.refresh()
 cell.body=120;cell.energy=60;cell.biomass=20;cell.update_geometry()
 cell.add_organ("feeding",0,"graze",false)
 for at in [1.2,3.2]:
  cell.add_organ("photosynthesis",at,"graze",false)
  cell.add_organ("mitochondrion",at,"graze",false)
 for kind in ["propulsion","hunting","toxin","poreforming","protection","regenerative"]:
  cell.add_organ(kind,2,"graze",false)
 var receptor: Dictionary=cell.organs.filter(func(o):return o.kind=="hunting")[0]
 var stock:=300.0
 var initial: float=cell.organic_mass()+stock
 var minimum:=INF
 for tick in 720:
  sim.time+=.25;cell.age+=.25
  for leaf in cell.organs:
   if leaf.kind!="photosynthesis":continue
   var taken: float=minf(stock,.175)
   stock-=taken;cell.chemistry.emit("carbon",taken,cell.local_point(leaf.a)*.72,-1,-1,0)
  sim._photosynthesize(cell,.25);sim._metabolize(cell,.25)
  cell.behavior["weapon_cue"]={"at":cell.position+Vector2(100,0),"id":999,"organ_id":receptor.id,"expires_at":sim.time+1,"lineage":999}
  sim._emit_and_attack(cell,.25)
  cell.spend_energy(.25*cell.PUMP_UPKEEP,cell.organs[0],"pumping")
  cell.spend_energy(.25*cell.MOTION_UPKEEP,cell.organs[5],"movement")
  cell.heal(.25)
  if tick>360:minimum=minf(minimum,cell.energy)
 var final: float=cell.organic_mass()+stock+sim.respiration_loss
 for p in sim.particles:
  if p.alive:final+=p.amount*Sim.Catalog.material(p.kind)
 check(cell.energy>10 and minimum>10 and cell.biomass>5,"Two leaves and two mitochondria support continuous toxin/pore firing, movement and protection in bright water with finite carbon")
 check(absf(final-initial)<.001,"Combat-capable photosynthesis conserves its finite supplied carbon and real secretion material")
 print("COMBAT_SUPPORT ",JSON.stringify({"ATP":cell.energy,"biomass":cell.biomass,"minimum_late_ATP":minimum,"stock":stock}))

func crowded_merging() -> void:
 var counts: Array=[]
 for signatures in [1,4]:
  var sim=fixture();sim.server_mode=true;sim.player.age=90
  var donor=Sim.Cell.new(1,sim.player.position+Vector2(1000,0));donor.lineage=sim.player.lineage_id();donor.age=90
  sim.cells.append(donor)
  var cues: Dictionary={}
  for i in signatures:cues[i+1]={"expires_at":1000.0,"report":{"id":i+1,"lineage":sim.player.lineage_id(),"at":donor.position}}
  sim.player.behavior["family_cues"]=cues
  var selected:=0
  for tick in 1000:
   sim.time+=.5;sim.player.behavior.erase("merge_order")
   sim.FamilyMerging.step(sim)
   if sim.player.behavior.has("merge_order"):selected+=1
  counts.append(selected)
  check(sim.cells.size()==2 and sim.player.ap==3,"Distant family signals never bypass physical contact or mint AP")
 check(counts[1]>counts[0]*4,"Crowded family cues substantially increase automatic merge willingness at equal elapsed time")
