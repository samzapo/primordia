extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Ecology=preload("res://scripts/resident_ecology.gd")
const Supply=preload("res://scripts/ambient_carbon.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize() -> void:run.call_deferred()
func fixture():
 var sim=Sim.new(951,0,false);sim.cells=[sim.player]
 sim.habitat_geometry=Sim.Habitat.new(951,sim.cells);sim.habitat_geometry.enabled=false
 sim.server_mode=true;sim.automatic_reproduction=false
 sim.player.organs.clear();sim.player.update_geometry()
 sim.player.add_organ("feeding",0,"graze",false)
 sim.player.add_organ("photosynthesis",1.2,"graze",false)
 sim.player.organs[-1].mutation="shade_leaf"
 sim.environment={"light":.12}
 if sim.kernels!=null:sim.kernels.set_activity_views([],true)
 return sim
func start(sim,streaming: bool):
 var bridge=Ecology.new();bridge.streaming_enabled=streaming
 bridge.start(sim,8192)
 var status: Array=await bridge.initialized
 check(status[0],str(status[1]))
 bridge.gpu.set_activity_views([],true)
 return bridge
func run() -> void:
 var adapter: String=RenderingServer.get_video_adapter_name().to_lower()
 check(RenderingServer.get_rendering_device()!=null and not ["llvmpipe","lavapipe","swiftshader"].any(func(name):return adapter.contains(name)),"Resident survival acceptance requires a real hardware rendering device")
 print("SURVIVAL_GPU ",RenderingServer.get_video_adapter_name())
 var sim=fixture()
 sim.spawn_particle(Sim.CARBON,Vector2(32,32),Vector2.ZERO,6)
 sim.spawn_particle(Sim.CARBON,Vector2(96,32),Vector2.ZERO,2)
 var bridge=await start(sim,false)
 var cold:=PackedFloat32Array();cold.resize(Supply.COUNT);cold[0]=3;cold[1]=1;cold[2]=2
 var result: Dictionary=bridge.gpu.carbon_supply_sync(cold,.5,8)
 check(not result.has("error"),"GPU saturation transaction commits")
 var packets: Array=bridge.snapshots()
 check(absf(packets[0].amount-(6.0*17/18))<.00001 and absf(packets[1].amount-4.5)<.00001,"Resident saturation includes cold stock and relaxes each area toward saturation")
 check(absf(result.added-2.5)<.00001 and absf(result.removed-1.0/3)<.00001 and absf(result.pending[2]-3)<.00001,"Bounded GPU receipt accounts for real deposit and unmaterialized source requests separately")
 check(bridge.gpu.readbacks==1,"Supply itself does not export resident packet poses")
 var before_phase: int=bridge.gpu.readbacks
 var selected: int=Supply.group(0,sim.seed_value)
 var factors:=PackedFloat32Array();factors.resize(Supply.COUNT);factors.fill(.1)
 var oxygen_cold:=PackedFloat32Array();oxygen_cold.resize(Supply.COUNT)
 var oxygen_result: Dictionary=bridge.gpu.carbon_supply_sync(oxygen_cold,.1,.5,selected,sim.seed_value,Sim.OXYGEN,factors)
 check(not oxygen_result.has("error") and bridge.gpu.readbacks==before_phase,"Phase-selective oxygen exchange uses the resident numeric transaction without pose export")
 for i in Supply.COUNT:
  if Supply.group(i,sim.seed_value)!=selected:check(oxygen_result.pending[i]==0,"An unselected gas tile receives no source request")
 var carbon_result: Dictionary=bridge.gpu.carbon_supply_sync(PackedFloat32Array(cold),.1,8,selected,sim.seed_value,Sim.CARBON,factors)
 check(not carbon_result.has("error"),"Carbon and oxygen share phased exchange without changing species")
 var cell=sim.player
 cell.energy=0;cell.biomass=0
 cell.chemistry.emit("carbon",4,cell.local_point(1.2)*.72)
 var reference=Codec.new().restore(Codec.new().capture(cell))
 check(bridge.gpu.attach_cytoplasm(cell.chemistry,cell),"Visible internal carriers use the resident GPU")
 cell.chemistry.photosynthesize(sim,cell,cell.organs[-1],.5)
 reference.chemistry.photosynthesize(sim,reference,reference.organs[-1],.5)
 check(absf(cell.energy-reference.energy)<.000001 and absf(cell.biomass-reference.biomass)<.000001 and absf(cell.chemistry.heat-reference.chemistry.heat)<.000001,"Resident and CPU photosynthesis agree on ATP yield, biomass and explicit heat")
 check(cell.energy>0 and cell.biomass>0,"Resident leaf recovers real resources from zero")
 cell.chemistry.ensure_cpu()
 bridge.close();await bridge.gpu.closed
 # The real resident scheduler and cold path, with no player camera.
 var live=fixture();cell=live.player;cell.position=Vector2(352,352);cell.angle=0
 cell.energy=0;cell.biomass=0;cell.health=23;cell.starvation_seconds=2400
 cell.chemistry.particles.clear();cell.chemistry.refresh()
 live.enable_perception_domains();live.ambient_carbon_enabled=true;live.particle_limit=5000
 bridge=await start(live,true)
 var initial_material: float=cell.organic_mass()
 var world_id: int=cell.id
 for tick in 3000:
  live.step(.1)
  if tick%100==0:await process_frame
 check(live.resident==bridge and bridge.fallback_reason=="","Ambient supply and hunger recovery retain resident ownership without fallback")
 check(cell.id==world_id and not cell.dead and cell.health>90 and cell.energy>0 and cell.biomass>0,"Actual cold resident ecology recovers the same starved one-leaf body without a camera")
 print("RESIDENT_RECOVERY ",JSON.stringify({"ATP":cell.energy,"biomass":cell.biomass,"health":cell.health,"starvation":cell.starvation_seconds,"carbon_added":live.ambient_carbon_added,"carbon_removed":live.ambient_carbon_removed,"external":live.habitat_census().external}))
 var total: float=cell.organic_mass();var carbon:=0.0
 for packet in bridge.snapshots():
  if packet.alive:
   total+=packet.amount*Sim.Catalog.material(packet.kind)
   if packet.kind==Sim.CARBON:carbon+=packet.amount
 check(absf(total+live.respiration_loss-live.external_input-initial_material)<.2,"The whole resident/cold recovery preserves open-system material accounting")
 check(carbon<Supply.SATURATION*Supply.COUNT*1.3 and live.ambient_carbon_removed>0,"Degassing bounds the pond carbon stock despite converging currents")
 check(live.ambient_carbon_added>0 and live.external_input>=live.ambient_carbon_added,"Authoritative open-system ledger records atmospheric material")
 cell.chemistry.ensure_cpu()
 bridge.close();await bridge.gpu.closed
 print("AMBIENT_CARBON_GPU: ",checks," checks, ",failures," failures")
 quit(1 if failures else 0)
