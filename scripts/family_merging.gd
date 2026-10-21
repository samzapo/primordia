extends RefCounted
## Explicit selection commits immediately; autonomous fusion still needs contact.
const MAX_FAMILY_CELLS:=12
const MIN_AGE:=60.0
const COOLDOWN:=120.0
const RECENT_SECONDS:=5.0
const MAX_RECENT:=64
static func managed(sim,cell) -> bool:
 return cell.id in sim.managed_cells or (not sim.server_mode and cell==sim.player)

static func eligible(sim,receiver,donor) -> bool:
 return receiver!=donor and not receiver.dead and receiver.health>0 and not donor.dead and donor.health>0 and receiver.lineage_id()==donor.lineage_id() and not managed(sim,donor) and not donor.unattended_protected

static func remember(sim,receiver,received: Dictionary) -> void:
 var memory: Dictionary=receiver.behavior.get("merge_cues",{})
 for id in memory.keys():
  if float(memory[id].get("expires_at",0))<=sim.time:memory.erase(id)
 for id in received:
  var cue: Dictionary=received[id]
  var report: Dictionary=cue.get("report",{})
  if float(cue.get("expires_at",0))<=sim.time or report.is_empty():continue
  if int(report.get("id",-1))!=int(id) or int(id)==receiver.id or int(report.get("lineage",-1))!=receiver.lineage_id():continue
  memory[id]={"report":report.duplicate(true),"received_at":sim.time,"expires_at":sim.time+RECENT_SECONDS}
 while memory.size()>MAX_RECENT:
  var oldest=memory.keys()[0]
  for id in memory:
   if float(memory[id].received_at)<float(memory[oldest].received_at):oldest=id
  memory.erase(oldest)
 receiver.behavior["merge_cues"]=memory

static func cue(sim,receiver,donor_id: int) -> Dictionary:
 for signals in [receiver.behavior.get("merge_cues",{}),receiver.behavior.get("family_cues",{})]:
  var item: Dictionary=signals.get(donor_id,{})
  var report: Dictionary=item.get("report",{})
  if float(item.get("expires_at",0))>sim.time and int(report.get("id",-1))==donor_id and int(report.get("lineage",-1))==receiver.lineage_id():
   return item
 return {}

static func detected(sim,receiver,donor_id: int) -> bool:
 return not cue(sim,receiver,donor_id).is_empty() and receiver.organs.any(func(organ):return organ.hp>0 and organ.kind in ["feeding","hunting","sensing","counterattack","family_toward","family_away"])

static func candidates(sim,receiver) -> Dictionary:
 var result: Dictionary={}
 for donor in sim.cells:
  if eligible(sim,receiver,donor) and detected(sim,receiver,donor.id):
   result[donor.id]=float(cue(sim,receiver,donor.id).expires_at)
 return result

static func neighborhood(receiver) -> float:
 # Fit the receiving cell and its local sensory neighborhood, never remote kin.
 var reach:=90.0
 for organ in receiver.organs:
  if organ.hp>0 and organ.kind in ["feeding","hunting","sensing","counterattack","family_toward","family_away"]:
   reach=maxf(reach,(120 if organ.kind=="hunting" else 90)*sqrt(organ.scale)*(1-organ.blocked*.65)*receiver.Genes.factor(organ,"sense"))
 return maxf(receiver.extent()*3,receiver.extent()+reach+32)

static func request(sim,donor_id: int) -> bool:
 var receiver=sim.player
 if not receiver.behavior.get("merge_order",{}).get("automatic",false):receiver.behavior.erase("merge_order")
 for donor in sim.cells:
  if donor.id==donor_id and eligible(sim,receiver,donor) and detected(sim,receiver,donor_id):
   # Selection is the transaction, not an instruction to navigate.
   # Eligibility and finite transfer remain; crowding never limits growth.
   return commit(sim,receiver,donor,true)
 return false

static func touching(sim,a,b) -> bool:
 var d: Vector2=sim.Medium.offset(a.position,b.position)
 return d.length()<=a.support(d.angle())+b.support(d.angle()+PI)+8

static func direction(sim,cell) -> Vector2:
 var order: Dictionary=cell.behavior.get("merge_order",{})
 if order.is_empty() or not order.get("automatic",false) or float(order.expires_at)<=sim.time:return Vector2.ZERO
 var received: Dictionary=cue(sim,cell,int(order.id))
 if received.is_empty():return Vector2.ZERO
 return sim.Medium.offset(cell.position,received.report.at).normalized()

static func living_families(sim) -> Dictionary:
 var families: Dictionary={}
 for cell in sim.cells:
  if cell.dead or cell.health<=0:continue
  var root: int=cell.lineage_id()
  if not families.has(root):families[root]=[]
  families[root].append(cell)
 return families

static func older(a,b) -> bool:
 if a.generation!=b.generation:return a.generation<b.generation
 if a.age!=b.age:return a.age>b.age
 return a.id<b.id

