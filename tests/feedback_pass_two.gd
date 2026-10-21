extends RefCounted
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
static func run(check: Callable) -> void:
 mitochondrial_upgrade(check)
 preload("res://tests/shade_steering.gd").run(check)
 preload("res://tests/behavior_tree.gd").run(check)
 preload("res://tests/low_power.gd").run(check)
 var sim=Sim.new(591,0,false);sim.server_mode=true;sim.cells=[sim.player]
 sim.player.add_organ("feeding",0,"graze",false)
 var bodies: Array=[]
 for i in 100:
  var cell=Sim.Cell.new(100+i);cell.lineage=cell.id;cell.add_organ("feeding",0,"graze",false)
  sim.cells.append(cell);bodies.append(cell)
 sim.Investment.npc_assignments(sim)
 check.call(sim.investment.npc.is_empty(),"No NPC is automatically assigned an investment policy")
 for cell in bodies:
  check.call(sim.Investment.strategy(sim,cell)==sim.Investment.balanced_path(sim,cell),"Unchosen NPCs follow the stable Balanced mix without a saved quota assignment")
 sim.investment.cells[bodies[0].id]="grazer"
 for body in bodies:body.ap=0
 var ledger=sim._family_ledger(bodies[0]);bodies[0].ap=1
 var input: float=sim.external_input;var mass: float=bodies[0].organic_mass()
 sim.managed_cells=bodies.slice(1).map(func(cell):return cell.id)+[sim.player.id]
 sim.step_autonomous_builds()
 sim.managed_cells=[]
 check.call(bodies[0].ap==1 and is_equal_approx(bodies[0].organic_mass()-mass,sim.external_input-input),"Strategy buys one ordinary first-free organ with conserved construction input")
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

static func mitochondrial_upgrade(check: Callable) -> void:
 var initial_biomass:=10.0
 for count in [0,1,2,8,12]:
  var cell=Sim.Cell.new(680+count);cell.body=10000;cell.biomass=initial_biomass;cell.energy=0;cell.update_geometry()
  for i in count:check.call(cell.add_organ("mitochondrion",i*.5,"graze",false),"Large-cell fixture installs a real mitochondrion")
  var factor: float=1+minf(4,count*.5)
  check.call(is_equal_approx(cell.mitochondrial_efficiency(),factor),"Healthy mitochondrial capacity stacks additively with its finite ceiling")
  cell.chemistry.emit("food",1,Vector2.ZERO);cell.chemistry.emit("oxygen",1,Vector2.ZERO,-1,-1,0)
  var fuel: float=cell.raw_fuel
  cell.chemistry.advance(cell,10)
  check.call(absf(cell.energy-2.25*factor)<.000001,"Mitochondria multiply ordinary aerobic ATP without throughput changes")
  check.call(absf(cell.biomass-initial_biomass-.7)<.000001 and cell.substrate==0 and cell.oxygen==0,"Every mitochondrial count keeps the same biomass, food and oxygen use")
  check.call(absf(cell.energy+(cell.biomass-initial_biomass)*7.5+cell.raw_fuel+cell.chemistry.heat-fuel)<.000001,"Mitochondrial bonus comes only from finite otherwise dissipated fuel")
 var damaged=Sim.Cell.new(700);damaged.energy=0;damaged.add_organ("mitochondrion",0,"graze",false)
 damaged.organs[0].hp=damaged.organs[0].max_hp*.5
 check.call(is_equal_approx(damaged.mitochondrial_efficiency(),1.25) and damaged.energy==0,"Damage halves the bonus; reading capacity spends no ATP")
 damaged.organs[0].hp=0
 check.call(damaged.mitochondrial_efficiency()==1,"A destroyed mitochondrion adds no efficiency")
 for fuel in [0.0,7.5,18.0]:
  for oxygen_at in [Vector2.ZERO,Vector2(1000,0)]:
   var plain=Sim.Cell.new(710);plain.energy=0;plain.biomass=0;plain.body=10000;plain.update_geometry()
   plain.chemistry.emit("food",1,Vector2.ZERO,-1,-1,fuel);plain.chemistry.emit("oxygen",1,oxygen_at,-1,-1,0)
   var mito=Sim.Cell.clone_state(plain);mito.add_organ("mitochondrion",1,"graze",false)
   plain.chemistry.advance(plain,10);mito.chemistry.advance(mito,10)
   check.call(absf(mito.biomass-plain.biomass)<.000001 and mito.oxygen==plain.oxygen and mito.substrate==plain.substrate,"Efficiency never diverts growth or consumes more food/oxygen")
   check.call(absf(mito.energy+mito.biomass*7.5+mito.raw_fuel+mito.chemistry.heat-fuel)<.000001,"Exhausted, legacy and fresh meals all retain exact energy accounting")
   if fuel<=7.5 or oxygen_at!=Vector2.ZERO:check.call(absf(mito.energy-plain.energy)<.000001,"No spare fuel or no local oxygen gives no unfunded mitochondrial ATP")
 var sim=Sim.new(688,0,false);sim.cells=[sim.player];sim.particles=[];sim.grid.clear();sim.evolution.enabled=false
 var cell=sim.player;cell.chemistry.particles.clear();cell.chemistry.refresh()
 cell.chemistry.emit("food",2,Vector2.ZERO,-1,-1,9)
 var before: float=(cell.organic_mass()-cell.substrate)*7.5+cell.raw_fuel
 var encoded=Codec.new().capture(sim);var restored=Codec.new().restore(encoded)
 check.call(restored.player.chemistry.particles==cell.chemistry.particles,"Checkpoint upgrade does not refill or alter saved food")
 sim._die(cell)
 var released:=0.0
 for packet in sim.particles:
  if packet.alive and packet.kind==Sim.NUTRIENT:released+=minf(packet.amount,packet.capacity)*Sim.Cell.Chemistry.FOOD_FUEL
 check.call(absf(released-before)<.000001,"Lysis preserves legacy food and tissue fuel without gaining the fresh-food reserve")
 sim.particles=[];sim.grid.clear();sim._emit_material(Sim.NUTRIENT,Vector2.ZERO,3)
 released=0
 for packet in sim.particles:released+=minf(packet.amount,packet.capacity)*Sim.Cell.Chemistry.FOOD_FUEL
 check.call(absf(released-3*7.5)<.000001,"Tissue leaks retain their own energy rather than gaining fresh-food energy")
