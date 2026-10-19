extends RefCounted
const Sim=preload("res://scripts/simulation.gd")
const Status=preload("res://scripts/organelle_status.gd")
const Coarse=preload("res://scripts/offscreen_ecology.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
class FixedEvents:
 extends "res://scripts/simulation.gd"
 func _event_count(rate: float,dt: float) -> int:return roundi(rate*dt)
 func _secretion_needed(_cell,_organ: Dictionary,_kind: int) -> bool:return true

static func fixture(kind: String,energy: float):
 var sim=FixedEvents.new(833,0,false)
 sim.cells=[sim.player];sim.particles.clear();sim.grid.clear()
 var cell=sim.player
 cell.organs.clear();cell.body=70;cell.biomass=100;cell.energy=energy
 cell.velocity=Vector2.ZERO;cell.angular_velocity=0;cell.angle=0
 cell.target=Vector2.RIGHT;cell.facing=Vector2.RIGHT;cell.target_mouth=0
 cell.update_geometry();cell.add_organ(kind,0,"graze",false)
 sim.fluid.velocity.fill(Vector2.ZERO);sim.fluid.activity.fill(1);sim.fluid.driven=false
 sim.habitat_geometry=Sim.Habitat.new(833,sim.cells);sim.habitat_geometry.enabled=false
 return sim
static func material(sim) -> float:
 var amount: float=sim.player.organic_mass()
 for packet in sim.particles:
  if packet.alive:amount+=packet.amount*Sim.Catalog.material(packet.kind)
 return amount
static func attack_cue(sim) -> void:
 var cell=sim.player
 cell.target_id=999;cell.target_memory=1;cell.target_mode="hunt"
 cell.target_position=cell.position+Vector2(100,0)
 cell.add_organ("hunting",1,"hunt",false)
 cell.behavior["weapon_cue"]={"at":cell.target_position,"id":999,"organ_id":cell.organs[-1].id,"expires_at":sim.time+20,"score":2,"lineage":999}
 cell.organs[0]["counter_report"]={"expires_at":sim.time+20,"report":{"hostile":true,"at":cell.target_position}}

static func run(check: Callable) -> void:
 var state=fixture("propulsion",5);var cell=state.player
 cell.update_power_state()
 check.call(cell.work_capacity()==.25,"ATP shortage retains quarter operation instead of disabling organs")
 cell.energy=15;cell.update_power_state()
 check.call(cell.work_capacity()==.25,"Recovery hysteresis retains quarter activity through a partial ATP refill")
 var anatomy: Array=cell.organs.duplicate(true)
 var rng: int=state.rng.state;var behavior: Dictionary=cell.behavior.duplicate(true)
 for i in 20:Status.state(state,cell,cell.organs[0])
 check.call(cell.behavior==behavior and state.rng.state==rng and cell.organs==anatomy,"Status reads never latch power state, edit anatomy or consume ecology RNG")
 var restored=Codec.new().restore(Codec.new().capture(cell))
 check.call(restored.behavior==behavior and restored.organs==anatomy and restored.work_capacity()==.25,"Checkpoint preserves actual anatomy and a partly recovered low-power state")
 cell.energy=18;cell.update_power_state()
 check.call(cell.work_capacity()==1 and not cell.behavior.has("low_power"),"Real ATP recovery automatically restores normal work and clears the latch")
 check.call(cell.work_capacity(19)==.25,"An operation that exceeds available ATP also uses quarter capacity")
 for kind in ["propulsion","cilia"]:
  var full=fixture(kind,100);var low=fixture(kind,0)
  full._motion_cell(full.player,.001);low._motion_cell(low.player,.001)
  check.call(full.player.velocity.length()>0 and low.player.velocity.distance_to(full.player.velocity*.25)<.00001,"Zero-ATP %s still delivers a quarter of the real propulsion impulse"%kind)
  check.call(low.player.energy==0 and full.player.energy<100,"Residual propulsion never creates ATP or makes ATP negative")
  check.call(absf(Coarse._swim(low.player)/Coarse._swim(full.player)-.25)<.00001,"Coarse swimming shares the quarter-capacity motor rule")
 for kind in ["feeding","cilia"]:
  var full=fixture(kind,100);var low=fixture(kind,0)
  full._suction_cell(full.player,.001);low._suction_cell(low.player,.001)
  var peak:=0.0;var error:=0.0
  for i in full.fluid.velocity.size():
   peak=maxf(peak,full.fluid.velocity[i].length())
   error=maxf(error,low.fluid.velocity[i].distance_to(full.fluid.velocity[i]*.25))
  check.call(peak>0 and error<.00001,"Zero-ATP %s pumps the actual fluid at quarter strength"%kind)
  check.call(low.player.energy==0,"Residual pumping cannot overdraw ATP")
  if kind=="feeding":
   for sim in [full,low]:sim.fluid.velocity.fill(Vector2.ZERO)
   var a: Dictionary=Coarse.feeding_request(full,full.player,1,.8)
   var b: Dictionary=Coarse.feeding_request(low,low.player,1,.8)
   check.call(absf(b.nutrient/a.nutrient-10.0/28)<.00001,"Coarse intake retains passive capture while scaling only active pumping")
 for kind in ["feeding","acidifying","neutralizing","regenerative"]:
  var full=fixture(kind,100);var low=fixture(kind,0)
  var initial: float=material(low)
  var dt:=80.0 if kind=="feeding" else 8.0
  full._emit_and_attack(full.player,dt);low._emit_and_attack(low.player,dt)
  var normal:=0;var residual:=0
  for packet in full.particles:
   if packet.kind!=Sim.PHEROMONE:normal+=1
  for packet in low.particles:
   if packet.kind!=Sim.PHEROMONE:residual+=1
  check.call(residual>0 and normal==residual*4,"Zero-ATP %s secretes finite ordinary packets at quarter event rate"%kind)
  check.call(absf(material(low)-initial)<.00001 and low.player.energy==0,"Residual %s secretion conserves represented material without ATP overdraft"%kind)
  var stopped=fixture(kind,0);stopped.player.biomass=0
  stopped._emit_and_attack(stopped.player,dt)
  check.call(not stopped.particles.any(func(p):return p.kind!=Sim.PHEROMONE),"Quarter-capacity %s still needs actual biomass"%kind)
  stopped.player.biomass=100;stopped.player.organs[0].hp=0
  stopped._emit_and_attack(stopped.player,dt)
  check.call(not stopped.particles.any(func(p):return p.kind!=Sim.PHEROMONE),"A destroyed %s never secretes via the low-power allowance"%kind)
 for kind in ["toxin","poreforming","counterattack"]:
  var full=fixture(kind,100);var low=fixture(kind,0)
  for sim in [full,low]:attack_cue(sim);sim.player.organs[0]["burst_clock"]=.75
  full._emit_and_attack(full.player,.25);low._emit_and_attack(low.player,.25)
  check.call(is_equal_approx(full.player.organs[0].burst_clock,.5) and is_equal_approx(low.player.organs[0].burst_clock,.6875),"Low-ATP %s recharge advances at one quarter speed"%kind)
  var status: Dictionary=Status.state(low,low.player,low.player.organs[0])
  check.call(status.label.contains("25%") and status.label.contains("2.8s"),"Low-power weapon status shows real remaining recharge time")
  var initial: float=material(low);var biomass: float=low.player.biomass
  low._emit_and_attack(low.player,2.75)
  check.call(low.particles.any(func(p):return p.kind!=Sim.PHEROMONE) and absf(biomass-low.player.biomass-.18)<.00001,"Quarter-speed %s eventually fires the unchanged finite burst"%kind)
  check.call(absf(material(low)-initial)<.00001 and low.player.energy==0,"Residual weapon emission conserves material and nonnegative ATP")
  var stopped=fixture(kind,0)
  stopped._emit_and_attack(stopped.player,4)
  check.call(not stopped.particles.any(func(p):return p.kind!=Sim.PHEROMONE),"Low-power weapons cannot invent an absent target signal")
 var full=fixture("regenerative",100);var low=fixture("regenerative",0)
 for sim in [full,low]:sim.player.health=50
 var mass: float=material(low)
 full.player.heal(.01);low.player.heal(.01)
 check.call(absf(low.player.health-50-(full.player.health-50)*.25)<.00001 and low.player.health>50,"Functional repair glands repair at quarter rate even at zero ATP")
 check.call(absf(material(low)-mass)<.00001 and low.player.energy==0,"Residual repair incorporates actual tissue without creating mass or ATP")
 var absent=fixture("regenerative",0);absent.player.organs[0].hp=0;absent.player.health=50
 absent.player.heal(.01)
 check.call(absent.player.health==50,"A broken repair gland cannot grant zero-ATP active healing")
 full=fixture("hunting",100);low=fixture("hunting",0)
 for sim in [full,low]:sim.player.organs[0].blocked=1
 full._clear_receptors(full.player,1);low._clear_receptors(low.player,1)
 check.call(absf((1-low.player.organs[0].blocked-.045)/(1-full.player.organs[0].blocked-.045)-.25)<.00001,"Receptor cleaning scales active work separately from passive unbinding")
 check.call(low.player.energy==0,"Active residual receptor clearing does not overdraw ATP")
 # Recovery organs remain ATP independent, not stuck at the residual floor.
 var photo=fixture("photosynthesis",0)
 photo.player.chemistry.emit("carbon",20,photo.player.local_point(0)*.72)
 var carbon: float=photo.player.carbon
 for pulse in 3:photo._photosynthesize(photo.player,.1)
 check.call(photo.player.energy>0 and photo.player.carbon<carbon,"Unpowered photosynthesis still makes real ATP using local light and finite carbon")
 var food=fixture("mitochondrion",0)
 food.player.chemistry.emit("food",2,Vector2(28,0));food.player.chemistry.emit("oxygen",2,Vector2(28,0),-1,-1,0)
 food.player.chemistry.advance(food.player,1)
 check.call(food.player.energy>0 and food.player.substrate<2,"ATP-independent respiration can replenish a starved cell from real food")
 # If prey is the only received cue, ATP shortage no longer rejects it.
 var cues=preload("res://tests/pheromones.gd")
 var hunt=cues.isolated()
 hunt.player.energy=0;hunt.player.biomass=20;hunt.player.substrate=0
 var prey=hunt._make_cell(hunt.player.position+Vector2(100,0),"grazer")
 cues.deliver(hunt,prey);cues.listen(hunt)
 check.call(hunt.player.target_mode=="hunt" and hunt.player.target_memory>0,"A starved hunter can follow an actual local prey cue at reduced capacity")
 # Feasible respiration support becomes an investment priority after the core.
 var investor=fixture("photosynthesis",0);investor.cells=[investor.player]
 investor.lineage.root_id=investor.player.lineage_id()
 investor.investment.lineages[investor.player.lineage_id()]="producer"
 investor.player.chemistry.emit("food",2,Vector2(28,0));investor.player.chemistry.emit("oxygen",2,Vector2(28,0),-1,-1,0)
 check.call(investor.Investment.candidate(investor,investor.player).kind=="mitochondrion","Low-power investment prioritizes feasible ATP recovery after its role core")