static func enforce_limit(sim) -> void:
 if sim.remote_client:return
 for family in living_families(sim).values():
  if family.size()<=MAX_FAMILY_CELLS:continue
  family.sort_custom(older)
  # Youngest generations donate first; prefer their surviving older parent.
  var donors: Array=family.duplicate();donors.reverse()
  for donor in donors:
   if family.size()<=MAX_FAMILY_CELLS:break
   if managed(sim,donor):continue
   var receiver=null
   var record: Dictionary=sim._family_ledger(donor).record_for(donor.id)
   for relative in family:
    if relative==donor or not older(relative,donor):continue
    if receiver==null:receiver=relative
    if relative.id==int(record.get("parent",-1)):
     receiver=relative;break
   if receiver!=null and commit(sim,receiver,donor,false,true):family.erase(donor)

static func step(sim) -> void:
 if sim.remote_client:return
 enforce_limit(sim)
 for cell in sim.cells:cell.behavior.erase("merge_order")

static func commit(sim,receiver,donor,from_selection: bool=false,for_capacity: bool=false) -> bool:
 if sim.remote_client or not eligible(sim,receiver,donor):return false
 if for_capacity:
  # The owner-authorized cap alone bypasses contact, cues, age and cooldown.
  # Ordinary manual/autonomous merges keep all their existing sensory gates.
  if not older(receiver,donor) or living_families(sim).get(receiver.lineage_id(),[]).size()<=MAX_FAMILY_CELLS:return false
 else:
  if not detected(sim,receiver,donor.id):return false
  if not from_selection and not touching(sim,receiver,donor):return false
 # Eligibility is checked before any transfer. Growth has no space/balance cap.
 # GPU ownership is
 # released once for this rare explicit transaction; normal simulation stays resident.
 var picture: Dictionary=preload("res://scripts/cell_portrait.gd").capture(donor)
 sim._flush_reserve_products(donor,true)
 receiver.chemistry.ensure_cpu();donor.chemistry.ensure_cpu()
 var ledger=sim._family_ledger(donor)
 for index in range(donor.organs.size()-1,-1,-1):
  if donor.inherent(donor.organs[index]):continue
  if not sim._recycle_for(donor,ledger.progression,index):return false
 # Inherent groove material is zero. Any bound membrane material joins the body.
 var solids: float=donor.body+donor.biomass+donor.brood_mass+donor.surface_material()
 receiver.biomass+=solids*.9
 if solids>0:sim.spawn_particle(sim.WASTE,receiver.excretion_position(),Vector2.ZERO,solids*.1,receiver.id)
 var available: float=donor.energy+donor.brood_energy
 receiver.energy+=available*.9;receiver.chemistry.heat+=available*.1
 receiver.ap=0
 var compartments: Dictionary={}
 receiver.chemistry.batching=true
 for packet in donor.chemistry.particles:
  if not packet.alive:continue
  var local: Vector2=sim.Medium.offset(receiver.position,donor.position+packet.p.rotated(donor.angle)).rotated(-receiver.angle)
  local=receiver.chemistry.constrain(receiver,local,1.4 if packet.species in ["oxygen","carbon"] else 7.0)
  var nutrition: float=float(packet.get("nutrition",0))/maxf(.000000001,packet.amount)
  if not compartments.has(packet.compartment):
   compartments[packet.compartment]=receiver.chemistry.next_packet
   receiver.chemistry.next_packet+=1
  var first_id: int=receiver.chemistry.next_packet
  receiver.chemistry.emit(packet.species,packet.amount,local,packet.source,compartments[packet.compartment],packet.fuel,0,nutrition)
  for transferred in receiver.chemistry.particles:
   if transferred.id>=first_id:
    transferred.age=float(packet.get("age",0))
    transferred.v=packet.v.rotated(donor.angle-receiver.angle)
    transferred.angle=packet.angle+donor.angle-receiver.angle
 receiver.chemistry.batching=false;receiver.chemistry.refresh()
 receiver.merge_after=sim.time+COOLDOWN
 receiver.behavior.erase("merge_order")
 receiver.update_geometry();receiver.render_revision+=1
 sim.merge_serial+=1
 sim.merge_bursts.append({"serial":sim.merge_serial,"time":sim.time,"donor":donor.id,"receiver":receiver.id,
  "at":donor.position,"to":receiver.position,"portrait":picture,"reason":"capacity" if for_capacity else "manual"})
 if sim.merge_bursts.size()>32:sim.merge_bursts.pop_front()
 donor.dead=true;donor.ap=0;donor.energy=0;donor.brood_energy=0
 donor.chemistry.particles.clear();donor.chemistry.refresh()
 sim.cells.erase(donor)
 ledger.records.erase(ledger.record_for(donor.id))
 sim.Investment.retire(sim,donor)
 # Preserve emitted owner-to-lineage snapshots for particles already in the pond.
 ledger.notify("Family cells merged. Organelles reabsorbed; resources combined.")
 # Bounded family notices carry fusion feedback; do not append unbounded history.
 return true
