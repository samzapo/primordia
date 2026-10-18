extends RefCounted
## Fusion is a local physical transaction, never a population cull or remote kill.
const MIN_AGE:=60.0
const COOLDOWN:=120.0
static func managed(sim,cell) -> bool:
 return cell.id in sim.managed_cells or (not sim.server_mode and cell==sim.player)

static func eligible(sim,receiver,donor) -> bool:
 return receiver!=donor and not receiver.dead and receiver.health>0 and not donor.dead and donor.health>0 and receiver.lineage_id()==donor.lineage_id() and not managed(sim,donor)

static func detected(sim,receiver,donor_id: int) -> bool:
 var cue: Dictionary=receiver.behavior.get("family_cues",{}).get(donor_id,{})
 var report: Dictionary=cue.get("report",{})
 if cue.is_empty() or float(cue.get("expires_at",0))<=sim.time:return false
 if int(report.get("id",-1))!=donor_id or int(report.get("lineage",-1))!=receiver.lineage_id():return false
 return receiver.organs.any(func(organ):return organ.hp>0 and organ.kind in ["feeding","hunting","sensing","counterattack","family_toward","family_away"])

static func candidates(sim,receiver) -> Dictionary:
 var result: Dictionary={}
 for donor in sim.cells:
  if eligible(sim,receiver,donor) and detected(sim,receiver,donor.id):
   result[donor.id]=float(receiver.behavior.family_cues[donor.id].expires_at)
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
 for donor in sim.cells:
  if donor.id==donor_id and eligible(sim,receiver,donor) and detected(sim,receiver,donor_id):
   receiver.behavior["merge_order"]={"id":donor.id,"expires_at":sim.time+60,"automatic":false}
   if touching(sim,receiver,donor):return commit(sim,receiver,donor)
   return true
 return false

static func touching(sim,a,b) -> bool:
 var d: Vector2=sim.Medium.offset(a.position,b.position)
 return d.length()<=a.support(d.angle())+b.support(d.angle()+PI)+8

static func direction(sim,cell) -> Vector2:
 var order: Dictionary=cell.behavior.get("merge_order",{})
 if order.is_empty() or float(order.expires_at)<=sim.time:return Vector2.ZERO
 var cue: Dictionary=cell.behavior.get("family_cues",{}).get(int(order.id),{})
 if cue.is_empty() or float(cue.expires_at)<=sim.time:return Vector2.ZERO
 return sim.Medium.offset(cell.position,cue.report.at).normalized()

static func step(sim) -> void:
 if sim.remote_client or sim.time<sim.merge_step_at:return
 var elapsed: float=clampf(sim.time-sim.merge_step_at+.5,0,5)
 sim.merge_step_at=sim.time+.5
 for cell in sim.cells.duplicate():
  if cell.dead or cell.health<=0:continue
  var cues: Dictionary=cell.behavior.get("family_cues",{})
  for id in cues.keys():
   if float(cues[id].expires_at)<=sim.time:cues.erase(id)
  var order: Dictionary=cell.behavior.get("merge_order",{})
  if not order.is_empty() and (float(order.expires_at)<=sim.time or (order.get("automatic",false) and managed(sim,cell))):
   cell.behavior.erase("merge_order");order={}
  if order.is_empty() and not managed(sim,cell) and cell.age>=MIN_AGE and sim.time>=cell.merge_after:
   var chance: float=1-exp(-(.2 if cues.size()>=4 else .02)*elapsed)
   if sim.ecology_rng.randf()<chance:
    for id in cues.keys():
     # A canonical recipient prevents two relatives choosing each other.
     if int(id)>cell.id:
      cell.behavior["merge_order"]={"id":int(id),"expires_at":sim.time+60,"automatic":true}
      order=cell.behavior.merge_order;break
  if order.is_empty() or not detected(sim,cell,int(order.id)):continue
  for donor in sim.cells.duplicate():
   if donor.id!=int(order.id) or not eligible(sim,cell,donor):continue
   if order.get("automatic",false) and (donor.age<MIN_AGE or sim.time<donor.merge_after):continue
   # Looking up a live body here validates actual contact only. Navigation uses
   # the immutable received chemical cue above, never this body's live position.
   if touching(sim,cell,donor):commit(sim,cell,donor)
   break

static func commit(sim,receiver,donor) -> bool:
 if not eligible(sim,receiver,donor) or not detected(sim,receiver,donor.id) or not touching(sim,receiver,donor):return false
 var organ_material: float=donor.organ_mass()
 var solids: float=donor.body+donor.biomass+donor.brood_mass+donor.surface_material()+organ_material*.5
 var radius: float=receiver.tissue_radius(receiver.body+receiver.biomass+receiver.brood_mass+solids*.9)
 var extent: float=radius*maxf(1.05,receiver.extent()/maxf(1,receiver.radius))
 if not sim.habitat_geometry.clear_at(receiver.position,extent):return false
 for other in sim.cells:
  if other==receiver or other==donor or other.dead:continue
  if sim.Medium.offset(receiver.position,other.position).length()<extent+other.extent()+4:return false
 # Complete all preflight checks before any irreversible work. GPU ownership is
 # released once for this rare explicit transaction; normal simulation stays resident.
 receiver.chemistry.ensure_cpu();donor.chemistry.ensure_cpu()
 var ledger=sim._family_ledger(donor)
 for index in range(donor.organs.size()-1,-1,-1):
  if donor.inherent(donor.organs[index]):continue
  if not sim._recycle_for(donor,ledger.progression,index):return false
 # Inherent groove material is zero. Any bound membrane material joins the body.
 solids=donor.body+donor.biomass+donor.brood_mass+donor.surface_material()
 receiver.biomass+=solids*.9
 if solids>0:sim.spawn_particle(sim.WASTE,receiver.excretion_position(),Vector2.ZERO,solids*.1,receiver.id)
 var available: float=donor.energy+donor.brood_energy
 receiver.energy+=available*.9;receiver.chemistry.heat+=available*.1
 receiver.ap+=donor.ap
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
 donor.dead=true;donor.ap=0;donor.energy=0;donor.brood_energy=0
 donor.chemistry.particles.clear();donor.chemistry.refresh()
 sim.cells.erase(donor)
 ledger.records.erase(ledger.record_for(donor.id))
 sim.investment.cells.erase(donor.id);sim.investment.npc.erase(donor.id)
 # Preserve emitted owner-to-lineage snapshots for particles already in the pond.
 ledger.notify("Family cells merged. Organelles reabsorbed; AP and resources combined.")
 # Bounded family notices carry fusion feedback; do not append unbounded history.
 return true
