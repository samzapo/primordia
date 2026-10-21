extends RefCounted
## Contact feeding: finite donor biomass becomes finite tissue-fuel food.
const Medium=preload("res://scripts/medium.gd")
const RATE:=2.0
const ATP_PER_UNIT:=0.5
static func reach(cell,organ: Dictionary) -> float:
 # A concave Hunter membrane must not hide the feeding tip behind its own points.
 return maxf(27*organ.scale,cell.extent()-cell.organ_local_position(organ).dot(cell.organ_normal(organ))+8*organ.scale)

static func local_segment(cell,organ: Dictionary) -> PackedVector2Array:
 var base: Vector2=cell.organ_local_position(organ)
 return PackedVector2Array([base,base+cell.organ_normal(organ)*reach(cell,organ)])

static func tip(cell,organ: Dictionary) -> Vector2:
 return cell.organ_position(organ)+cell.organ_normal(organ).rotated(cell.angle)*reach(cell,organ)

static func touches(donor,at: Vector2,margin: float) -> bool:
 var local: Vector2=Medium.offset(donor.position,at).rotated(-donor.angle)
 var outline: PackedVector2Array=donor.membrane.outline()
 if Geometry2D.is_point_in_polygon(local,outline):return true
 for i in outline.size():
  if Geometry2D.get_closest_point_to_segment(local,outline[i],outline[(i+1)%outline.size()]).distance_squared_to(local)<=margin*margin:return true
 return false

static func contact(donor,from: Vector2,at: Vector2) -> Dictionary:
 var start:=Medium.offset(donor.position,from).rotated(-donor.angle)
 var end:=Medium.offset(donor.position,at).rotated(-donor.angle)
 var outline: PackedVector2Array=donor.membrane.outline()
 var chosen: Dictionary={};var distance:=INF
 for i in outline.size():
  var a:=outline[i];var b:=outline[(i+1)%outline.size()]
  var hit=Geometry2D.segment_intersects_segment(start,end,a,b)
  var point: Vector2=hit if hit!=null else Geometry2D.get_closest_point_to_segment(end,a,b)
  var d: float=start.distance_squared_to(point) if hit!=null else end.distance_squared_to(point)
  # An actual tube/edge intersection takes precedence over the nearest-tip fallback.
  var crossing: bool=hit!=null
  if not chosen.is_empty() and chosen.crossing and not crossing:continue
  if chosen.is_empty() or (crossing and not chosen.crossing) or d<distance:
   chosen={"cell":donor.id,"edge":i,"t":clampf((point-a).dot(b-a)/maxf(.000001,a.distance_squared_to(b)),0,1),"crossing":crossing};distance=d
 chosen.erase("crossing")
 return chosen

static func step(sim,cell,dt: float) -> void:
 if sim.remote_client or cell.dead or dt<=0:return
 for organ in cell.organs:
  if organ.kind=="proboscis":organ.feeding=false;organ.erase("proboscis_contact")
 if sim.Behavior.sated(cell):return
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
  var unit_cost: float=ATP_PER_UNIT+cell.metabolic_upkeep(organ)/(RATE*organ.scale*organ.scale)
  amount=minf(amount,(cell.energy+cell.biomass*cell.Chemistry.RESERVE_ATP)/unit_cost) # A meal never funds its own capture.
  if amount<=0:continue
  cell.spend_energy(amount*unit_cost,organ,"contact feeding")
  # Drain stored biomass only. Never debit structural body/health or create a wound.
  chosen.biomass-=amount
  cell.chemistry.emit("food",amount,cell.chemistry.constrain(cell,cell.organ_local_position(organ)*.8,7),organ.id,-1,amount*cell.Chemistry.TISSUE_FUEL)
  cell.eaten+=amount
  if chosen.id!=cell.id:cell.foreign_intake+=amount
  cell.consumed(organ,amount);cell.emitted(organ)
  organ.proboscis_contact=contact(chosen,cell.organ_position(organ),at)
  organ.feeding=true;organ.link=at;chosen.last_wound=Medium.offset(chosen.position,at).angle()-chosen.angle
  chosen.render_revision+=1;cell.render_revision+=1
