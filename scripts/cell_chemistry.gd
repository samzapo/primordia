extends RefCounted
## Finite food/waste vacuoles. ATP and biomass are numeric cell resources.
const Catalog = preload("res://scripts/chemistry_catalog.gd")
const MAX_VACUOLES := 12
const MAX_PACKETS := MAX_VACUOLES*2
const DIGESTION_RATE := 1.8
const BIOMASS_YIELD := 0.7
var model_version := 1
var particles: Array = []
var totals: Dictionary = {}
var vacuoles: Array = []
var owner: WeakRef
var accelerator
var next_packet := 0
var tick := 0
var bins: Dictionary = {}
var presentation_totals: Dictionary = {}
var render_origins: Dictionary = {}
var pending_time := 0.0
var coarse_due := -1.0
var simulated_time := 0.0
var fine_updates := 0
var coarse_updates := 0
var heat := 0.0
var expelled := 0.0
var frame_dt := 1.0
# Empty compatibility fields read by old saved blueprints; no active pathways.
var nodes: Array = []
var edges: Array = []
var reactor_mass := 0.0
var light_flux := 0.0
var solar_work := 0.0
var flux: Dictionary = {}
var limiting: Dictionary = {}

func setup(cell) -> void: owner=weakref(cell)
func amount(species: String) -> float: return maxf(0,float(totals.get(species,0)))
func material() -> float: return float(presentation_totals.get("material",amount("food")+amount("waste")))
func storage_used() -> float: return 0.0
func potential() -> float: return float(presentation_totals.get("potential",raw_fuel()))
func raw_fuel() -> float:
	if not presentation_totals.is_empty():return float(presentation_totals.get("raw_fuel",0))
	if accelerator!=null:return accelerator.value(66)
	var result:=0.0
	for packet in particles:result+=packet.fuel
	return result
func _index(_packet: Dictionary) -> void: pass
func _quantum(_species: String) -> float: return 4.0

func emit(species: String, quantity: float, at: Vector2, source: int=-1, compartment: int=-1, fuel: float=-1, _spread: float=0) -> void:
	if quantity<=0 or species not in ["food","waste"]:return
	fuel=quantity*7.5 if fuel<0 and species=="food" else maxf(0,fuel)
	if accelerator!=null:accelerator.command(1,quantity,at,0,-1,source,compartment,fuel,0,species);return
	var chosen: Dictionary={}
	var count:=0
	for packet in particles:
		if packet.species!=species:continue
		count+=1
		if chosen.is_empty() or packet.p.distance_squared_to(at)<chosen.p.distance_squared_to(at):chosen=packet
	# Coalesce only the same compartment, or bounded overflow into an existing
	# carrier. This changes parcel resolution, never represented material/fuel.
	if not chosen.is_empty() and (count>=MAX_VACUOLES or (chosen.compartment==compartment and chosen.p.distance_squared_to(at)<16)):
		chosen.amount+=quantity;chosen.fuel+=fuel
	else:
		particles.append({"id":next_packet,"species":species,"amount":quantity,"fuel":fuel,"p":at,"previous":at,"v":Vector2.ZERO,"angle":next_packet*2.399963,"source":source,"compartment":next_packet if compartment<0 else compartment,"alive":true})
		next_packet+=1
	refresh()
func _consume(packet: Dictionary, quantity: float) -> float:
	quantity=minf(quantity,packet.amount)
	var fuel: float=packet.fuel*quantity/maxf(.00000001,packet.amount)
	packet.amount-=quantity;packet.fuel-=fuel
	packet.alive=packet.amount>.0000001
	return fuel
func assign(species: String, quantity: float) -> void:
	if species not in ["food","waste"]:return
	quantity=maxf(0,quantity)
	if accelerator!=null:accelerator.command(6,quantity,owner.get_ref().local_point(0)*.7,0,-1,-1,-1,-1,0,species);return
	var difference:=quantity-amount(species)
	if difference>0:emit(species,difference,owner.get_ref().local_point(0)*.7)
	else:
		for packet in particles:
			if packet.species==species and difference<0:
				var used:=minf(-difference,packet.amount);_consume(packet,used);difference+=used
		refresh()
func set_raw_fuel(value: float) -> void:
	if accelerator!=null:accelerator.command(7,value);return
	var total:=amount("food")
	for packet in particles:
		if packet.species=="food":packet.fuel=maxf(0,value)*packet.amount/maxf(.00000001,total)
func receive(kind: int, quantity: float, capacity: float, world_at: Vector2) -> void:
	if kind!=0:return
	var cell=owner.get_ref()
	var local:=Vector2(wrapf(world_at.x-cell.position.x,-2048,2048),wrapf(world_at.y-cell.position.y,-1280,1280)).rotated(-cell.angle)
	local=local.normalized()*minf(local.length(),cell.support(local.angle()+cell.angle)*.78)
	emit("food",quantity,local,-1,-1,minf(quantity,capacity)*7.5)
func refresh() -> void:
	particles=particles.filter(func(packet):return packet.alive)
	totals.clear();vacuoles.clear()
	for packet in particles:
		totals[packet.species]=amount(packet.species)+packet.amount
		if packet.species=="food":vacuoles.append({"id":packet.compartment,"p":packet.p,"radius":3.8,"acid":0.0,"material":0.0,"age":0.0})
	for packet in particles:
		if packet.species!="waste":continue
		if vacuoles.any(func(v):return v.id==packet.compartment):continue
		vacuoles.append({"id":packet.compartment,"p":packet.p,"radius":3.8,"acid":1.0,"material":0.0,"age":0.0})
