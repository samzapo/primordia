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
  cell.lineage=sim.player.lineage_id();cell.age=1000-i;cell.ap=i
  cell.add_organ("feeding",0,"graze",false);sim.cells.append(cell)
  sim.lineage.register(cell,sim.player.id,i,"living",0)
 sim.next_id=1000
 return sim
func fund(sim,cell) -> void:
 cell.biomass=200;cell.energy=100
 cell.brood_mass=sim.offspring_quote(cell).material;cell.brood_energy=60
 cell.update_geometry()
func material(sim) -> float:
 var amount: float=sim.build_waste
 for cell in sim.cells:amount+=cell.organic_mass()
 for packet in sim.particle_snapshots():
  if packet.alive:amount+=packet.amount*sim.Catalog.material(packet.kind)
 return amount
func energy(sim) -> float:
 return sim.cells.reduce(func(total,cell):return total+cell.energy+cell.brood_energy+cell.chemistry.heat,0.0)
func points(sim) -> int:
 return sim.cells.reduce(func(total,cell):return total+cell.ap,0)
func run() -> void:
 check(Sim.Cell.new(80).automatic_division,"New cells default to Auto divide")
 var manual=fixture();manual.player.automatic_division=false
 check(not manual.make_offspring(manual.player,manual.offspring_quote()).automatic_division,"Daughters preserve an explicit manual parent choice")
 check(not Codec.new().restore(Codec.new().capture(manual)).player.automatic_division,"Saved manual choices remain manual across updates")
 for follow in [false,true]:
  var sim=fixture(12);var parent=sim.player;fund(sim,parent)
  var mass:=material(sim);var atp:=energy(sim);var ap:=points(sim);var serial: int=sim.next_id
  var births: int=sim.lineage.births;var total: int=sim.lineage.total_cells
  check(sim.division_status().ready and sim.divide_lineage(false,follow),"At-cap division is allowed to commit normally")
  check(sim.cells.size()==12 and sim.player==parent and not parent.dead,"Only the new excess daughter folds back; follow never selects a consumed body")
  check(sim.lineage.births==births+1 and sim.lineage.total_cells==total+1 and sim.next_id==serial+1,"The completed paid birth retains its identity and lifetime counters")
  check(points(sim)==ap+2 and parent.ap>=2,"Both ordinary division AP awards transfer once to the surviving parent")
  check(absf(material(sim)-mass)<.0001 and absf(energy(sim)-(atp-20))<.0001,"Existing waste/heat yields conserve material and account for the paid division ATP")
  check(sim.merge_bursts.size()==1 and sim.merge_bursts[0].donor==serial and sim.merge_bursts[0].receiver==parent.id,"The daughter has one visible pull-in to its actual parent")
  check(sim.lineage.deaths==0 and sim.death_bursts.is_empty(),"Population merges produce no death reports or lysis")
  check(Validity.error(sim).is_empty(),"Paid folding leaves every resource and physical field finite")
  var ap_after:=points(sim);sim._step_reproduction();sim.FamilyMerging.enforce_limit(sim)
  check(points(sim)==ap_after and sim.merge_bursts.size()==1,"A repeated tick cannot repeat the transfer or AP award")
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
 sim._step_reproduction()
 check(sim.cells.size()==12 and sim.lineage.births==1 and parent.automatic_division,"Automatic reproduction follows the same paid cap transaction")
 sim=fixture(12);parent=sim.player;fund(sim,parent)
 check(sim.request_division() and sim.cells.size()==12 and not parent.division_requested and not parent.automatic_division,"A queued one-shot completes once at the cap without enabling continuous auto")
 sim=fixture(18);sim.managed_cells=[sim.cells[-1].id];var protected=sim.cells[-1]
 var mass:=material(sim);var atp:=energy(sim);var ap:=points(sim);var total: int=sim.lineage.total_cells
 var rng: int=sim.ecology_rng.state;var before=Codec.new().capture(sim)
 var restored=Codec.new().restore(before)
 check(restored.cells.size()==18 and restored.lineage.total_cells==total,"Restore preserves all saved cells before the first authority tick")
 restored.FamilyMerging.enforce_limit(restored)
 check(restored.cells.size()==12 and Validity.error(restored).is_empty(),"Disconnected saved families reconcile after startup without a reset")
 sim.FamilyMerging.enforce_limit(sim)
 check(sim.cells.size()==12 and sim.cells.has(protected),"Oversized families shrink to 12 while protecting connected selected donors")
 check(sim.merge_bursts.map(func(event):return event.donor)==[116,115,114,113,112,111],"Youngest generations donate first, skipping the controlled younger body")
 check(sim.merge_bursts.all(func(event):return event.receiver==sim.player.id),"A surviving older parent receives the excess descendants")
 check(absf(material(sim)-mass)<.0001 and absf(energy(sim)-atp)<.0001 and points(sim)==ap,"Existing family reconciliation conserves material, ATP plus heat and all AP")
 check(sim.ecology_rng.state==rng and sim.lineage.total_cells==total and sim.lineage.births==0 and sim.lineage.deaths==0,"Cap reconciliation changes no randomness, births, deaths or lifetime totals")
 check(sim.lineage.records.size()==12 and sim.death_bursts.is_empty(),"Consumed cells leave family portraits without death animations")
 var second=Sim.Cell.new(8000,Vector2(2400,2400));second.lineage=8000;sim.cells.append(second)
 sim.FamilyMerging.enforce_limit(sim)
 check(sim.cells.has(second) and sim.cells.size()==13,"The cap is per lineage, not a whole-pond count")
 var roundtrip=Codec.new().restore(Codec.new().capture(sim))
 check(roundtrip.cells.size()==13 and points(roundtrip)==points(sim) and roundtrip.lineage.total_cells==total,"Saved reconciliation never resurrects consumed daughters or duplicates resources")
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
 var mass:=material(sim);var ap:=points(sim)
 sim._step_reproduction()
 check(sim.cells.size()==12 and not sim.cells.has(donor) and sim.resident==bridge,"The actual resident authority reconciles without CPU fallback")
 check(absf(receiver.substrate-food)<.0001 and absf(receiver.oxygen-oxygen)<.0001,"Resident internal food and oxygen transfer through the existing merge")
 check(absf(material(sim)-mass)<.001 and points(sim)==ap and Validity.error(sim).is_empty(),"Resident cap transfer retains finite material and AP accounting")
 check(sim.particles.is_empty() and sim.pheromones.is_empty(),"External chemistry retains resident ownership without a CPU mirror")
 for cell in sim.cells:cell.chemistry.ensure_cpu()
 bridge.close();await bridge.gpu.closed
