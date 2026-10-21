extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Proboscis=preload("res://scripts/proboscis.gd")
var checks:=0
var failures:=0
func check(ok: bool,why: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func fixture():
 var sim=Sim.new(59,0,false);sim.server_mode=true;sim.cells=[sim.player];sim.particles=[]
 sim.player.organs.clear();sim.spatial_queries=false
 return sim
func run() -> void:
 await controls()
 var sim=fixture();var cell=sim.player
 cell.energy=0;cell.biomass=10;cell.update_power_state()
 check(cell.work_capacity(2)==1,"Biomass reserves keep ordinary organs at full capacity")
 var mass=cell.organic_mass()
 check(cell.spend_energy(2)==2 and cell.energy==0 and is_equal_approx(cell.biomass,9.95) and is_equal_approx(cell.reserve_used,.05),"Full work pays its real ATP deficit from finite biomass")
 check(is_equal_approx(cell.organic_mass(),mass) and is_equal_approx(cell.chemistry.heat,13),"Combustion retains nonfuel products and explicit heat")
 sim._flush_reserve_products(cell,true)
 check(cell.behavior.get("reserve_products",0)==0 and sim.particle_count()==2,"Combustion products flush once as carbon and waste")
 cell.biomass=0;check(cell.work_capacity()==.25,"Exhausted ATP and biomass retain quarter capacity")
 # Strong particle attraction does not change water or cell velocities.
 for role in ["hunter","grazer"]:
  sim=fixture();cell=sim.player;cell.biomass=20;cell.energy=3
  cell.add_organ("feeding",0,"graze",false)
  if role=="hunter":
   cell.add_organ("hunting",PI,"graze",false);cell.add_organ("propulsion",PI/2,"graze",false);cell.add_organ("toxin",3*PI/2,"graze",false)
  else:cell.add_organ("cilia",PI,"graze",false)
  var mouth=cell.organs.filter(func(o):return o.kind=="feeding")[0]
  cell.drive_active=true;cell.target_mode="graze";cell.target_memory=30;cell.target_organ_id=mouth.id
  var at: Vector2=cell.pore_center(mouth);var water=sim.fluid.velocity.duplicate()
  cell.velocity=Vector2(3,4);var velocity=cell.velocity
  sim._suction_cell(cell,.1);sim.fluid.prepare_attractors(sim.cells)
  var normal: Vector2=cell.organ_normal(mouth).rotated(cell.angle)
  var near: Vector2=at+normal*cell.oral_reach(mouth)*.45;var far: Vector2=at+normal*cell.oral_reach(mouth)*1.1
  check((sim.fluid.transport_sample(near)-sim.fluid.sample(near)).dot(-normal)>100,role+" mouth retains strong local nutrient pull")
  check((sim.fluid.transport_sample(far)-sim.fluid.sample(far)).length()<.00001,role+" mouth stops pulling outside its cell-scaled reach")
  check(sim.fluid.velocity==water and cell.velocity==velocity,"Oral attraction cannot inject water/cell momentum")
  var start:=near
  for i in 240:start=preload("res://scripts/particle_transport.gd").advect(start,Vector2.ZERO,sim.fluid,1.0/60)
  check(sim.Medium.offset(start,at).length()<cell.pore_radius(mouth)+10,role+" attractor delivers a real particle to the mouth")
  var saved=Codec.new().restore(Codec.new().capture(sim))
  check(saved.fluid.particle_velocity.is_empty(),"Derived attractor field is not saved as persistent water")
  sim.particles=[];sim.grid.rebuild([]);cell.energy=3;cell.biomass=20
  sim.camera_views=[Vector4(cell.position.x,cell.position.y,600,600)]
  sim.spawn_particle(sim.NUTRIENT,near,Vector2.ZERO,24,-1)
  sim.spawn_particle(sim.OXYGEN,at,Vector2.ZERO,24,-1)
  sim.fluid.prepare_attractors(sim.cells)
  for i in 1200:
   for particle in sim.particles:
    if particle.alive:preload("res://scripts/particle_transport.gd").advance(particle,sim.fluid,1.0/60,i,sim.rng)
   sim.grid.rebuild(sim.particles);sim._feed(cell);sim._metabolize(cell,1.0/60)
  print("MEAL ",role," eaten=",cell.eaten," processed=",cell.processed," ATP=",cell.energy," biomass=",cell.biomass," food=",cell.substrate," oxygen=",cell.oxygen)
  check(cell.eaten>10 and cell.processed>0 and cell.substrate>1 and cell.energy>3 and cell.biomass>0,role+" recovers from a finite nearby meal instead of starving beside it")
 # Actual contact transfer cannot create mass/fuel, reach remotely or overdraw.
 sim=fixture();cell=sim.player;cell.energy=10;cell.biomass=30;cell.position=Vector2(400,400)
 cell.add_organ("proboscis",0,"graze",false)
 var organ=cell.organs[0];var tip=Proboscis.tip(cell,organ)
 var donor=Sim.Cell.new(991,tip+Vector2(35,0));donor.biomass=20;donor.update_geometry();sim.cells.append(donor)
 var total=cell.organic_mass()+donor.organic_mass();var fuel=cell.raw_fuel
 Proboscis.step(sim,cell,.5)
 check(donor.biomass==19 and cell.substrate==1 and cell.energy==9.5,"Proboscis spends ATP and transfers exactly one real biomass at contact")
 check(is_equal_approx(total,cell.organic_mass()+donor.organic_mass()) and is_equal_approx(cell.raw_fuel-fuel,Sim.Cell.Chemistry.TISSUE_FUEL),"Contact feeding preserves finite material and tissue fuel")
 donor.position+=Vector2(500,0);var eaten=cell.eaten;Proboscis.step(sim,cell,1)
 check(cell.eaten==eaten and not organ.feeding,"Proboscis cannot feed across open water")
 donor.position-=Vector2(500,0);donor.unattended_protected=true;Proboscis.step(sim,cell,1)
 check(cell.eaten==eaten,"Protected unattended favorite cannot be drained")
 donor.unattended_protected=false;donor.biomass=.05;Proboscis.step(sim,cell,1)
 check(donor.biomass==0 and is_finite(cell.energy),"Contact feeding cannot overdraw donor biomass")
 var saved=Codec.new().restore(Codec.new().capture(sim))
 check(saved.player.count("proboscis")==1,"New organ anatomy survives ordinary graph serialization")
 await photosynthesis()
 await resident_attractor()
 print("FEEDBACK_REQUESTS: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)

func controls() -> void:
 var game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false;root.add_child(game)
 game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
 var picker=game.cell_ui.investment_picker;game.build_open=true
 var relative=Sim.Cell.new(992);relative.lineage=game.world.player.lineage_id();game.world.cells.append(relative)
 for mobile in [false,true]:
  game.touch_zoom.enabled=mobile
  picker.open()
  for pair in [[picker.auto_mitosis,"mitosis"],[picker.auto_bud,"budding"]]:
   var button: Button=pair[0];button.pressed.emit();picker.sync()
   check(button.text.ends_with("Off") and button.icon==null,"Family auto mode visibly switches Off on desktop/mobile")
   check(not (relative.automatic_division if pair[1]=="mitosis" else relative.automatic_budding),"Family policy reaches actual relatives")
   button.pressed.emit();picker.sync()
   check(button.text.ends_with("On") and button.icon!=null,"Family auto mode visibly switches On with a supported icon")
  picker._scope("cell");picker.auto_bud.pressed.emit();picker.sync()
  check(picker.auto_bud.text.ends_with("Off") and relative.automatic_budding,"This-cell choice leaves relatives unchanged")
  picker.auto_bud.pressed.emit();picker.sync()
 if RenderingServer.get_rendering_device()!=null:
  root.size=Vector2i(576,900);game.touch_zoom.enabled=true;picker.open()
  await process_frame;await process_frame;await RenderingServer.frame_post_draw
  var destination:=OS.get_environment("PRIMORDIA_TEST_CAPTURE")
  if destination!="":root.get_texture().get_image().save_png(destination)
 game.queue_free();await process_frame

func photosynthesis() -> void:
 for surplus in [false,true]:
  var sim=fixture();var cell=sim.player;cell.energy=100 if surplus else 10;cell.biomass=100 if surplus else 10
  cell.add_organ("photosynthesis",0,"graze",false);cell.chemistry.emit("food",4,Vector2.ZERO)
  cell.chemistry.emit("carbon",3,cell.local_point(0)*.72,-1,-1,0)
  var food=cell.substrate
  var share: float=cell.chemistry.food_share(sim,cell)
  check(share==1.0,"Producer continuously exports all food in recovery and surplus")
  var cpu=Sim.Cell.clone_state(cell)
  var gpu=null
  if RenderingServer.get_rendering_device()!=null:
   gpu=preload("res://scripts/resident_particles.gd").new();gpu.rd=RenderingServer.get_rendering_device()
   check(preload("res://scripts/resident_cytoplasm.gd").new().attach(gpu,cell.chemistry,cell),"Focused sharing check uses actual resident chemistry")
  cell.chemistry.photosynthesize(sim,cell,cell.organs[0],1)
  var exterior: float=sim.particles.reduce(func(total,p):return total+p.amount,0.0)
  check(is_equal_approx(cell.substrate-food,cell.fixed_carbon*Sim.Cell.Chemistry.LEAF_FOOD*(1-share)) and is_equal_approx(exterior,cell.fixed_carbon*Sim.Cell.Chemistry.LEAF_FOOD*share),"Internal/external food split uses real consumed carbon")
  if gpu!=null:
   cpu.chemistry.photosynthesize(sim,cpu,cpu.organs[0],1)
   check(is_equal_approx(cell.substrate,cpu.substrate) and is_equal_approx(cell.energy,cpu.energy),"Resident and CPU food/ATP match for both sharing fractions")
   cell.chemistry.ensure_cpu()

func resident_attractor() -> void:
 if RenderingServer.get_rendering_device()==null:return
 print("FOCUSED_GPU ",RenderingServer.get_video_adapter_name())
 var sim=fixture();var cell=sim.player;cell.add_organ("feeding",0,"graze",false)
 cell.drive_active=true;cell.target_mode="graze";cell.target_memory=1;cell.target_organ_id=cell.organs[0].id
 var at: Vector2=cell.pore_center(cell.organs[0]);sim.fluid.prepare_attractors(sim.cells)
 var start: Vector2=at+cell.organ_normal(cell.organs[0]).rotated(cell.angle)*cell.oral_reach(cell.organs[0])*.8
 var data:=PackedFloat32Array([start.x,start.y,0,0,0,0,0,0,8,.3,.3,0])
 var gpu=preload("res://scripts/resident_particles.gd").new()
 gpu.initialize(data,sim.fluid.particle_flow())
 var ready: Array=await gpu.ready
 check(ready[0],"Resident external transport accepts the particle-only attraction field")
 if not ready[0]:gpu.close();await gpu.closed;return
 for i in 120:
  gpu.advance(1.0/60,i)
  if i%8==0:await process_frame
 await RenderingServer.frame_post_draw
 gpu.snapshot();var actual: PackedFloat32Array=await gpu.snapshot_ready
 check(sim.Medium.offset(Vector2(actual[0],actual[1]),at).length()<30,"Resident hardware GPU pulls actual external food to the mouth")
 check(gpu.readbacks==1 and gpu.dispatches==120,"Gameplay attraction retains resident particle ownership")
 gpu.close();await gpu.closed
