extends RefCounted
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
static func run(check: Callable) -> void:
 preload("res://tests/shade_steering.gd").run(check)
 preload("res://tests/behavior_tree.gd").run(check)
 var sim=Sim.new(591,0,false);sim.server_mode=true;sim.cells=[sim.player]
 sim.player.add_organ("feeding",0,"graze",false)
 var bodies: Array=[]
 for i in 100:
  var cell=Sim.Cell.new(100+i);cell.lineage=cell.id;cell.add_organ("feeding",0,"graze",false)
  sim.cells.append(cell);bodies.append(cell)
 sim.Investment.npc_assignments(sim)
 var counts: Dictionary={"hunter":0,"producer":0,"grazer":0}
 for value in sim.investment.npc.values():counts[value]+=1
 check.call(counts=={"hunter":10,"producer":45,"grazer":45},"NPC strategies use 10% hunters and equal producer/grazer quotas")
 var before: Dictionary=sim.investment.npc.duplicate()
 sim.Investment.npc_assignments(sim)
 check.call(before==sim.investment.npc,"Unchanged population retains each NPC strategy across scheduling")
 for cell in bodies:
  var candidate: Dictionary=sim.Investment.candidate(sim,cell)
  check.call(not candidate.is_empty() and candidate.kind==sim.Investment.PRIORITIES[before[cell.id]][0],"NPC purchases obey their strategy instead of the random catalog")
 for body in bodies:sim._family_ledger(body).progression.points=0
 var ledger=sim._family_ledger(bodies[0]);ledger.progression.points=1
 var input: float=sim.external_input;var mass: float=bodies[0].organic_mass()
 sim.step_autonomous_builds()
 check.call(ledger.progression.points==0 and is_equal_approx(bodies[0].organic_mass()-mass,sim.external_input-input),"Strategy buys exactly one ordinary AP-funded organ with conserved construction input")
 sim.managed_lineages=[bodies[1].lineage_id()]
 sim.player=bodies[1]
 check.call(sim.Investment.set_strategy(sim,"lineage","producer"),"Owner can save a family investment strategy")
 check.call(sim.Investment.candidate(sim,bodies[1]).kind=="photosynthesis","An unattended player cell uses the explicit family policy")
 sim.managed_cells=[bodies[1].id]
 check.call(sim.Investment.candidate(sim,bodies[1]).is_empty(),"A connected selected body keeps its AP for manual purchases")
 sim.managed_cells=[]
 check.call(sim.Investment.set_strategy(sim,"cell","grazer") and sim.Investment.candidate(sim,bodies[1]).kind=="cilia","Per-cell policy overrides its family policy")
 check.call(not sim.Investment.set_strategy(sim,"other","hunter") and not sim.Investment.set_strategy(sim,"lineage","random"),"Unknown policy scopes and values are rejected")
 var restored=Codec.new().restore(Codec.new().capture(sim))
 check.call(restored.investment==sim.investment and restored.managed_cells.is_empty(),"Policies and quota assignments persist; connection selection does not")
 var owned: Dictionary=sim.Investment.owned_settings(sim,bodies[1].lineage_id())
 check.call(owned.npc.is_empty() and owned.cells.size()==1 and owned.lineages.size()==1,"A view exposes only its owner's investment settings")
 # Photosynthesis partitions actual newly fixed food, with no duplicate carbon credit.
 var photo=Sim.Cell.new(501);photo.add_organ("photosynthesis",0,"graze",false)
 photo.chemistry.emit("carbon",8,photo.local_point(0)*.72,-1,-1,0)
 sim.particles=[];sim.grid.rebuild([]);sim.player=photo
 photo.chemistry.photosynthesize(sim,photo,photo.organs[0],1)
 var outside:=0.0
 for packet in sim.particles:
  if packet.kind==Sim.NUTRIENT:outside+=packet.amount
 check.call(photo.fixed_carbon>0 and absf(photo.substrate-photo.fixed_carbon*.65*.75)<.000001 and absf(outside-photo.fixed_carbon*.65*.25)<.000001,"Photosynthesis keeps 75% of its food inside and releases 25% outside")
 check.call(absf(photo.carbon+photo.fixed_carbon-8)<.000001,"Both food shares debit the same finite carbon once")
 var ordinary=Sim.Cell.new(502);ordinary.chemistry.emit("food",2,Vector2(28,0));ordinary.chemistry.emit("oxygen",2,Vector2(28,0),-1,-1,0)
 var mitochondrial=Sim.Cell.clone_state(ordinary);mitochondrial.id=504;mitochondrial.lineage=504;mitochondrial.add_organ("mitochondrion",1,"graze",false)
 var energy: float=ordinary.energy;var biomass: float=mitochondrial.biomass;var heat: float=mitochondrial.chemistry.heat;var fuel: float=mitochondrial.raw_fuel
 ordinary.chemistry.advance(ordinary,1);mitochondrial.chemistry.advance(mitochondrial,1)
 check.call(mitochondrial.energy>ordinary.energy and mitochondrial.oxygen==ordinary.oxygen,"Mitochondria improve oxygen-dependent ATP yield, using actual oxygen")
 check.call(absf(mitochondrial.energy-energy+(mitochondrial.biomass-biomass)*7.5+mitochondrial.raw_fuel+mitochondrial.chemistry.heat-heat-fuel)<.000001,"Extra mitochondrial ATP stays within the original food fuel budget")
 check.call(mitochondrial.organ_local_position(mitochondrial.organs[-1]).length()<mitochondrial.radius*.8,"Mitochondria are placed inside the cell rather than on its membrane")
 var ferment=Sim.Cell.new(503);ferment.chemistry.emit("food",2,Vector2(28,0));var ferment_mito=Sim.Cell.clone_state(ferment);ferment_mito.add_organ("mitochondrion",1,"graze",false)
 ferment.chemistry.advance(ferment,1);ferment_mito.chemistry.advance(ferment_mito,1)
 check.call(ferment.energy==ferment_mito.energy,"Without oxygen, mitochondria do not improve fermentation")
 # Selective and protected attack policy travels with emitted material identity.
 sim.cells=[photo,ordinary,mitochondrial];sim.player=photo;sim.lineage.root_id=photo.lineage_id()
 var alias: int=sim._attack_owner(photo,true);sim.prepare_combat_rules()
 var hp: float=ordinary.health
 ordinary.damage(5,0,alias)
 check.call(ordinary.health==hp and not ordinary.accepts_attack(alias),"Counterattack toxin cannot harm an unarmed cell at contact")
 ordinary.add_organ("toxin",0,"graze",false);ordinary.damage(50,PI,alias)
 check.call(ordinary.health<hp,"Counterattack toxin can harm a cell with offensive anatomy")
 check.call("sanctuary" not in sim.Cell.KINDS and not photo.add_organ("sanctuary",1,"graze",false),"Removed Sanctuary cannot be constructed")
 restored=Codec.new().restore(Codec.new().capture(sim));restored.prepare_combat_rules()
 check.call(restored.attack_sources==sim.attack_sources,"Counterattack's immutable source permissions survive restart without Sanctuary")
 preload("res://tests/retired_history.gd").run(check)
