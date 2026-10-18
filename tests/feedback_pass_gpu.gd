extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const GPU=preload("res://scripts/resident_particles.gd")
const Cytoplasm=preload("res://scripts/resident_cytoplasm.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
var assertions:=0
var failures:=0
func check(ok: bool,why: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(64,64)
 await process_frame;await process_frame
 print("FEEDBACK_PASS_GPU ",RenderingServer.get_video_adapter_name())
 var gpu=GPU.new();gpu.rd=RenderingServer.get_rendering_device()
 for output in [1.0,2.0,4.0]:
  var cell=Sim.Cell.new(31);cell.energy=10
  cell.add_organ("mitochondrion",1,"graze",false);cell.organs[-1].output=output
  cell.chemistry.emit("food",4,Vector2(30,0));cell.chemistry.emit("oxygen",4,Vector2(30,0),-1,-1,0)
  var cpu=Sim.Cell.clone_state(cell)
  check(Cytoplasm.new().attach(gpu,cell.chemistry,cell),"Mitochondrial fixture uses resident internal particles")
  for i in 60:
   cell.chemistry.advance(cell,1.0/60);cpu.chemistry.advance(cpu,1.0/60)
  check(absf(cell.energy-cpu.energy)<.000001 and absf(cell.biomass-cpu.biomass)<.000001 and absf(cell.raw_fuel-cpu.raw_fuel)<.000001 and absf(cell.chemistry.heat-cpu.chemistry.heat)<.000001,"Mitochondrial ATP, tissue, fuel, heat and inert legacy output match CPU reference")
  check(cell.chemistry.particles.is_empty() and cell.chemistry.accelerator.exports==0,"Mitochondria retain GPU authority without a CPU pose mirror")
  cell.chemistry.ensure_cpu()
 var plant=Sim.Cell.new(32);plant.add_organ("photosynthesis",0,"graze",false)
 plant.chemistry.emit("carbon",3,plant.local_point(0)*.72,-1,-1,0)
 var sim=Sim.new(59,0,false);sim.cells=[plant];sim.player=plant;sim.particles=[];sim.grid.rebuild([])
 check(Cytoplasm.new().attach(gpu,plant.chemistry,plant),"Food-sharing fixture uses resident carbon particles")
 plant.chemistry.photosynthesize(sim,plant,plant.organs[0],1)
 var exterior:=0.0
 for packet in sim.particles:exterior+=packet.amount
 check(absf(plant.substrate-plant.fixed_carbon*.65*.75)<.000001 and absf(exterior-plant.fixed_carbon*.65*.25)<.000001,"GPU food sharing delivers exactly 75% internal and 25% external")
 plant.chemistry.ensure_cpu()
 # Division keeps resident ingested chemistry on its owner, never on the child.
 var birth=Sim.new(61,0,false);birth.server_mode=true;birth.cells=[birth.player]
 birth.habitat_geometry=Sim.Habitat.new(61,birth.cells);birth.habitat_geometry.enabled=false
 var parent=birth.player;parent.add_organ("feeding",0,"graze",false);parent.add_organ("photosynthesis",1,"graze",false)
 birth.investment.cells[parent.id]="producer"
 var quote: Dictionary=birth.offspring_quote(parent)
 parent.biomass+=quote.material;parent.energy=100;parent.reserve(60,quote.material)
 parent.chemistry.emit("food",3,Vector2(20,0))
 check(Cytoplasm.new().attach(gpu,parent.chemistry,parent),"Division parent retains a real resident cytoplasm")
 var food: float=parent.substrate
 check(birth.divide_lineage(false,false),"Resident-parent paid division commits")
 var daughter=birth.cells[-1]
 check(daughter.organs.size()==2 and daughter.count("photosynthesis")==1 and birth.Investment.strategy(birth,daughter)=="producer","Resident-parent daughters inherit strategy and basic anatomy only")
 check(parent.substrate==food and daughter.substrate==0 and daughter.chemistry.particle_count()==0 and parent.chemistry.accelerator!=null,"Division neither clones resident vacuoles nor drops the parent's GPU owner")
 parent.chemistry.ensure_cpu()
 # Same-family fusion releases only the two internal owners and can resume residency.
 var fusion=Sim.new(612,0,false);fusion.server_mode=true;fusion.cells=[fusion.player]
 fusion.habitat_geometry=Sim.Habitat.new(612,fusion.cells);fusion.habitat_geometry.enabled=false
 var recipient=fusion.player;recipient.position=Vector2(500,500)
 var donor=Sim.Cell.new(713,Vector2(600,500));donor.lineage=recipient.lineage_id()
 donor.add_organ("feeding",0,"graze",false);donor.add_organ("photosynthesis",1,"graze",false)
 donor.chemistry.emit("food",2,Vector2.ZERO,-1,-1,15);donor.chemistry.particles[0].age=6
 donor.chemistry.emit("waste",.5,Vector2.ZERO,-1,donor.chemistry.particles[0].compartment,0)
 fusion.cells.append(donor);fusion.lineage.register(donor,recipient.id,1,"living",0)
 donor.position=recipient.position+Vector2(recipient.extent()+donor.extent()-2,0)
 check(Cytoplasm.new().attach(gpu,recipient.chemistry,recipient) and Cytoplasm.new().attach(gpu,donor.chemistry,donor),"Both merging cells own hardware-resident internal chemistry")
 check(fusion.FamilyMerging.request(fusion,donor.id) and recipient.substrate==2 and recipient.waste==.5,"A real resident fusion transfers the vacuole without duplicating either owner")
 check(Cytoplasm.new().attach(gpu,recipient.chemistry,recipient),"The fused cell returns to resident internal chemistry")
 check(recipient.chemistry.vacuoles.filter(func(v):return v.get("species","") not in ["oxygen","carbon"]).size()==1 and recipient.chemistry.vacuoles[0].age==6,"Resident reattachment retains food/waste grouping and digestion age")
 recipient.chemistry.ensure_cpu()
 # Counterattack reception works through actual GPU queries, without a source body.
 var defender=Sim.Cell.new(90,Vector2(1000,900));defender.add_organ("counterattack",0,"graze",false)
 var receptor: Vector2=defender.organ_position(defender.organs[0])
 var signal_packet:=PackedFloat32Array([receptor.x+5,receptor.y,0,0,0,0,0,3,8,.2,.2,0])
 var sensed=GPU.new();sensed.configure_interactions("chemistry");sensed.configure_exchange();sensed.configure_perception();sensed.configure_exposure()
 sensed.initialize(signal_packet,Fixture.flow(),[{"slot":0,"owner":91,"lineage":91,"expires_at":8.0,"report":{"id":91,"lineage":91,"at":Vector2(1100,950),"mass":100.0,"radius":40.0,"hostile":true,"defended":true,"emitted_at":0.0}}])
 var sensing_ready: Array=await sensed.ready;check(sensing_ready[0],str(sensing_ready[1]))
 var perception=preload("res://scripts/resident_perception.gd")
 var queries: Array=perception.requests([defender],.2,0)
 var signals: Dictionary=sensed.exchange_sync([defender],[],[],queries,{"feeding":false,"exposure":false,"projection":false})
 sim.cells=[defender];sim.player=defender;sim.particles=[];sim.grid.rebuild([]);sim.time=0
 sim._sense(defender,.2,perception.for_cell(queries,signals.senses,defender));sim._emit_and_attack(defender,.1)
 check(sim.particles.any(func(p):return p.kind==Sim.TOXIN and sim.attack_sources.get(p.owner,{}).get("selective",false)),"A lone counterattack gland fires from a locally received immutable GPU report")
 check(not sim.cells.any(func(c):return c.id==91),"Counterattack does not need a live source body or remote anatomy lookup")

 # Hunting permission must survive a different navigation winner on real GPU reception.
 var hunter=Sim.Cell.new(290,Vector2(1000,900));hunter.energy=10;hunter.biomass=20
 hunter.add_organ("hunting",0,"hunt",false);hunter.add_organ("toxin",1,"graze",false);hunter.add_organ("poreforming",2,"graze",false)
 hunter.chemistry.emit("food",4,Vector2.ZERO)
 var trace: Vector2=hunter.organ_position(hunter.organs[0])+Vector2(5,0)
 var hunting_gpu=GPU.new();hunting_gpu.configure_interactions("chemistry");hunting_gpu.configure_exchange();hunting_gpu.configure_perception()
 hunting_gpu.initialize(PackedFloat32Array([trace.x,trace.y,0,0,0,0,0,3,8,.2,.2,0]),Fixture.flow(),
 [{"slot":0,"owner":291,"lineage":291,"expires_at":8.0,"report":{"id":291,"lineage":291,"at":hunter.position+Vector2(100,0),"mass":10.0,"radius":20.0,"hostile":false,"defended":false,"emitted_at":0.0}}])
 var hunting_ready: Array=await hunting_gpu.ready;check(hunting_ready[0],str(hunting_ready[1]))
 queries=perception.requests([hunter],.2,0)
 var hunting_receipt: Dictionary=hunting_gpu.exchange_sync([hunter],[],[],queries,{"feeding":false,"exposure":false,"projection":false,"summaries":true})
 sim.cells=[hunter];sim.player=hunter;sim.particles=[];sim.grid.rebuild([]);sim.time=0
 sim._sense(hunter,.2,perception.for_cell(queries,hunting_receipt.senses,hunter))
 check(hunter.behavior.has("weapon_cue") and sim.Behavior.priority(hunter,"hunt")==0,"A locally received GPU prey trace enables weapons while the hungry cell rests to digest")
 sim._emit_and_attack(hunter,.01)
 check(sim.particles.any(func(p):return p.kind==Sim.TOXIN) and sim.particles.any(func(p):return p.kind==Sim.PORE_SUBUNIT),"Both ordinary glands emit finite particles from real resident reception without a live prey body")
 hunting_gpu.close();await hunting_gpu.closed

 # A family trace never becomes a threat, but can guide attack dispersal.
 defender.add_organ("sensing",PI,"flee",false);defender.add_organ("propulsion",1,"graze",false)
 defender.sense_clock=0;defender.lineage=90
 var family_data:=PackedFloat32Array()
 for index in 2:
  family_data.append_array(PackedFloat32Array([defender.position.x+index*2,defender.position.y,0,0,0,0,0,3,8,.2,.2,0]))
 var family_gpu=GPU.new();family_gpu.configure_interactions("chemistry");family_gpu.configure_exchange();family_gpu.configure_perception()
 family_gpu.initialize(family_data,Fixture.flow(),[
  {"slot":0,"owner":92,"lineage":90,"expires_at":8.0,"report":{"id":92,"lineage":90,"at":defender.position+Vector2(-30,60),"mass":30.0,"radius":20.0,"hostile":true,"defended":false,"emitted_at":0.0}},
  {"slot":1,"owner":93,"lineage":93,"expires_at":8.0,"report":{"id":93,"lineage":93,"at":defender.position+Vector2(80,0),"mass":100.0,"radius":40.0,"hostile":true,"defended":true,"emitted_at":0.0}}])
 var family_ready: Array=await family_gpu.ready;check(family_ready[0],str(family_ready[1]))
 queries=perception.requests([defender],.2,0)
 # Both local packet poses reach the real receptors; emission positions differ.
 var family_query: Dictionary=queries[-1]
 var family_receipt: Dictionary=family_gpu.exchange_sync([defender],[],[],queries,{"feeding":false,"exposure":false,"projection":false,"summaries":true})
 var received: Dictionary=perception.for_cell(queries,family_receipt.senses,defender)
 check(received[family_query.organ_id].families.has(92),"Resident family query receives an actual same-lineage chemical report")
 check(not received[family_query.organ_id].reports.has(92),"A relative never enters the hostile target channel")
 sim._sense(defender,.2,received)
 sim._sense(defender,.2,received)
 check(defender.target_mode=="flee" and defender.target_id==93 and defender.target.x<0 and defender.target.y<0,"Actual GPU cues escape a foreign threat while spreading away from family")
 check(defender.facing==-defender.target and defender.threat==Vector2.RIGHT,"Escape steering turns away from family while weapon aim retains the reported threat")
 check(not sim.cells.any(func(c):return c.id in [92,93]),"GPU behavior uses only immutable emission facts, without live source bodies")
 family_gpu.close();await family_gpu.closed
 sensed.close();await sensed.closed
 # Actual resident hazard receipt must retain the immutable source permission.
 var attacker=Sim.Cell.new(33,Vector2(500,500))
 var victim=Sim.Cell.new(34,Vector2(1500,1000))
 sim.cells=[attacker,victim];sim.player=attacker;sim.lineage.root_id=attacker.lineage_id();sim.managed_lineages=[victim.lineage_id()]
 var source: int=sim._attack_owner(attacker,true);sim.prepare_combat_rules()
 var packets:=PackedFloat32Array([1500,1000,0,0,0,0,0,4,8,.2,.2,0])
 var contact=GPU.new();contact.configure_interactions("chemistry");contact.configure_exchange();contact.configure_perception();contact.configure_exposure()
 contact.initialize(packets,Fixture.flow(),[{"slot":0,"owner":source,"lineage":attacker.lineage_id()}])
 var ready: Array=await contact.ready;check(ready[0],str(ready[1]))
 var receipt: Dictionary=contact.exchange_sync([victim],[],[],[],{"feeding":false,"exposure":true,"projection":false})
 check(receipt.exposure.hits[0].size()==1 and receipt.exposure.hits[0][0].owner==source,"Resident contact carries the policy identity without resolving a live source")
 var bridge=preload("res://scripts/resident_ecology.gd").new();bridge.world=weakref(sim)
 var hp: float=victim.health
 bridge._apply_exposure([victim],receipt.exposure)
 check(victim.health==hp and absf(victim.waste-.2)<.00001,"Selective toxin becomes spent waste without hurting a peaceful body")
 contact.close();await contact.closed
 # ATP-starved weapons still emit actual material into the resident owner.
 var low=Sim.new(731,0,false);low.cells=[low.player]
 low.player.organs.clear();low.player.add_organ("poreforming",0,"graze",false)
 low.player.energy=0;low.player.biomass=10;low.player.target_id=999
 low.player.target_memory=1;low.player.target_mode="hunt"
 low.player.target_position=low.player.position+Vector2(100,0)
 low.player.add_organ("hunting",1,"hunt",false)
 low.player.behavior["weapon_cue"]={"at":low.player.target_position,"id":999,"organ_id":low.player.organs[-1].id,"expires_at":10.0,"lineage":999}
 var owner=preload("res://scripts/resident_ecology.gd").new();owner.streaming_enabled=false
 owner.start(low,512)
 var owner_ready: Array=await owner.initialized;check(owner_ready[0],str(owner_ready[1]))
 low._emit_and_attack(low.player,.01)
 var admitted: Dictionary=owner._receipt([],[],{"feeding":false,"projection":false,"chemistry":false})
 check(not admitted.has("error") and owner.pending.is_empty(),"Zero-ATP pore burst is accepted by the actual hardware resident owner")
 var low_packets: Array=owner.snapshots()
 var emitted:=0.0;var pieces:=0
 for packet in low_packets:
  if packet.kind in [Sim.TAG,Sim.PORE_SUBUNIT]:
   emitted+=packet.amount
   if packet.kind==Sim.PORE_SUBUNIT:pieces+=1
 check(absf(emitted-.18)<.000001 and pieces==4 and absf(low.player.biomass-9.82)<.000001,"Low-power resident burst retains its finite tag, four pore pieces and actual tissue debit")
 low._emit_and_attack(low.player,1)
 check(is_equal_approx(low.player.organs[0].burst_clock,.5) and low.player.energy==0,"Resident weapon advances its shared quarter-speed recharge without negative ATP")
 owner.gpu.advance(.01,1)
 owner._receipt([],[],{"feeding":false,"projection":false,"chemistry":false})
 check(owner.ready and owner.fallback_reason=="" and low.particles.is_empty(),"Low-power secretion keeps GPU authority without a CPU pose mirror or fallback")
 low_packets=owner.snapshots()
 check(low_packets.all(func(packet):return packet.p.is_finite() and is_finite(packet.amount)),"Residual low_packets remain finite under actual resident transport")
 low.player.energy=18;low._emit_and_attack(low.player,.25)
 check(is_equal_approx(low.player.organs[0].burst_clock,.25) and not low.player.behavior.has("low_power"),"The resident path resumes normal recharge after real ATP replenishment")
 owner.close();await owner.gpu.closed
 print("FEEDBACK PASS GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
