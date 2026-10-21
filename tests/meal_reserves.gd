extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Cell=Sim.Cell
const Chemistry=Cell.Chemistry
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize() -> void:run.call_deferred()
func build(role: String):
 var cell=Cell.new(90);cell.body=90;cell.biomass=12;cell.energy=40;cell.resource_effects_enabled=false
 cell.update_geometry();cell.membrane=Cell.Membrane.new(cell.radius,90)
 var kinds: Array=["hunting","propulsion","feeding","poreforming"] if role=="hunter" else ["feeding","cilia"] if role=="grazer" else ["photosynthesis","photosynthesis","mitochondrion"]
 for i in kinds.size():check(cell.add_organ(kinds[i],i*TAU/kinds.size(),"graze",false),"Fixture fits "+kinds[i])
 check(cell.synergy()==role,"Fixture has "+role+" synergy");cell.update_geometry()
 return cell
func endurance(role: String,food: float,seconds: float) -> Dictionary:
 var cell=build(role);cell.chemistry.emit("food",food,Vector2(18,12))
 var initial: float=cell.organic_mass()
 var sim=Sim.new(451,0,false);sim.cells=[cell];sim.player=cell;sim.automatic_reproduction=false;sim.particles.clear()
 var minimum:=INF
 for i in int(seconds*2):
  cell.age+=.5;cell.chemistry.advance(cell,.5)
  # Charge ordinary steady work as well as maintenance, without introducing food.
  cell.spend_energy(.5*(cell.operating_budget().steady-cell.atp_decay_rate()))
  cell.decay_energy(.5)
  minimum=minf(minimum,cell.energy+cell.biomass*Chemistry.RESERVE_ATP)
  if cell.energy<=0 and cell.biomass<=0 and cell.substrate<=.000001:break
 var result: Dictionary={"role":role,"meal":food,"elapsed":cell.age,"ATP":cell.energy,"biomass":cell.biomass,"food":cell.substrate,"minimum_fuel":minimum}
 check(absf(cell.organic_mass()-initial)<.00001,"Stored meal and burned reserve products conserve material")
 print("MEAL_ENDURANCE ",JSON.stringify(result));return result
