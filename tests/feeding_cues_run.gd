extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Probe=preload("res://scripts/proboscis.gd")
const Cue=preload("res://scripts/proboscis_feeding_art.gd")
const Colors=preload("res://scripts/signal_colors.gd")
var checks:=0
var failures:=0
class ViewStub extends Node2D:
 var cell
 var raster_active:=false
 var raster_outline:=PackedVector2Array()
 var motion
 func visible_point(at: Vector2) -> Vector2:return at if motion==null else motion.point(at)
 func visible_outline() -> PackedVector2Array:
  var outline: PackedVector2Array=raster_outline if raster_active else cell.membrane.outline()
  return outline if motion==null else motion.outline(outline,raster_active)
class GameStub extends RefCounted:
 var world
 var views: Dictionary={}
 var lineage_names: Array=[{"root":2147483646,"color":"28d99a"}]
 var ui_time:=0.0
 func lineage_color(root: int) -> String:return "ed386e" if root==2 else "28d99a" if root==2147483646 else ""
 func merge_selecting() -> bool:return false
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var game=GameStub.new();game.world=Sim.new(29,0,false)
 var sim=game.world;sim.spatial_queries=false
 var feeder=sim.Cell.new(1,Vector2(400,400));feeder.add_organ("proboscis",0,"graze",false)
 var organ: Dictionary=feeder.organs[0]
 var donor=sim.Cell.new(2,Probe.tip(feeder,organ)+Vector2(20,0));donor.biomass=40
 sim.cells=[feeder,donor];sim.player=feeder
 var holes: Array=donor.holes.duplicate(true);var health: float=donor.health
 Probe.step(sim,feeder,.1)
 check(organ.feeding and organ.proboscis_contact.cell==donor.id,"Only actual successful feeding records a puncture contact")
 var at:=Cue.anchor(donor.membrane.outline(),organ.proboscis_contact)
 var edge: int=organ.proboscis_contact.edge;var outline: PackedVector2Array=donor.membrane.outline()
 check(at.distance_to(Geometry2D.get_closest_point_to_segment(at,outline[edge],outline[(edge+1)%outline.size()]))<.00001,"The puncture anchor lies exactly on the real donor membrane")
 check(donor.holes==holes and donor.health==health,"The cosmetic hole adds no leaking wound or extra damage")
 var state: int=sim.rng.state
 var first=ViewStub.new();first.cell=feeder;first.position=Vector2(90,300)
 var second=ViewStub.new();second.cell=donor;second.position=first.position+Sim.Medium.offset(feeder.position,donor.position)
 game.views={1:first,2:second}
 var cue=Cue.new();cue.game=game;root.add_child(cue)
 cue.sync()
 check(cue.contacts.size()==1,"Active feeding has one transfer cue outside cell raster caches")
 var old_phase: float=cue.contacts[0].phase
 game.ui_time+=.1;cue.sync()
 check(cue.contacts[0].phase>old_phase and sim.rng.state==state,"Transfer motion advances on the local clock without biology or RNG")
 var old_hole: Vector2=cue.contacts[0].hole
 second.rotation=.3;second.position+=Vector2(4,-2);cue.sync()
 check(cue.contacts[0].hole.distance_to(old_hole)>1,"The contact follows the rendered donor transform")
 # Lateral motion and rendered heading must not leave a hole pinned to the
 # authority's stale membrane edge. Check the real current shaft and membrane.
 second.position+=Vector2(0,8);first.rotation=.15;cue.sync()
 check(cue.contacts.size()==1,"A rendered contact remains visible while donor and feeder move between updates")
 if not cue.contacts.is_empty():
  var path:=Cue.geometry(game,first,organ);var hole: Vector2=cue.contacts[0].hole
  check(hole.distance_to(Geometry2D.get_closest_point_to_segment(hole,path.base,path.tip))<.00001,"Puncture and transfer path stay exactly on the visible shaft")
  var local: Vector2=second.transform.affine_inverse()*hole;var nearest:=INF
  var curve: PackedVector2Array=donor.membrane.outline()
  for i in curve.size():nearest=minf(nearest,local.distance_to(Geometry2D.get_closest_point_to_segment(local,curve[i],curve[(i+1)%curve.size()])))
  check(nearest<.0001,"The reprojected puncture lies on the donor's rendered membrane; distance="+str(nearest))
  var old: Vector2=second.transform*Cue.anchor(curve,organ.proboscis_contact)
  check(old.distance_to(hole)>1,"The fixture exposes the stale-edge drift reported by the owner")
 var pose: Vector2=second.position;second.position+=Vector2(300,0);cue.sync()
 check(cue.contacts.is_empty(),"A stale feeding report cannot draw a detached hole when the shaft no longer intersects")
 second.position=pose;cue.sync()
 second.raster_active=true;second.raster_outline=donor.membrane.outline()
 var cached:=Cue.geometry(game,first,organ)
 check(cached.hole.is_finite() and cached.hole.distance_to(cue.contacts[0].hole)<.0001,"Cached donor bodies use their displayed membrane outline")
 second.raster_active=false
 second.motion=preload("res://scripts/cell_motion.gd").new()
 second.motion.sync(donor,0,second.global_transform)
 second.motion.sync(donor,.2,second.global_transform)
 var animated:=Cue.geometry(game,first,organ)
 var displayed: PackedVector2Array=second.visible_outline()
 var nearest_display:=INF
 if animated.hole.is_finite():
  var local: Vector2=second.transform.affine_inverse()*animated.hole
  for i in displayed.size():nearest_display=minf(nearest_display,local.distance_to(Geometry2D.get_closest_point_to_segment(local,displayed[i],displayed[(i+1)%displayed.size()])))
 check(animated.hole.is_finite() and nearest_display<.0001,"The puncture stays on the client-animated donor membrane")
 check(animated.hole.distance_to(Geometry2D.get_closest_point_to_segment(animated.hole,animated.base,animated.tip))<.0001,"The locally animated contact remains on the same straight visible proboscis")
 second.motion=null
 var tint:=Colors.family(game,2)
 check(tint.is_equal_approx(Color("ed386e")*Color(1,1,1,.65)),"Pheromones use the chosen family color with slight transparency")
 var stock: Color=preload("res://scripts/cell_art.gd").make(sim.seed_value,991).colors[1];stock.a=.65
 check(Colors.family(game,991).is_equal_approx(stock),"Uncustomized pheromones exactly match seeded family body color")
 check(Colors.root({"owner":1,"report":{"lineage":2}})==2,"Signal color uses the immutable family report, not the current source")
 check(Colors.packed(Color(1,0,1))==16711935,"Web tint packs RGB exactly in an unused float channel")
 donor.biomass=1;feeder.energy=100
 var body: float=donor.body;var mass: float=donor.organic_mass()+feeder.organic_mass()
 Probe.step(sim,feeder,10)
 check(donor.biomass==0 and donor.body==body and donor.health==health and not donor.dead and donor.holes==holes,"Exhausting donor reserves never kills, damages structural body or opens a real wound")
 check(absf(donor.organic_mass()+feeder.organic_mass()-mass)<.00001,"Nonlethal extraction conserves donor and feeder material")
 Probe.step(sim,feeder,.1);cue.sync()
 check(not organ.feeding and not organ.has("proboscis_contact") and cue.contacts.is_empty(),"Stopping intake clears both the puncture and transfer cue")
 for kind in ["propulsion","hunting","sensing"]:feeder.add_organ(kind,feeder.organs.size(),"graze",false)
 feeder.biomass=200;organ.feeding=true;organ.proboscis_contact={"cell":2,"edge":0,"t":.5}
 Probe.step(sim,feeder,.1)
 check(not organ.feeding and not organ.has("proboscis_contact"),"A sated parasite cannot leave a stuck sucking indication")
 if "--native" in OS.get_cmdline_user_args():native_tints(game)
 if "--gpu" in OS.get_cmdline_user_args():await gpu_tints(game)
 cue.queue_free();first.free();second.free();await process_frame
 print("FEEDING_CUES: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)

func native_tints(game) -> void:
 var kernel=preload("res://scripts/backend.gd").create()
 check(kernel!=null,"Native tint comparison loads the current native library")
 if kernel==null:return
 var packets: Array=[]
 for root_id in [2,991,2147483646]:
  packets.append({"kind":3,"p":Vector2(30+packets.size()*30,50),"previous":Vector2(30+packets.size()*30,50),"angle":0.0,"previous_angle":0.0,"amount":.2,"alive":true,"report":{"lineage":root_id}})
 var ids: Array[int]=[0,1,2]
 var capacities:=PackedInt32Array();capacities.resize(26);capacities.fill(4)
 var result: Array=kernel.render_particles(packets,ids,[],Vector2.ZERO,Vector2(400,400),1,0,capacities,false,Colors.native_style(game))
 var colors: PackedFloat32Array=result[3]
 for i in packets.size():
  var expected:=Colors.family(game,packets[i].report.lineage)
  var actual:=Color(colors[i*12+8],colors[i*12+9],colors[i*12+10],colors[i*12+11])
  check(actual.is_equal_approx(expected),"Native tint matches family style for "+str(packets[i].report.lineage))

func gpu_tints(game) -> void:
 var beacon=ColorRect.new();beacon.size=Vector2(8,8);root.add_child(beacon)
 await process_frame;await process_frame
 var Fixture=preload("res://scripts/resident_fixture.gd")
 var gpu=preload("res://scripts/resident_particles.gd").new()
 check(gpu.configure_interactions("chemistry") and gpu.configure_exchange() and gpu.configure_perception(1),"Configure real resident signal metadata")
 var states:=PackedFloat32Array();var metadata: Array=[]
 for i in 2:
  var root_id: int=2 if i==0 else 2147483646
  states.append_array(PackedFloat32Array([50+i*30,60,0,0,0,0,0,3,6,.2,0,0]))
  metadata.append({"slot":i,"owner":i+10,"expires_at":10.0,"report":{"id":i+10,"lineage":root_id,"at":Vector2(50+i*30,60),"radius":30.0,"mass":20.0,"emitted_at":1.0,"hostile":false,"defended":false}})
 gpu.initialize(states,Fixture.flow(),metadata)
 var status: Array=await gpu.ready
 check(status[0],str(status[1]))
 if not status[0]:return
 var captured={"bytes":PackedByteArray()};var done:=Semaphore.new()
 RenderingServer.call_on_render_thread(func():
  captured.bytes=gpu.rd.texture_get_data(gpu._perception.lineage_image,0);done.post())
 done.wait()
 # Readback is confined to this isolated correctness fixture.
 for i in 2:
  var root_id: int=int(captured.bytes.decode_float(i*8))|(int(captured.bytes.decode_float(i*8+4))<<16)
  check(root_id==metadata[i].report.lineage,"Resident visual texture preserves all immutable family-ID bits")
 check(gpu.publish_views([Vector4(60,60,100,100)]),"Bounded signal publication starts")
 var publication: Dictionary=await gpu.publication_ready
 check(not publication.has("error") and publication.count==2 and publication.bytes.size()==64,"Publication retains32-byte records and stable particle identity fields")
 if not publication.has("bytes"):
  gpu.close();await gpu.closed;beacon.queue_free();return
 var roots: Array=[]
 for at in range(0,publication.bytes.size(),32):roots.append(publication.bytes.decode_s32(at+20))
 roots.sort();check(roots==[2,2147483646],"Web publication carries exact families without a pose-metadata download")
 var view=preload("res://scripts/resident_view.gd").new();view.game=game;root.add_child(view);view.initialize(gpu);view.camera(Vector2.ZERO)
 await process_frame;await process_frame
 check(view.batch.material.get_shader_parameter("family_tints"),"Local resident drawing uses the family palette")
 view.queue_free();await process_frame
 gpu.close();await gpu.closed;beacon.queue_free()
