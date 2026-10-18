extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Supply=preload("res://scripts/ambient_carbon.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
var checks:=0
var failures:=0
class LightWorld:
 extends "res://scripts/simulation.gd"
 var illumination:=0.02
 func light_at(_at: Vector2) -> float:return illumination

func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize() -> void:run.call_deferred()
func fixture(at: Vector2,mutation: String="",leaves: int=1,extra: int=0,mito: int=0):
 var sim=LightWorld.new(951,0,false);var cell=sim.player
 sim.cells=[cell];sim.particles.clear();sim.grid.clear()
 sim.server_mode=true;sim.automatic_reproduction=false
 sim.habitat_geometry=Sim.Habitat.new(951,sim.cells);sim.habitat_geometry.enabled=false
 cell.organs.clear();cell.biomass=0;cell.energy=0;cell.body=120 if extra>0 else 30;cell.health=23;cell.starvation_seconds=2400
 cell.chemistry.particles.clear();cell.chemistry.refresh();cell.position=at;cell.angle=0;cell.update_geometry()
 cell.add_organ("feeding",0,"graze",false)
 for i in leaves:
  cell.add_organ("photosynthesis",1.2+i*2,"graze",false);cell.organs[-1].mutation=mutation
 for i in extra:cell.add_organ("protection",3.2+i*.2,"graze",false)
 for i in mito:cell.add_organ("mitochondrion",.4+i,"graze",false)
 sim.camera_position=at;sim.camera_views=[Vector4(at.x,at.y,500,500)]
 if sim.kernels!=null:sim.kernels.set_activity_views(sim.camera_views,true)
 sim.ambient_carbon_enabled=true
 return sim

func advance(sim,seconds: float,external: bool=true) -> Dictionary:
 var cell=sim.player;var fixed: float=cell.fixed_carbon;var energy: float=cell.energy
 var minimum:=INF
 for step in int(seconds*2):
  sim.time+=.5;sim.transport_clock+=.5;sim.revision+=1;cell.age+=.5;cell.activity=1
  if external:
   Supply.step(sim);sim.grid.rebuild(sim.particles);sim._feed(cell)
  else:
   # Exact finite supplied-carbon budget fixture; ATP/tissue cannot be assigned.
   for leaf in cell.organs:
    if leaf.kind=="photosynthesis":
     cell.chemistry.emit("carbon",.7,cell.local_point(leaf.a)*.72)
     cell.chemistry.emit("oxygen",2,cell.local_point(leaf.a)*.72)
  sim._photosynthesize(cell,.5);sim._metabolize(cell,.5)
  # Ordinary oral pumping, with the shared low-power floor and paid ATP.
  cell.update_power_state()
  cell.spend_energy(.5*cell.PUMP_UPKEEP*cell.work_capacity(),cell.organs[0],"pumping")
  cell.heal(.5);cell.chemistry.excrete(sim,cell,.5)
  if step%20==0:sim._compact_particles();sim.grid.rebuild(sim.particles)
  if step>int(seconds):minimum=minf(minimum,cell.energy)
 return {"ATP":cell.energy,"biomass":cell.biomass,"health":cell.health,"starvation":cell.starvation_seconds,"fixed":cell.fixed_carbon-fixed,"energy_change":cell.energy-energy,"min_late_ATP":minimum}

func run() -> void:
 var test=fixture(Vector2(320,320));test.time=5
 var before: float=test.external_input;Supply.step(test)
 check(test.particle_count()==Supply.COUNT,"Atmospheric exchange creates at most one real carbon parcel per water tile")
 var total:=0.0
 for packet in test.particles:total+=packet.amount
 check(absf(total-(test.external_input-before))<.00001 and total==test.ambient_carbon_added,"All environmental carbon has a matching explicit material-source debit")
 var count: int=test.particle_count();test.time=10;Supply.step(test);test._compact_particles()
 check(test.particle_count()==count,"Existing dissolved-carbon parcels are replenished without particle-count growth")
 var full=fixture(Vector2(320,320));full.time=5
 full.spawn_particle(Sim.CARBON,Vector2(32,32),Vector2.ZERO,20)
 Supply.step(full)
 check(full.particles[0].amount<20 and full.particles[0].amount>Supply.SATURATION and full.ambient_carbon_removed>0,"Oversaturated water releases finite carbon to air without overshooting equilibrium")
 var total_after:=0.0
 for packet in full.particles:
  if packet.alive:total_after+=packet.amount
 check(absf(total_after+full.respiration_loss-full.external_input-20)<.00001,"Atmospheric inflow and degassing both balance represented material")
 var serializable=Sim.new(951,0,false)
 for key in ["particles","time","ambient_carbon_enabled","ambient_carbon_at","ambient_carbon_due","ambient_carbon_added","ambient_carbon_removed","external_input"]:serializable.set(key,test.get(key))
 var saved=Codec.new().restore(Codec.new().capture(serializable))
 var source: float=saved.external_input;var packets: int=saved.particle_count()
 Supply.step(saved)
 check(saved.external_input==source and saved.particle_count()==packets,"Save/restart retains source clock and saturation without a duplicate grant")
 if test.kernels!=null:
  var pooled=fixture(Vector2(320,320));pooled.spawn_particle(Sim.CARBON,Vector2(32,32),Vector2.ZERO,2)
  check(pooled.enable_particle_pool(),"Native reference owns its exterior pool")
  pooled.time=5;Supply.step(pooled)
  var matter:=0.0
  for packet in pooled.kernels.pool_snapshots():
   if packet.alive:matter+=packet.amount
  check(absf(matter+pooled.respiration_loss-pooled.external_input-2)<.00001,"Native numeric source obeys the same open-system material accounting")
 var unpowered=fixture(Vector2(320,320));var x: float=unpowered.player.biomass
 unpowered.automatic_reproduction=true;unpowered.player.biomass=100;unpowered.player.energy=0
 unpowered._fund_reproduction(unpowered.player,1)
 check(unpowered.player.biomass==100 and unpowered.player.brood_mass==0,"Starved cells stop diverting tissue into automatic reproduction")
 # All leaves, positions on and between source sites, both sides of world wrap,
 # darkest supported water and bright water, and existing severe starvation.
 for mutation in ["","shade_leaf","sun_leaf"]:
  for at in [Vector2(320,320),Vector2(352,352),Vector2(4095,2559)]:
   var sim=fixture(at,mutation)
   var report:=advance(sim,600)
   print("BASELINE ",mutation," ",at," ",report)
   check(report.health>95 and report.ATP>1 and report.biomass>1 and report.starvation<1200,"A single "+mutation+" leaf physically recovers an empty, injured cell at "+str(at))
 var sunny=fixture(Vector2(352,352),"sun_leaf");sunny.illumination=1
 var bright:=advance(sunny,300)
 check(bright.health>95 and bright.ATP>1,"A single sun leaf also recovers in bright water")
 var old=Sim.new(951,0,false);old.time=12345;old.enable_ambient_carbon()
 check(old.ambient_carbon_at==old.time and old.ambient_carbon_due==old.time+5,"Enabling the source on an old pond starts a fresh interval, not historical catch-up")
 var investor=fixture(Vector2(320,320));investor.player.organs=investor.player.organs.filter(func(o):return o.kind!="photosynthesis")
 investor.investment.cells[investor.player.id]="hunter"
 check(investor.Investment.candidate(investor,investor.player).kind=="photosynthesis","An opted-in starving role establishes energy support before extra anatomy")
 investor.player.add_organ("photosynthesis",1,"graze",false);investor.player.carbon=2
 check(investor.Investment.candidate(investor,investor.player).kind=="photosynthesis","Any opted-in role can add another leaf when its existing energy support is insufficient")
 investor.player.substrate=2;investor.player.oxygen=2
 check(investor.Investment.candidate(investor,investor.player).kind=="mitochondrion","Local food and oxygen favor efficient respiration before further expansion")
 investor.managed_cells=[investor.player.id]
 check(investor.Investment.candidate(investor,investor.player).is_empty(),"Connected selected cells remain manual even during an energy shortage")
 var lean=fixture(Vector2(320,320),"sun_leaf",1,6)
 var lean_result:=advance(lean,180,false)
 var unassisted=fixture(Vector2(320,320),"sun_leaf",3,6,0)
 var unassisted_result:=advance(unassisted,180,false)
 var supported=fixture(Vector2(320,320),"sun_leaf",3,6,1)
 var supported_result:=advance(supported,180,false)
 print("COMPLEXITY one=",lean_result," supported=",supported_result)
 check(lean_result.ATP<1 and supported_result.ATP>10,"Many support organs exceed a single leaf's budget; more leaves and mitochondria fund them")
 check(unassisted_result.ATP<supported_result.ATP,"Mitochondrial respiration adds useful headroom to the same multi-leaf build")
 var plain=fixture(Vector2(320,320),"",1,0)
 var mitochondrion=fixture(Vector2(320,320),"",1,0,1)
 var p:=advance(plain,180,false);var m:=advance(mitochondrion,180,false)
 check(m.ATP>p.ATP,"A mitochondrion provides a net ATP benefit after its own maintenance")
 print("BASELINE_SURVIVAL: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
