extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Validity=preload("res://scripts/network/world_validity.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize() -> void:run.call_deferred()
func fixture(count: int=1):
 var sim=Sim.new(775,0,false);sim.server_mode=true;sim.evolution.sandbox=true
 sim.cells=[sim.player];sim.player.organs.clear();sim.player.add_organ("feeding",0,"graze",false)
 sim.lineage.records.clear();sim.lineage.total_cells=0;sim.lineage.highest_generation=0;sim.lineage.initialize(sim)
 sim.player.position=Vector2(320,320);sim.player.previous_position=sim.player.position
 sim.player.age=1000;sim.automatic_reproduction=false
 sim.habitat_geometry=Sim.Habitat.new(775,sim.cells);sim.habitat_geometry.enabled=false
 for i in range(1,count):
  var cell=Sim.Cell.new(100+i,Vector2(1000+i*190,1400))
  cell.lineage=sim.player.lineage_id();cell.age=1000-i;cell.ap=0
  cell.add_organ("feeding",0,"graze",false);sim.cells.append(cell)
  sim.lineage.register(cell,sim.player.id,i,"living",0)
 sim.next_id=1000
 return sim
func fund(sim,cell) -> void:
 cell.biomass=200;cell.energy=100
 cell.brood_mass=0;cell.brood_energy=0;cell.reproduction_retry_at=0
 cell.update_geometry()
func material(sim) -> float:
 var amount: float=sim.build_waste
 for cell in sim.cells:amount+=cell.organic_mass()
 for packet in sim.particle_snapshots():
  if packet.alive:amount+=packet.amount*sim.Catalog.material(packet.kind)
 return amount
func energy(sim) -> float:
 return sim.cells.reduce(func(total,cell):return total+cell.energy+cell.brood_energy+cell.chemistry.heat,0.0)
func run() -> void:
 check(Sim.Cell.new(80).automatic_division,"New cells default to Auto divide")
 var manual=fixture();manual.player.automatic_division=false
 check(not manual.make_offspring(manual.player,manual.offspring_quote()).automatic_division,"Daughters preserve an explicit manual parent choice")
 check(not Codec.new().restore(Codec.new().capture(manual)).player.automatic_division,"Saved manual choices remain manual across updates")
 for mode in ["mitosis","budding"]:
  for follow in [false,true]:
   var capped=fixture(12);fund(capped,capped.player)
   var before=Codec.new().capture(capped)
   check(not capped.Lifecycle.quote(capped,capped.player,mode).ready,"Family cap blocks "+mode+" before construction")
   check(not capped.Lifecycle.reproduce(capped,capped.player,capped.lineage,mode,follow),"At-cap reproduction does not start")
   check(Codec.new().capture(capped)==before,"Blocked birth spends no resources, identity, counters or cooldown and produces no merge")
 var full=fixture(64)
 for i in full.cells.size():full.cells[i].lineage=i/8
 fund(full,full.player)
 for mode in ["mitosis","budding"]:
  var before=Codec.new().capture(full)
  check(not full.Lifecycle.quote(full,full.player,mode).ready and not full.Lifecycle.reproduce(full,full.player,full.lineage,mode),"Pond cap blocks "+mode+" even with family room")
  check(Codec.new().capture(full)==before,"Full pond leaves existing cells and resources unchanged")
 var near=fixture(63)
 for i in near.cells.size():near.cells[i].lineage=near.cells[i].id
 fund(near,near.player);fund(near,near.cells[1])
 check(near.Lifecycle.reproduce(near,near.player,near.lineage,"budding") and near.cells.size()==64,"The last pond place can be filled")
 check(not near.Lifecycle.reproduce(near,near.cells[1],near._family_ledger(near.cells[1]),"budding") and near.cells.size()==64,"A second same-tick birth sees the newly filled pond cap")
 # The ledger lookup above is a test setup operation; the failed birth itself
 # must preserve its funded parent and cannot produce a birth/merge event.
 check(near.cells[1].biomass==200 and near.cells[1].energy==100 and near.merge_bursts.is_empty(),"Second candidate retains all resources without a compensating merge")
 var independent=fixture(14)
 for i in 15:
  var other=Sim.Cell.new(8000+i,Vector2(2000,2000));other.lineage=8000;other.generation=i
  independent.cells.append(other)
 independent.FamilyMerging.enforce_limit(independent)
 check(independent.cells.size()==24 and independent.FamilyMerging.living_families(independent).values().all(func(family):return family.size()==12),"Two oversized lineages reconcile independently to 12 each")
 var inactive=fixture(13);inactive.cells[-1].health=0
 inactive.FamilyMerging.enforce_limit(inactive)
 check(inactive.cells.size()==13 and inactive.merge_bursts.is_empty(),"Only living healthy bodies count toward the family maximum")
 var sim=fixture(11);fund(sim,sim.player);var parent=sim.player
 check(sim.divide_lineage(false,true) and sim.cells.size()==12 and sim.player!=parent and not sim.player.dead,"The twelfth cell stays alive and normal follow selection works")
 check(sim.player.automatic_division,"Ordinary Auto divide daughters inherit enabled auto")
 sim=fixture(12);parent=sim.player;fund(sim,parent);sim.automatic_reproduction=true
 var cap_rng: int=sim.ecology_rng.state
 for second in 300:
  sim.time=second;sim._step_reproduction()
 check(sim.cells.size()==12 and sim.lineage.births==0 and sim.merge_bursts.is_empty(),"Five minutes at capacity start no automatic birth/merge cycle")
 check(parent.biomass==200 and parent.energy==100 and sim.ecology_rng.state==cap_rng and parent.automatic_division,"Capped automatic checks spend no resources or random draws and keep auto enabled")
 sim=fixture(12);parent=sim.player;fund(sim,parent)
 check(not sim.request_division() and sim.cells.size()==12 and not parent.division_requested,"Retired investment commands cannot queue a hidden birth")
 sim=fixture(18);sim.managed_cells=[sim.cells[-1].id];var protected=sim.cells[-1]
 var mass:=material(sim);var atp:=energy(sim);var total: int=sim.lineage.total_cells
 var rng: int=sim.ecology_rng.state;var before=Codec.new().capture(sim)
 var restored=Codec.new().restore(before)
 check(restored.cells.size()==18 and restored.lineage.total_cells==total,"Restore preserves all saved cells before the first authority tick")
 restored.FamilyMerging.enforce_limit(restored)
 check(restored.cells.size()==12 and Validity.error(restored).is_empty(),"Disconnected saved families reconcile after startup without a reset")
 sim.FamilyMerging.enforce_limit(sim)
 check(sim.cells.size()==12 and sim.cells.has(protected),"Oversized families shrink to 12 while protecting connected selected donors")
 check(sim.merge_bursts.map(func(event):return event.donor)==[116,115,114,113,112,111],"Youngest generations donate first, skipping the controlled younger body")
 check(sim.merge_bursts.all(func(event):return event.receiver==sim.player.id),"A surviving older parent receives the excess descendants")
 check(absf(material(sim)-mass)<.0001 and absf(energy(sim)-atp)<.0001,"Existing family reconciliation conserves material, ATP plus heat")
 check(sim.ecology_rng.state==rng and sim.lineage.total_cells==total and sim.lineage.births==0 and sim.lineage.deaths==0,"Cap reconciliation changes no randomness, births, deaths or lifetime totals")
 check(sim.lineage.records.size()==12 and sim.death_bursts.is_empty(),"Consumed cells leave family portraits without death animations")
 var second=Sim.Cell.new(8000,Vector2(2400,2400));second.lineage=8000;sim.cells.append(second)
 sim.FamilyMerging.enforce_limit(sim)
 check(sim.cells.has(second) and sim.cells.size()==13,"The cap is per lineage, not a whole-pond count")
 var roundtrip=Codec.new().restore(Codec.new().capture(sim))
 check(roundtrip.cells.size()==13 and roundtrip.lineage.total_cells==total,"Saved reconciliation never resurrects consumed daughters or duplicates resources")
 sim=fixture(14)
 for cell in sim.cells:cell.generation=4;cell.age=20
 sim.cells[2].age=30
 sim.FamilyMerging.enforce_limit(sim)
 check(sim.cells.size()==12 and sim.merge_bursts.map(func(event):return event.donor)==[113,112],"Same-generation excess uses age and then ID")
 check(sim.merge_bursts.all(func(event):return event.receiver==sim.player.id),"An older surviving parent remains preferred within a generation")
 sim=fixture(13);var donor=sim.cells[-1];var actual_parent=sim.cells[5]
 sim.lineage.record_for(donor.id).parent=actual_parent.id
 sim.FamilyMerging.enforce_limit(sim)
 check(sim.merge_bursts[0].receiver==actual_parent.id,"An available older parent receives its own daughter")
 sim=fixture(13);sim.managed_cells=sim.cells.map(func(cell):return cell.id)
 sim.FamilyMerging.enforce_limit(sim)
 check(sim.cells.size()==13 and sim.merge_bursts.is_empty(),"Protected bodies never silently bypass player ownership")
 sim.managed_cells=[];sim.FamilyMerging.enforce_limit(sim)
 check(sim.cells.size()==12,"A blocked family reconciles when a donor becomes unattended")
 sim=fixture(13);donor=sim.cells[-1]
 check(not sim.FamilyMerging.request(sim,donor.id) and sim.cells.has(donor),"Cap policy grants no new ordinary merge targeting permission")
 sim.remote_client=true;sim.FamilyMerging.enforce_limit(sim)
 check(sim.cells.size()==13,"Clients never enforce or transfer authoritative population state")
 if "--gpu" in OS.get_cmdline_user_args():await resident_case()
 print("FAMILY CAP: %d assertions, %d failures" % [checks,failures])
 quit(0 if failures==0 else 1)
func resident_case() -> void:
 var sim=fixture(13);var receiver=sim.player;var donor=sim.cells[-1]
 sim.particles.clear();sim.grid.clear()
 donor.chemistry.emit("food",2,Vector2.ZERO,donor.id,7,18)
 donor.chemistry.emit("oxygen",1,Vector2(2,0))
 var bridge=preload("res://scripts/resident_ecology.gd").new();bridge.start(sim,8192)
 var ready: Array=await bridge.initialized
 check(ready[0],str(ready[1]))
 if not ready[0]:return
 for cell in [receiver,donor]:
  check(preload("res://scripts/resident_cytoplasm.gd").new().attach(bridge.gpu,cell.chemistry,cell),"Cap participants have resident internal chemistry")
 var food: float=receiver.substrate+donor.substrate;var oxygen: float=receiver.oxygen+donor.oxygen
 var mass:=material(sim);
 sim._step_reproduction()
 check(sim.cells.size()==12 and not sim.cells.has(donor) and sim.resident==bridge,"The actual resident authority reconciles without CPU fallback")
 check(absf(receiver.substrate-food)<.0001 and absf(receiver.oxygen-oxygen)<.0001,"Resident internal food and oxygen transfer through the existing merge")
 check(absf(material(sim)-mass)<.001 and Validity.error(sim).is_empty(),"Resident cap transfer retains finite material accounting")
 check(sim.particles.is_empty() and sim.pheromones.is_empty(),"External chemistry retains resident ownership without a CPU mirror")
 for cell in sim.cells:cell.chemistry.ensure_cpu()
 bridge.close();await bridge.gpu.closed
