extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var beacon:=ColorRect.new();beacon.size=Vector2(8,8);root.add_child(beacon);await process_frame;await process_frame
 var sim=Sim.new(64,0,false);sim.server_mode=true;sim.evolution.sandbox=true
 sim.cells=[sim.player];sim.player.organs=[];sim.player.position=Vector2(700,700)
 sim.habitat_geometry=Sim.Habitat.new(64)
 var habitat=sim.habitat_geometry
 habitat.plants=[{"p":Vector2(3000,1600),"radius":100.0,"form":0,"angle":0.0}]
 habitat.forms=[{"branches":[{"a":Vector2(-70,0),"b":Vector2(70,0),"r":16.0,"depth":1}]}];habitat.rebuild()
 sim.fluid.driven=false;sim.particles=[];sim.grid.rebuild([])
 var reference=Sim.Medium.new();reference.set_plants(habitat)
 var strongest:=0
 for i in reference.plant_drag.size():
  if reference.plant_drag[i]>reference.plant_drag[strongest]:strongest=i
 var controller=preload("res://scripts/resident_ecology.gd").new();controller.start(sim,1024)
 var status: Array=await controller.initialized
 check(status[0],"Resident hardware backend starts for vegetation flow regression")
 if not status[0]:quit(1);return
 for native_field in [true,false]:
  sim.native_fluid=native_field
  for visible in [true,false]:
   sim.camera_views=[Vector4(3000,1600,500,400)] if visible else []
   sim.fluid.velocity.fill(Vector2(40,-10));sim.background_field_clock=0
   sim.fluid.plant_drag=PackedFloat32Array();sim.fluid.plant_geometry=-1
   var dt:=1.0/30 if visible else .25
   sim.step(dt)
   var expected: Vector2=Vector2(40,-10)*exp(-reference.plant_drag[strongest]*dt)
   check(sim.fluid.plant_drag.size()==2560,"Resident loop builds its plant drag cache without a CPU gameplay step")
   check(sim.fluid.velocity[strongest].distance_to(expected)<.0001,"Actual "+("native" if native_field else "reference")+" water decays by the same planted-node drag in "+("visible" if visible else "offscreen")+" resident simulation")
 check(habitat.particles_permeable,"Vegetation drag preserves permeable chemical transport")
 controller.gpu.close();await controller.gpu.closed
 sim.resident=null
 print("RESIDENT PLANT FLOW: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
