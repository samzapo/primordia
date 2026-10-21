extends RefCounted
## Contact feeding: finite donor biomass becomes finite tissue-fuel food.
const Medium=preload("res://scripts/medium.gd")
const RATE:=2.0
const ATP_PER_UNIT:=0.5
static func tip(cell,organ: Dictionary) -> Vector2:
 return cell.organ_position(organ)+cell.organ_normal(organ).rotated(cell.angle)*27*organ.scale

static func touches(donor,at: Vector2,margin: float) -> bool:
 var local: Vector2=Medium.offset(donor.position,at).rotated(-donor.angle)
 var outline: PackedVector2Array=donor.membrane.outline()
 if Geometry2D.is_point_in_polygon(local,outline):return true
 for i in outline.size():
  if Geometry2D.get_closest_point_to_segment(local,outline[i],outline[(i+1)%outline.size()]).distance_squared_to(local)<=margin*margin:return true
 return false

static func step(sim,cell,dt: float) -> void:
 if sim.remote_client or cell.dead or dt<=0:return
 for organ in cell.organs:
  if organ.kind!="proboscis" or organ.hp<=0:continue
  organ.feeding=false
  var at:=tip(cell,organ);var chosen=null;var distance:=INF
  var candidates: Array=sim.cell_index.at(at) if sim.spatial_queries else range(sim.cells.size())
  for index in candidates:
   var donor=sim.cells[index]
   if donor==cell or donor.dead or donor.health<=0 or donor.unattended_protected or donor.biomass<=0 or not donor.accepts_attack(cell.id):continue
   var d:=Medium.offset(at,donor.position).length_squared()
   if d>pow(donor.extent()+6*organ.scale,2) or not touches(donor,at,6*organ.scale):continue
   if chosen==null or d<distance or (d==distance and donor.id<chosen.id):chosen=donor;distance=d
  if chosen==null:continue
  var amount: float=minf(chosen.biomass,minf(maxf(0,cell.gut_capacity()-cell.substrate),RATE*organ.scale*organ.scale*organ.hp/organ.max_hp*dt*cell.work_capacity()))
  amount=minf(amount,(cell.energy+cell.biomass)/ATP_PER_UNIT) # A meal never funds its own capture.
  if amount<=0:continue
  cell.spend_energy(amount*ATP_PER_UNIT,organ,"contact feeding")
  chosen.biomass-=amount
  cell.chemistry.emit("food",amount,cell.chemistry.constrain(cell,cell.organ_local_position(organ)*.8,7),organ.id,-1,amount*cell.Chemistry.TISSUE_FUEL)
  cell.eaten+=amount
  if chosen.id!=cell.id:cell.foreign_intake+=amount
  cell.consumed(organ,amount);cell.emitted(organ)
  organ.feeding=true;organ.link=at;chosen.last_wound=Medium.offset(chosen.position,at).angle()-chosen.angle
  chosen.render_revision+=1;cell.render_revision+=1