func run() -> void:
 var cell=build("hunter");cell.energy=0
 cell.chemistry.receive(0,40,40,cell.position+cell.local_point(0))
 var matter: float=cell.organic_mass();var potential: float=cell.chemistry.potential()+cell.biomass*Chemistry.TISSUE_FUEL+cell.energy+cell.chemistry.heat
 cell.chemistry.advance(cell,20)
 check(cell.substrate>35,"A meal is retained beyond the retired ten-second digestive deadline")
 check(absf(cell.organic_mass()-matter)<.000001,"Digestion conserves matter")
 check(absf(cell.chemistry.potential()+cell.biomass*Chemistry.TISSUE_FUEL+cell.energy+cell.chemistry.heat-potential)<.00001,"Digestion has no unfunded energy")
 var old=Cell.new();old.biomass=0;old.energy=0;old.chemistry.emit("food",4,Vector2(20,0),-1,-1,30)
 old.chemistry.advance(old,10)
 check(old.energy+old.biomass*Chemistry.TISSUE_FUEL+old.chemistry.heat+old.raw_fuel<=30.000001,"Old saved food is never refueled by new density")
 cell.energy=0;cell.biomass=2;var before: float=cell.organic_mass()
 cell.spend_energy(10)
 check(absf(cell.biomass-1.75)<.000001 and cell.work_capacity()==1,"Reserve biomass supplies full-power work at the new finite yield")
 check(absf(cell.organic_mass()-before)<.000001,"Reserve burning retains its carbon/waste products exactly")
 var lean=build("hunter");var bulky=build("grazer")
 lean.biomass=100;bulky.biomass=100;lean.substrate=80;bulky.substrate=80;lean.update_geometry();bulky.update_geometry()
 check(lean.radius<bulky.radius and lean.mass<bulky.mass,"The same stored meal is leaner and lighter in a hunter")
 check(lean.gut_capacity()>bulky.gut_capacity(),"Hunters can retain denser raw food stores")
 check(Sim.Behavior.sated(lean) and Sim.Behavior.priority(lean,"hunt")==0,"Sated hunters stop seeking another kill")
 var contact=Cell.new(97);contact.add_organ("hunting",1.5,"hunt",false);contact.add_organ("proboscis",0,"graze",false)
 check(is_equal_approx(contact.feeding_axis(1.5),contact.organ_normal(contact.organs[1]).angle()),"Hunters face a feeding organ toward sensed prey rather than the receptor")
 var needle=build("hunter");needle.organs.filter(func(o):return o.kind=="poreforming")[0].kind="proboscis";needle.update_geometry()
 var probe: Dictionary=needle.organs.filter(func(o):return o.kind=="proboscis")[0]
 var tip: Vector2=Sim.Medium.offset(needle.position,preload("res://scripts/proboscis.gd").tip(needle,probe)).rotated(-needle.angle)
 check(tip.dot(needle.organ_normal(probe))>needle.extent(),"Feeding tip extends beyond its own star-shaped collision envelope")
 var hidden=Sim.new(921,0,false);hidden.habitat_geometry=Sim.Habitat.new(921,[]);hidden.habitat_geometry.enabled=false;hidden.spatial_queries=false
 var feeder=Cell.new(992,Vector2(400,400));feeder.add_organ("proboscis",0,"graze",false)
 var donor=Cell.new(993,preload("res://scripts/proboscis.gd").tip(feeder,feeder.organs[0])+Vector2(20,0));donor.biomass=20
 hidden.cells=[feeder,donor];hidden.player=feeder;hidden.particles.clear();hidden.camera_follows_player=false;hidden.camera_position=Vector2.ZERO;hidden.view_half=Vector2(1,1)
 hidden.offscreen_ecology.advance(hidden,feeder,.25,true)
 check(feeder.eaten>0 and feeder.substrate>0 and donor.biomass<20,"Hidden contact-feeding hunters eat real donor biomass through the same physiology path")
 var established=Cell.new(9911);established.body=400;established.biomass=0;established.update_geometry();established.membrane=Cell.Membrane.new(established.radius,9911)
 for i in 10:check(established.add_organ("protection",TAU*i/10,"graze",false),"Legacy anatomy fixture fits")
 established.body=30;established.biomass=200
 var kept: int=established.organs.size();Sim.Offscreen._resize(established)
 check(established.organs.size()==kept and established.perimeter()>=established.occupied(),"Compressed reserves retain enough membrane space for established anatomy")
 var producer=build("producer")
 var sim=Sim.new(351,0,false);sim.cells=[producer];sim.player=producer;sim.particles.clear()
 check(producer.chemistry.food_share(sim,producer)==1,"Producers always export all newly made food")
 var leaf: Dictionary=producer.organs[0];var at: Vector2=producer.local_point(leaf.a)*.72
 producer.chemistry.emit("carbon",10,at);producer.energy=20
 var m: float=producer.organic_mass();var e: float=producer.energy;var sun: float=producer.chemistry.solar_work
 producer.chemistry.photosynthesize(sim,producer,leaf,1)
 var exported:=0.0
 for packet in sim.particles:exported+=packet.amount*Sim.Catalog.material(packet.kind)
 check(exported>0 and producer.fixed_carbon>0,"Photosynthesis continues releasing real external food")
 check(absf(producer.organic_mass()+exported-m)<.000001,"Leaf growth plus exported food conserve carbon")
 check(absf((producer.biomass-12)-producer.fixed_carbon*Chemistry.LEAF_BIOMASS)<.000001,"Leaf growth is the modest direct share")
 check(producer.chemistry.solar_work>sun and producer.energy>e,"Sunlight explicitly funds food and usable ATP")
 var reserve=build("producer");reserve.energy=0;reserve.biomass=2;reserve.oxygen=1
 var stored: float=reserve.organic_mass();var gas: float=reserve.oxygen
 reserve.burn_biomass(1)
 check(absf(reserve.energy-60)<.000001 and absf(reserve.oxygen-(gas-1))<.000001,"A mitochondrion adds50% reserve ATP using real oxygen")
 check(absf(reserve.organic_mass()-stored)<.000001 and absf(reserve.chemistry.heat+reserve.energy-Chemistry.TISSUE_FUEL)<.000001,"Reserve respiratory recovery conserves matter and finite energy")
 var hunter=endurance("hunter",120,2400)
 check(hunter.elapsed>=2400 and hunter.minimum_fuel>0,"A single 120-unit kill supports a basic hunter for at least forty minutes")
 var full=endurance("hunter",480,7200)
 check(full.elapsed>=7200 and full.minimum_fuel>0,"A full hunter food store supports two hours without another meal")
 var grazer=endurance("grazer",80,1200)
 check(grazer.elapsed>=1200 and grazer.minimum_fuel>0,"Grazer meals and biomass stores bridge a twenty-minute food gap")
 if "--gpu" in OS.get_cmdline_user_args():
  var beacon:=ColorRect.new();beacon.size=Vector2(8,8);root.add_child(beacon);await process_frame;await process_frame
  var gpu=preload("res://scripts/resident_particles.gd").new();gpu.rd=RenderingServer.get_rendering_device()
  var a=build("hunter");a.chemistry.receive(0,60,60,a.local_point(0));var b=Cell.clone_state(a)
  check(preload("res://scripts/resident_cytoplasm.gd").new().attach(gpu,a.chemistry,a),"Hardware resident attachment")
  for i in 40:a.chemistry.advance(a,.25);b.chemistry.advance(b,.25)
  check(absf(a.energy-b.energy)<.00001 and absf(a.biomass-b.biomass)<.00001 and absf(a.substrate-b.substrate)<.00001,"CPU/GPU demand digestion agrees")
  check(a.chemistry.accelerator.exports==0,"Storage digestion never exports a GPU pose mirror")
  a.chemistry.ensure_cpu()
  var x=build("producer");x.energy=0;x.biomass=2;x.oxygen=1;var y=Cell.clone_state(x)
  check(preload("res://scripts/resident_cytoplasm.gd").new().attach(gpu,x.chemistry,x),"Resident reserve oxygen ownership")
  x.burn_biomass(.5);y.burn_biomass(.5)
  check(absf(x.energy-y.energy)<.000001 and absf(x.oxygen-y.oxygen)<.000001,"CPU/GPU biomass respiration agrees")
  x.chemistry.ensure_cpu();gpu.close()
 print("MEAL_RESERVES: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