func advance(cell, dt: float, _external_osmolarity: float=.15) -> void:
	if dt<=0 or cell.dead or amount("food")+amount("waste")<=.0000001:return
	if accelerator!=null:accelerator.advance(dt,.15);return
	frame_dt=dt;tick+=1
	var budget: float=DIGESTION_RATE*cell.growth_scale()*dt
	var original:=particles.duplicate()
	for packet in original:
		packet.previous=packet.p
		if packet.species=="food" and budget>0:
			var used: float=minf(packet.amount,budget);budget-=used
			var fuel:=_consume(packet,used)
			var tissue:=minf(used,fuel/7.5)*BIOMASS_YIELD
			var atp:=maxf(0,fuel-tissue*7.5)
			cell.biomass+=tissue;cell.gain_energy(atp);cell.processed+=used
			emit("waste",used-tissue,packet.p,packet.source,packet.compartment,0)
	# Bounded analytic circulation, also for a coarse elapsed interval. Waste
	# follows its food carrier, then travels to the real cytoproct for release.
	for packet in particles:
		var carrier: Dictionary={}
		if packet.species=="waste":
			for food in particles:
				if food.species=="food" and food.compartment==packet.compartment:carrier=food;break
		var outlet: Vector2=cell.local_point(cell.excretion_angle())*.88
		if not carrier.is_empty():packet.p=carrier.p
		elif packet.species=="waste":packet.p=packet.p.move_toward(outlet,dt*maxf(6,cell.radius*.3))
		else:packet.p=packet.p.rotated(dt*.20)
		packet.p=constrain(cell,packet.p)
	refresh()
static func constrain(cell, at: Vector2) -> Vector2:
	var limit: float=cell.local_point(cell.surface_parameter(at.angle())).length()-4
	at=at.limit_length(maxf(1,limit))
	var center: Vector2=Vector2(-.12,-.10)*cell.radius
	var delta: Vector2=at-center
	if delta.length()<cell.radius*.22:at=center+delta.normalized()*cell.radius*.22 if delta.length()>.001 else center+Vector2.RIGHT*cell.radius*.22
	return at.limit_length(maxf(1,limit))
func excrete(sim, cell, dt: float) -> void:
	if amount("waste")<=.0000001:return
	var outlet: Vector2=cell.local_point(cell.excretion_angle())*.88
	if accelerator!=null:
		# The compact receipt already says whether any waste-only vacuole has
		# reached the outlet. Avoid an empty render-thread transaction.
		if not vacuoles.any(func(v):return v.acid>0 and v.p.distance_to(outlet)<=maxf(2,cell.radius*.08)):return
		accelerator.command(11,dt*4*cell.growth_scale(),outlet,maxf(2,cell.radius*.08))
		for packet in accelerator._unpack(accelerator.transfer):_expel(sim,cell,packet,packet.amount)
		return
	var budget: float=dt*4*cell.growth_scale()
	for packet in particles:
		if packet.species!="waste" or packet.p.distance_to(outlet)>maxf(2,cell.radius*.08):continue
		if particles.any(func(food):return food.species=="food" and food.compartment==packet.compartment):continue
		var used: float=minf(budget,packet.amount);budget-=used
		_consume(packet,used);_expel(sim,cell,packet,used)
	refresh()
func _expel(sim, cell, _packet: Dictionary, quantity: float) -> void:
	if quantity<=0:return
	var normal: Vector2=cell.local_normal(cell.excretion_angle()).rotated(cell.angle)
	sim.spawn_particle(2,cell.excretion_position()+normal*9,normal*12,quantity,cell.id)
	expelled+=quantity
func ensure_cpu() -> void:
	if accelerator!=null:accelerator.release()
func particle_count() -> int:return accelerator.live_count if accelerator!=null else int(presentation_totals.get("packets",particles.size()))
func particle_snapshots(presentation: bool=false) -> Array:return accelerator.snapshot(presentation) if accelerator!=null else particles
func clone_for(cell):
	var copy=get_script().new();copy.owner=weakref(cell)
	copy.particles=particle_snapshots().duplicate(true);copy.next_packet=next_packet;copy.tick=tick;copy.heat=heat;copy.expelled=expelled
	copy.presentation_totals=presentation_totals.duplicate(true);copy.refresh()
	return copy
# Archived pathway configuration is deliberately inactive in this revision.
func inherit_configuration(_parent) -> void:pass
func partition(_parent,_fraction: float) -> float:return 0.0
func anchor_photosynthesis(_cell,_organ: Dictionary) -> void:pass
func photosynthesize(_sim,_cell,_organ: Dictionary,_dt: float) -> void:pass
func configuration() -> Dictionary:return {"version":2,"model":"food-vacuoles"}
func load_configuration(_value: Dictionary) -> String:return "Pathway editing is retired; digestion is automatic."
func reserve_atp(quantity: float, storing: bool) -> void:
	var cell=owner.get_ref()
	quantity=minf(quantity,cell.energy if storing else cell.brood_energy)
	cell.energy+=-quantity if storing else quantity;cell.brood_energy+=quantity if storing else -quantity
