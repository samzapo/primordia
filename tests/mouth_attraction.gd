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
func run() -> void:
 Fixture.load_native()
 var sim=Sim.new(59,0,false);sim.server_mode=true;sim.cells=[sim.player];sim.player.organs.clear()
 var a=sim.player;a.position=Vector2(500,500);a.energy=100;a.biomass=20
 a.add_organ("feeding",0,"graze",false)
 var organ=a.organs[0];var reach: float=a.oral_reach(organ)
 check(reach>50 and reach<150,"Ordinary oral reach is about one third of the oversized previous range")
 var small=Sim.Cell.new(3);small.body=30;small.biomass=0;small.update_geometry()
 check(small.oral_reach(organ)<reach,"Smaller cells have a smaller suction zone")
 sim.fluid.velocity.fill(Vector2.ZERO);sim.fluid.prepare_attractors(sim.cells)
 var mouth: Vector2=a.pore_center(organ);var at: Vector2=mouth+Vector2(reach*.5,0)
 var nutrient: Vector2=sim.fluid.transport_sample(at,0)
 for kind in [1,2,3,4,5,6,7,8,9,10]:
  check((sim.fluid.transport_sample(at,kind)-nutrient*.2).length()<.0001,"Non-nutrient species "+str(kind)+" receives exactly20% pull")
 check(sim.fluid.transport_sample(mouth+Vector2(reach+1,0),0)==Vector2.ZERO,"Suction has a hard local radius without grid bleed")
 var water=sim.fluid.velocity.duplicate();var velocity=a.velocity
 var b=Sim.Cell.new(2);b.biomass=20;b.energy=100;b.add_organ("feeding",PI,"graze",false)
 b.position=a.position+Vector2(a.extent()+b.extent()+90,0);b.previous_position=b.position
 sim.cells.append(b);sim.fluid.prepare_attractors(sim.cells)
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
 if RenderingServer.get_rendering_device()!=null:
  await gpu(sim,middle)
  await environment_tail(sim,middle)
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
 if ClassDB.class_exists("PrimordiaResidentReference"):
  reference=ClassDB.instantiate("PrimordiaResidentReference")
  check(reference.configure(data,field,2),"Native resident reference accepts the same descriptors")
 for i in 12:
  gpu.advance(1.0/60,i)
  if reference!=null:reference.advance(1.0/60,i)
  await process_frame
 await RenderingServer.frame_post_draw
 gpu.snapshot();var actual: PackedFloat32Array=await gpu.snapshot_ready
 if reference!=null:check(Fixture.compare(reference.snapshot(),actual).passed,"Actual resident GPU/native agree across nutrient, oxygen, pheromone and carbon")
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
