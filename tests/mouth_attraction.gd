extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Transport=preload("res://scripts/particle_transport.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
var checks:=0
var failures:=0
func check(ok: bool,why: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func forage(cell,organ: Dictionary) -> void:
 cell.drive_active=true;cell.target_mode="graze";cell.target_memory=1;cell.target_organ_id=organ.id

func run() -> void:
 Fixture.load_native()
 activity_upkeep()
 var sim=Sim.new(59,0,false);sim.server_mode=true;sim.cells=[sim.player];sim.player.organs.clear()
 var a=sim.player;a.position=Vector2(500,500);a.energy=100;a.biomass=20
 a.add_organ("feeding",0,"graze",false)
 var organ=a.organs[0];var reach: float=a.oral_reach(organ)
 check(reach>50 and reach<150,"Ordinary oral reach is about one third of the oversized previous range")
 var small=Sim.Cell.new(3);small.body=30;small.biomass=0;small.update_geometry()
 check(small.oral_reach(organ)<reach,"Smaller cells have a smaller suction zone")
 sim.fluid.velocity.fill(Vector2.ZERO)
 sim.fluid.prepare_attractors(sim.cells)
 var before: float=a.energy
 sim._suction_cell(a,.2)
 check(sim.fluid.particle_flow().size()==2560 and a.energy==before,"Idle mouths produce no attraction and spend no pumping ATP")
 forage(a,organ);sim.fluid.prepare_attractors(sim.cells)
 sim._suction_cell(a,.2)
 check(a.energy<before and sim.fluid.particle_flow().size()==2562,"Active foraging enables attraction and pays pumping ATP")
 for mode in ["hunt","light","flee","evade","kin_toward","acid"]:
  a.target_mode=mode;sim.fluid.prepare_attractors(sim.cells)
  before=a.energy;sim._suction_cell(a,.2)
  check(sim.fluid.particle_flow().size()==2560 and a.energy==before,"Switching to "+mode+" shuts off attraction and pumping cost")
 forage(a,organ);a.target_memory=0;sim.fluid.prepare_attractors(sim.cells)
 check(sim.fluid.particle_flow().size()==2560,"Expired food intent cannot leave a stale pump")
 forage(a,organ);var active: Dictionary=sim.offscreen_ecology.feeding_request(sim,a,.5,1)
 a.drive_active=false;var idle: Dictionary=sim.offscreen_ecology.feeding_request(sim,a,.5,1)
 check(active.nutrient>idle.nutrient and active.oxygen>0 and idle.oxygen>0,"Coarse feeding removes pump capture while retaining passive intake and gas exchange")
 forage(a,organ);sim.fluid.prepare_attractors(sim.cells)
 var mouth: Vector2=a.pore_center(organ);var at: Vector2=mouth+Vector2(reach*.5,0)
 var nutrient: Vector2=sim.fluid.transport_sample(at,0)
 check(sim.fluid.transport_sample(at,3)==sim.fluid.sample(at),"Pheromones receive zero oral pull")
 for kind in [1,2,4,5,6,7,8,9,10]:
  check((sim.fluid.transport_sample(at,kind)-nutrient*.2).length()<.0001,"Non-nutrient species "+str(kind)+" receives exactly20% pull")
 check(sim.fluid.transport_sample(mouth+Vector2(reach+1,0),0)==Vector2.ZERO,"Suction has a hard local radius without grid bleed")
 var water=sim.fluid.velocity.duplicate();var velocity=a.velocity
 var b=Sim.Cell.new(2);b.biomass=20;b.energy=100;b.add_organ("feeding",PI,"graze",false)
 b.position=a.position+Vector2(a.extent()+b.extent()+90,0);b.previous_position=b.position
 forage(b,b.organs[0]);sim.cells.append(b);sim.fluid.prepare_attractors(sim.cells)
 var other: Vector2=b.pore_center(b.organs[0]);var middle: Vector2=(mouth+other)*.5
 check(sim.fluid.transport_sample(middle,0).length()>1,"Equal facing mouths have a deterministic nonzero pull")
 for offset in [-4.0,0.0,4.0]:
  var p: Vector2=middle+Vector2(0,offset)
  for i in 180:p=Transport.advect(p,Vector2.ZERO,sim.fluid,1.0/60,0)
  check(minf(p.distance_to(mouth),p.distance_to(other))<24,"Food between two mouths reaches one intake")
 sim.fluid.prepare_attractors([b,a]);var reversed: Vector2=sim.fluid.transport_sample(middle,0)
 sim.fluid.prepare_attractors([a,b])
 check(sim.fluid.transport_sample(middle,0)==reversed,"Stable cell IDs resolve ties independently of array order")
 check(sim.fluid.velocity==water and a.velocity==velocity,"Attractors never change actual water or cell velocity")
 a.substrate=a.gut_capacity();sim.fluid.prepare_attractors(sim.cells)
 check(sim.fluid.particle_flow().size()==2562,"A full gut stops attracting food away from a hungry neighbor")
 a.substrate=0;sim.fluid.prepare_attractors(sim.cells)
 if ClassDB.class_exists("PrimordiaKernels"):
  var kernels=preload("res://scripts/backend.gd").create()
  for kind in [0,1,3,5]:
   var source: Dictionary={"p":middle,"previous":middle,"v":Vector2.ZERO,"kind":kind,"amount":.3,"capacity":.3,"alive":true,"age":0.0,"angle":0.0,"previous_angle":0.0,"spin":0.0,"direction":Vector2.RIGHT}
   var native: Dictionary=source.duplicate();var reference: Dictionary=source.duplicate()
   var r1:=RandomNumberGenerator.new();r1.seed=531
   var r2:=RandomNumberGenerator.new();r2.seed=531
   Transport.advance(reference,sim.fluid,.03,1,r1)
   kernels.transport([native],[0],sim.fluid.particle_flow(),middle,Vector2(500,500),.03,1,r2,-1,false)
   check(native.p.distance_to(reference.p)<.0001,"Native/script species-weighted attraction agrees for "+str(kind))
 # Identical random draws prove chemical signals are unaffected even during long catch-up.
 for elapsed in [.03,1.25]:
  var source: Dictionary={"p":middle,"previous":middle,"v":Vector2(12,7),"kind":3,"amount":.3,"capacity":.3,"alive":true,"age":0.0,"angle":0.0,"previous_angle":0.0,"spin":0.0,"direction":Vector2.RIGHT}
  var tracer: Dictionary=source.duplicate();var control: Dictionary=source.duplicate()
  var r1:=RandomNumberGenerator.new();r1.seed=741
  var r2:=RandomNumberGenerator.new();r2.seed=741
  var water_only=Sim.Medium.new();water_only.velocity=sim.fluid.velocity.duplicate()
  Transport.advance(tracer,sim.fluid,elapsed,1,r1);Transport.advance(control,water_only,elapsed,1,r2)
  check(tracer.p==control.p and r1.state==r2.state,"Script pheromones match plain water exactly at"+str(elapsed))
  if ClassDB.class_exists("PrimordiaKernels"):
   var kernels=preload("res://scripts/backend.gd").create()
   var native: Dictionary=source.duplicate();r1.seed=741
   kernels.transport([native],[0],sim.fluid.particle_flow(),middle,Vector2(500,500),elapsed,1,r1,-1,false)
   check(native.p.distance_to(control.p)<.0001,"Native pheromones match plain water at"+str(elapsed))
 if RenderingServer.get_rendering_device()!=null:
  await gpu(sim,middle)
  await environment_tail(sim,middle)
  await respiration_gpu()
 print("MOUTH_ATTRACTION: %d assertions, %d failures" % [checks,failures])
 quit(0 if failures==0 else 1)
func gpu(sim,middle: Vector2) -> void:
 var data:=Fixture.make(4)
 for i in 4:
  data[i*12]=middle.x;data[i*12+1]=middle.y;data[i*12+2]=0;data[i*12+3]=0
  data[i*12+4]=0;data[i*12+5]=0;data[i*12+7]=[0,1,3,5][i]
 var field: PackedVector2Array=sim.fluid.particle_flow()
 var gpu=preload("res://scripts/resident_particles.gd").new();gpu.initialize(data,field)
 var status: Array=await gpu.ready
 check(status[0],"Resident GPU accepts bounded analytic mouth descriptors")
 if not status[0]:gpu.close();await gpu.closed;return
 var reference=null
 var water_reference=null
 if ClassDB.class_exists("PrimordiaResidentReference"):
  reference=ClassDB.instantiate("PrimordiaResidentReference")
  check(reference.configure(data,field,2),"Native resident reference accepts the same descriptors")
  water_reference=ClassDB.instantiate("PrimordiaResidentReference")
  check(water_reference.configure(data,sim.fluid.velocity,2),"Plain-water control uses the same resident initial state")
 for i in 12:
  gpu.advance(1.0/60,i)
  if reference!=null:reference.advance(1.0/60,i);water_reference.advance(1.0/60,i)
  await process_frame
 await RenderingServer.frame_post_draw
 gpu.snapshot();var actual: PackedFloat32Array=await gpu.snapshot_ready
 if reference!=null:check(Fixture.compare(reference.snapshot(),actual).passed,"Actual resident GPU/native agree across nutrient, oxygen, pheromone and carbon")
 if water_reference!=null:
  var water_only: PackedFloat32Array=water_reference.snapshot()
  check(Vector2(actual[24]-water_only[24],actual[25]-water_only[25]).length()<.001,"Resident GPU pheromones match water-only motion and diffusion")
 check(absf(actual[0]-middle.x)>4,"Resident food escapes the competing-mouth midpoint")
 check(gpu.readbacks==1,"Attraction needs no gameplay particle readback")
 gpu.close();await gpu.closed

func environment_tail(sim,middle: Vector2) -> void:
 var data:=PackedFloat32Array([middle.x,middle.y,0,0,0,0,0,0,8,.3,.3,0])
 var acid:=PackedFloat32Array();acid.resize(2560)
 var water: PackedVector2Array=sim.fluid.velocity
 var field: PackedVector2Array=sim.fluid.particle_flow()
 var gpu=preload("res://scripts/resident_particles.gd").new()
 check(gpu.configure_interactions("chemistry") and gpu.configure_exchange() and gpu.configure_perception() and gpu.configure_chemistry(acid,59),"Small live-pipeline mouth fixture configures")
 gpu.initialize(data,water)
 var status: Array=await gpu.ready
 check(status[0],"Live pipeline starts with plain water")
 if not status[0]:gpu.close();await gpu.closed;return
 var reference=ClassDB.instantiate("PrimordiaResidentReference")
 for inputs in [field,water]:
  check(gpu.environment(inputs,acid),"Live environment accepts added and removed mouth descriptors")
  reference.configure(data,inputs,1);reference.advance(.03,0)
  gpu.advance(.03,0)
  await process_frame;await RenderingServer.frame_post_draw
  gpu.snapshot();data=await gpu.snapshot_ready
  var expected: PackedFloat32Array=reference.snapshot()
  check(Vector2(data[0]-expected[0],data[1]-expected[1]).length()<.001,"Live environmental update applies exact mouth count without stale attraction")
 gpu.close();await gpu.closed

class WorkEvents:
 extends "res://scripts/simulation.gd"
 var secretion_needed:=false
 func _event_count(rate: float,dt: float) -> int:return roundi(rate*dt)
 func _secretion_needed(_cell,_organ: Dictionary,_kind: int) -> bool:return secretion_needed

func work_fixture(kind: String):
 var sim=WorkEvents.new(71,0,false)
 sim.cells=[sim.player];sim.particles.clear();sim.grid.clear()
 var cell=sim.player;cell.organs.clear();cell.body=70;cell.biomass=20;cell.energy=40;cell.health=100
 cell.chemistry.assign("food",0);cell.chemistry.assign("oxygen",0);cell.chemistry.assign("carbon",0)
 cell.add_organ(kind,0,"graze",false);cell.drive_active=false;cell.target=Vector2.ZERO;cell.target_memory=0
 cell.update_geometry();sim.fluid.velocity.fill(Vector2.ZERO);sim.fluid.driven=false
 sim.habitat_geometry=Sim.Habitat.new(71,sim.cells);sim.habitat_geometry.enabled=false
 return sim

func charged(cell,id: int) -> float:
 var rates: Dictionary=cell.energy_budget.rates(cell.age)
 return rates.organs.get(id,0.0)*rates.seconds

func activity_upkeep() -> void:
 for kind in Sim.Cell.KINDS:
  var sim=work_fixture(kind);var cell=sim.player;var organ: Dictionary=cell.organs[0]
  sim._metabolize(cell,.25)
  check(charged(cell,organ.id)==0,"Idle "+kind+" has no installation ATP tax")
  var rates: Dictionary=cell.energy_budget.rates(cell.age)
  check(rates.categories.get("upkeep",0)>0 and rates.categories.get("turnover",0)>0,"Basic cell maintenance and ATP turnover remain with idle "+kind)
 var gland=work_fixture("poreforming");var cell=gland.player;var organ: Dictionary=cell.organs[0]
 gland._emit_and_attack(cell,1)
 check(charged(cell,organ.id)==0 and not organ.has("emission_serial"),"A pore gland waiting for a viable cue spends nothing")
 cell.add_organ("hunting",PI,"hunt",false)
 cell.behavior.weapon_cue={"organ_id":cell.organs[1].id,"lineage":999,"expires_at":gland.time+5,"at":cell.position+Vector2(100,0)}
 var mass: float=cell.biomass;gland._emit_and_attack(cell,1)
 check(charged(cell,organ.id)>2 and cell.biomass<mass and organ.get("emission_serial",0)==1,"An actual pore burst pays ATP/work and finite material")
 # Barely-funded secretion must reserve its output material before burning ATP.
 var tight=work_fixture("poreforming");cell=tight.player;organ=cell.organs[0]
 cell.add_organ("hunting",PI,"hunt",false);cell.biomass=.18;cell.energy=2
 cell.behavior.weapon_cue={"organ_id":cell.organs[1].id,"lineage":999,"expires_at":tight.time+5,"at":cell.position+Vector2(100,0)}
 tight._emit_and_attack(cell,1)
 check(cell.biomass>=0 and cell.energy>=0 and organ.get("emission_serial",0)==0,"Underfunded work cannot consume the biomass reserved for a burst")
 var secretion=work_fixture("neutralizing");cell=secretion.player;organ=cell.organs[0]
 secretion._emit_and_attack(cell,1)
 check(charged(cell,organ.id)==0,"A neutralizing gland without a chemical need is idle")
 secretion.secretion_needed=true;secretion._emit_and_attack(cell,1)
 check(charged(cell,organ.id)>0 and organ.get("emission_serial",0)>0,"A needed secretion pays for real gland work")
 var motor=work_fixture("propulsion");cell=motor.player;organ=cell.organs[0]
 motor._motion_cell(cell,.1);check(charged(cell,organ.id)==0,"A flagellum with no drive does not idle-burn ATP")
 cell.target=Vector2.RIGHT;motor._motion_cell(cell,.1)
 check(charged(cell,organ.id)>0,"Swimming pays its motor work cost")
 var repair=work_fixture("regenerative");cell=repair.player;organ=cell.organs[0]
 cell.heal(.2);check(charged(cell,organ.id)==0,"A repair gland does not charge for undamaged tissue")
 cell.health=90;cell.heal(.2)
 check(cell.health>90 and charged(cell,organ.id)>0,"A repair gland charges while restoring actual tissue")
 var sac=work_fixture("toxin_sac");cell=sac.player;organ=cell.organs[0]
 organ.stored_toxin=preload("res://scripts/toxin_sac.gd").capacity(organ)
 preload("res://scripts/toxin_sac.gd").fill(cell,.2)
 check(charged(cell,organ.id)==0,"A full toxin sac has no filling cost")
 organ.stored_toxin=0;preload("res://scripts/toxin_sac.gd").fill(cell,.2)
 check(organ.stored_toxin>0 and charged(cell,organ.id)>0,"Actual toxin storage pays work and material")
 var leaf=work_fixture("photosynthesis");cell=leaf.player;organ=cell.organs[0]
 cell.chemistry.photosynthesize(leaf,cell,organ,.3)
 check(charged(cell,organ.id)==0,"A leaf without carbon has no photosynthesis charge")
 cell.chemistry.emit("carbon",2,cell.local_point(organ.a)*.72)
 var fixed: float=cell.fixed_carbon;cell.chemistry.photosynthesize(leaf,cell,organ,.3)
 check(cell.fixed_carbon>fixed and charged(cell,organ.id)>0,"Carbon fixation pays leaf upkeep from actual production")
 for aerobic in [false,true]:
  var mito=work_fixture("mitochondrion");cell=mito.player;organ=cell.organs[0]
  cell.chemistry.emit("food",2,Vector2.ZERO)
  if aerobic:cell.chemistry.emit("oxygen",2,Vector2.ZERO)
  cell.chemistry.advance(cell,.25)
  check((charged(cell,organ.id)>0)==aerobic,"Mitochondria charge only for actual oxygen-dependent respiration")
 var reserve=work_fixture("mitochondrion");cell=reserve.player;organ=cell.organs[0]
 cell.chemistry.emit("oxygen",2,Vector2.ZERO);cell.burn_biomass(.5)
 check(cell.reserve_used==.5 and charged(cell,organ.id)>0 and is_finite(cell.energy),"Reserve-powered mitochondrial work remains finite and pays its own charge")

func respiration_gpu() -> void:
 var cpu=work_fixture("mitochondrion");var gpu=work_fixture("mitochondrion")
 for fixture in [cpu,gpu]:
  fixture.player.chemistry.emit("food",2,Vector2.ZERO)
  fixture.player.chemistry.emit("oxygen",2,Vector2.ZERO)
 var resident=preload("res://scripts/resident_particles.gd").new();resident.rd=RenderingServer.get_rendering_device()
 var chem=gpu.player.chemistry
 check(preload("res://scripts/resident_cytoplasm.gd").new().attach(resident,chem,gpu.player),"Resident cytoplasm attaches for actual work accounting")
 cpu.player.chemistry.advance(cpu.player,.25);chem.advance(gpu.player,.25)
 check(charged(gpu.player,gpu.player.organs[0].id)>0,"Resident mitochondrial receipt charges actual aerobic work")
 check(absf(cpu.player.energy-gpu.player.energy)<.0001 and absf(cpu.player.biomass-gpu.player.biomass)<.0001,"CPU and resident respiration keep identical net ATP and material")
 chem.ensure_cpu()
