extends RefCounted
## Finite food/waste vacuoles. ATP and biomass are numeric cell resources.
const Catalog = preload("res://scripts/chemistry_catalog.gd")
const MAX_VACUOLES := 12
const MAX_GAS := 6
const MAX_PACKETS := MAX_VACUOLES*2+MAX_GAS*2
const ACTIVE_SPECIES := ["food","waste","oxygen","carbon"]
const REACTION_REACH := 20.0
const DIGESTION_RATE := 1.8
const ENERGY_DENSITY := 40.0
const AEROBIC_ATP := 2.25*ENERGY_DENSITY
const FERMENT_ATP := ENERGY_DENSITY
const RESERVE_ATP := ENERGY_DENSITY
const LEAF_BIOMASS := 0.035
const LEAF_FOOD := 1.0-LEAF_BIOMASS
const RESIDENCE_SECONDS := 10.0
const BIOMASS_YIELD := 0.7
const MAX_LEAF_FIXATION := 0.7
const LEAF_ATP_YIELD := 4.0
# Food and tissue retain more finite chemical energy per represented unit.
# Saved intracellular fuel is never topped up when the rules change.
const FOOD_FUEL := 18.0*ENERGY_DENSITY
const TISSUE_FUEL := 7.5*ENERGY_DENSITY
const LEAF_SOLAR_WORK := LEAF_BIOMASS*TISSUE_FUEL+LEAF_FOOD*FOOD_FUEL+LEAF_ATP_YIELD
const MIN_LEAF_LIGHT := 0.08 # Authored diffuse-light survival floor, with real carbon costs.
var model_version := 2
var batching:=false
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
var gas_credit:=0.0
var excretion_credit:=0.0
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
func material() -> float: return float(presentation_totals.get("material",amount("food")+amount("waste")+amount("carbon")))
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

func emit(species: String, quantity: float, at: Vector2, source: int=-1, compartment: int=-1, fuel: float=-1, _spread: float=0, nutrition: float=0) -> void:
	if quantity<=0 or species not in ACTIVE_SPECIES:return
	fuel=quantity*FOOD_FUEL if fuel<0 and species=="food" else maxf(0,fuel)
	if accelerator!=null:accelerator.command(1,quantity,at,0,-1,source,compartment,fuel,0,species,{19:nutrition});return
	var chosen: Dictionary={}
	var count:=0
	for packet in particles:
		if packet.species!=species or not packet.alive:continue
		count+=1
		if chosen.is_empty() or packet.p.distance_squared_to(at)<chosen.p.distance_squared_to(at):chosen=packet
	# Coalesce only the same compartment, or bounded overflow into an existing
	# carrier. This changes parcel resolution, never represented material/fuel.
	if not chosen.is_empty() and (count>=(MAX_VACUOLES if species in ["food","waste"] else MAX_GAS) or ((chosen.compartment==compartment or (compartment<0 and float(chosen.get("age",0))<1)) and chosen.p.distance_squared_to(at)<196)):
		chosen.amount+=quantity;chosen.fuel+=fuel
		if nutrition>0 or chosen.has("nutrition"):chosen.nutrition=float(chosen.get("nutrition",0))+quantity*nutrition
		if compartment<0 and float(chosen.get("age",0))>=1:chosen.age=1.0
	else:
		var parent: Dictionary={}
		for packet in particles:
			if packet.compartment==compartment and compartment>=0:parent=packet;break
		particles.append({"age":float(parent.get("age",0)),"id":next_packet,"species":species,"amount":quantity,"fuel":fuel,"p":at,"previous":at,"v":Vector2.ZERO,"angle":next_packet*2.399963,"source":source,"compartment":next_packet if compartment<0 else compartment,"alive":true})
		if nutrition>0:particles[-1].nutrition=quantity*nutrition
		next_packet+=1
	if not batching:refresh()
func _consume(packet: Dictionary, quantity: float) -> float:
	quantity=minf(quantity,packet.amount)
	var fuel: float=packet.fuel*quantity/maxf(.00000001,packet.amount)
	if packet.has("nutrition"):packet.nutrition*=1-quantity/maxf(.00000001,packet.amount)
	packet.amount-=quantity;packet.fuel-=fuel
	packet.alive=packet.amount>.0000001
	return fuel
func assign(species: String, quantity: float) -> void:
	if species not in ACTIVE_SPECIES:return
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
	if kind not in [0,1,5] or quantity<=0:return
	var cell=owner.get_ref()
	var local:=Vector2(wrapf(world_at.x-cell.position.x,-2048,2048),wrapf(world_at.y-cell.position.y,-1280,1280)).rotated(-cell.angle)
	local=local.normalized()*minf(local.length(),cell.support(local.angle()+cell.angle)*.78)
	# External profile carries true fuel up to quantity, then ATP allocation credit.
	var bonus := clampf(capacity/quantity-1,0,float(Catalog.data().ecology.nutrient_bonus_limit)) if kind==0 else 0.0
	emit({0:"food",1:"oxygen",5:"carbon"}[kind],quantity,local,-1,-1,minf(quantity,capacity)*FOOD_FUEL if kind==0 else 0,0,bonus)
func refresh() -> void:
	particles=particles.filter(func(packet):return packet.alive)
	totals.clear();vacuoles.clear()
	var carriers: Dictionary={}
	for packet in particles:
		totals[packet.species]=amount(packet.species)+packet.amount
		if packet.species in ["oxygen","carbon"]:
			vacuoles.append({"id":packet.id,"species":packet.species,"p":packet.p,"angle":packet.angle,"radius":1.4,"acid":0.0,"material":0.0,"contents":packet.amount,"age":float(packet.get("age",0))})
		if packet.species!="food":continue
		var v={"id":packet.compartment,"p":packet.p,"radius":carrier_radius(packet.amount),"acid":0.0,"material":0.0,"contents":packet.amount,"age":float(packet.get("age",0))}
		carriers[packet.compartment]=v;vacuoles.append(v)
	for packet in particles:
		if packet.species!="waste":continue
		if carriers.has(packet.compartment):
			var v: Dictionary=carriers[packet.compartment]
			v.contents+=packet.amount;v.acid=packet.amount/maxf(.0000001,v.contents);v.radius=carrier_radius(v.contents)
		else:
			var v={"id":packet.compartment,"p":packet.p,"radius":carrier_radius(packet.amount),"acid":1.0,"material":0.0,"contents":packet.amount,"age":float(packet.get("age",0))}
			carriers[packet.compartment]=v;vacuoles.append(v)
func _near_consume(species: String, quantity: float, at: Vector2, reach: float) -> float:
	var used:=0.0
	for packet in particles:
		if packet.species!=species or not packet.alive or packet.p.distance_squared_to(at)>reach*reach:continue
		var q:=minf(quantity-used,packet.amount)
		_consume(packet,q);used+=q
		if used>=quantity-.0000001:break
	return used

func carrier_radius(quantity: float) -> float:
	var cell=owner.get_ref()
	var density:=4.0 if cell.synergy()=="hunter" else 1.0
	return clampf(6+sqrt(maxf(0,quantity)/density)*.6,7,maxf(7,minf(14,cell.radius*.28)))

func digestion_rate(cell,dt: float=1.0) -> float:
	# Parasites promptly convert their actual intake, never build a raw-food reserve.
	if cell.synergy()=="parasite":return amount("food")/maxf(.000001,dt)
	if cell.synergy()=="grazer":return .2*cell.growth_scale()
	# Keep fuel in the vacuole instead of filling a quickly decaying ATP pool.
	var aerobic:=clampf(amount("oxygen")/maxf(.001,amount("food")),0,1)
	var yield_per_unit:=lerpf(FERMENT_ATP,AEROBIC_ATP*cell.mitochondrial_efficiency(),aerobic)
	var maintenance: float=cell.operating_budget().steady-cell.atp_decay_rate()
	var demand: float=maxf(0,maintenance+(100-cell.energy)/12.0)
	return minf(DIGESTION_RATE*cell.growth_scale(),demand/yield_per_unit)

func consume_oxygen(quantity: float, at: Vector2, reach: float) -> float:
	if accelerator!=null:return accelerator.command(8,quantity,at,reach,-1,-1,-1,0,0,"oxygen")
	var used:=_near_consume("oxygen",quantity,at,reach)
	refresh();return used

func advance(cell, dt: float, _external_osmolarity: float=.15) -> void:
	if dt<=0 or cell.dead or particle_count()==0:return
	var mitochondrial_gain: float=cell.mitochondrial_gain(dt)
	if accelerator!=null:
		var before: float=cell.processed-cell.fermented
		var energy_before: float=cell.energy
		accelerator.advance(dt,.15,mitochondrial_gain)
		cell.respiration_upkeep(maxf(0,cell.processed-cell.fermented-before),maxf(0,cell.energy-energy_before))
		return
	var aerobic_total:=0.0
	var produced_total:=0.0
	frame_dt=dt;tick+=1
	var budget: float=digestion_rate(cell,dt)*dt
	var original:=particles.duplicate();batching=true
	for packet in original:
		packet.previous=packet.p
		if packet.species!="food" or not packet.alive or budget<=0:continue
		var used: float=minf(budget,packet.amount);budget-=used
		var aerobic:=_near_consume("oxygen",used,packet.p,REACTION_REACH)
		var anaerobic:=used-aerobic
		var bonus := clampf(float(packet.get("nutrition",0))/maxf(.00000001,packet.amount),0,float(Catalog.data().ecology.nutrient_bonus_limit))
		var fuel:=_consume(packet,used)
		var fueled:=minf(used,fuel/TISSUE_FUEL)
		var tissue: float=fueled*(.7*aerobic+.3*anaerobic)/maxf(.00000001,used)
		var work: float=minf(maxf(0,fuel-tissue*TISSUE_FUEL),fueled*(AEROBIC_ATP*aerobic+FERMENT_ATP*anaerobic)/maxf(.00000001,used))
		# Nutrient quality retains its own allocation rule. Mitochondria recover
		# only otherwise dissipated fuel, never debit the meal's biomass output.
		var mitochondrial_extra: float=work*maxf(0,mitochondrial_gain-1)*aerobic/maxf(.00000001,used)
		if bonus>0:
			var extra := minf(work*bonus,maxf(0,fuel-work))
			var recovered_heat := maxf(0,fuel-tissue*TISSUE_FUEL-work)
			tissue-=maxf(0,extra-recovered_heat)/TISSUE_FUEL
			work+=extra
		work+=minf(mitochondrial_extra+work*(.15 if cell.synergy()=="grazer" else 0.0),maxf(0,fuel-tissue*TISSUE_FUEL-work))
		cell.biomass+=tissue;cell.gain_energy(work);cell.processed+=used
		cell.fermented+=anaerobic
		aerobic_total+=aerobic;produced_total+=work
		if anaerobic>0:cell.fermentation_activity=2
		heat+=maxf(0,fuel-tissue*TISSUE_FUEL-work)
		emit("carbon",used*.1,packet.p,-1,-1,0)
		emit("waste",used-tissue-used*.1,packet.p,packet.source,packet.compartment,0)
	cell.respiration_upkeep(aerobic_total,produced_total)
	batching=false;particles=particles.filter(func(packet):return packet.alive)
	var food_by_compartment: Dictionary={}
	for packet in particles:
		if packet.species=="food":food_by_compartment[packet.compartment]=packet
	for packet in particles:
		if packet.species=="waste" and food_by_compartment.has(packet.compartment):continue
		packet.previous=packet.p;packet.age=float(packet.get("age",0))+dt
		var gas: bool=packet.species in ["oxygen","carbon"]
		if packet.species=="waste" and packet.age>=RESIDENCE_SECONDS:
			packet.p=packet.p.move_toward(cell.local_point(cell.excretion_angle())*.88,dt*maxf(10,cell.radius*.4))
		else:
			if packet.v.length_squared()<.001:packet.v=Vector2.from_angle(packet.compartment*2.399963+.8)*maxf(6,cell.radius*.22)
			var steps:=clampi(ceili(dt/.05),1,64)
			for step in steps:
				var trial: Vector2=packet.p+packet.v*(dt/steps)
				var bounded:=constrain(cell,trial,1.4 if gas else carrier_radius(packet.amount))
				if trial.distance_squared_to(bounded)>.000001:packet.v=packet.v.bounce((trial-bounded).normalized())
				packet.p=bounded
	for packet in particles:
		if packet.species!="waste":continue
		var food: Dictionary=food_by_compartment.get(packet.compartment,{})
		if not food.is_empty():packet.p=food.p;packet.previous=food.previous;packet.v=food.v;packet.age=food.age
	refresh()

static func constrain(cell, at: Vector2, radius: float=7.0) -> Vector2:
	var limit: float=cell.local_point(cell.surface_parameter(at.angle())).length()-radius
	at=at.limit_length(maxf(1,limit))
	var center: Vector2=Vector2(-.12,-.10)*cell.radius
	var delta: Vector2=at-center
	if delta.length()<(cell.radius*.22+radius):at=center+delta.normalized()*(cell.radius*.22+radius) if delta.length()>.001 else center+Vector2.RIGHT*(cell.radius*.22+radius)
	return at.limit_length(maxf(1,limit))
func excrete(sim, cell, dt: float) -> void:
	gas_credit=minf(8*cell.growth_scale(),gas_credit+dt*6*cell.growth_scale())
	excretion_credit=minf(8*cell.growth_scale(),excretion_credit+dt*4*cell.growth_scale())
	# Small gases cross only at the actual membrane after physical transport.
	if accelerator!=null and amount("oxygen")+amount("carbon")>=.3 and gas_credit>=.3:
		accelerator.command(13,gas_credit)
		for packet in accelerator._unpack(accelerator.transfer):
			gas_credit=maxf(0,gas_credit-packet.amount);_expel_gas(sim,cell,packet)
	elif accelerator==null:
		var gas_budget: float=gas_credit
		for packet in particles:
			if packet.species not in ["oxygen","carbon"] or packet.amount<.3 or packet.p.length()<cell.local_point(cell.surface_parameter(packet.p.angle())).length()-10:continue
			var q:=minf(1.8,packet.amount)
			if gas_budget+.00000001<q:continue
			gas_budget-=q
			var released: Dictionary=packet.duplicate();released.amount=q
			_consume(packet,q);_expel_gas(sim,cell,released)
		gas_credit=maxf(0,gas_budget)
		refresh()
	if amount("waste")<=.0000001:return
	var outlet: Vector2=cell.local_point(cell.excretion_angle())*.88
	if accelerator!=null:
		# The compact receipt already says whether any waste-only vacuole has
		# reached the outlet. Avoid an empty render-thread transaction.
		if not vacuoles.any(func(v):return v.get("species","") not in ["oxygen","carbon"] and v.acid>=.99999999 and v.age>=RESIDENCE_SECONDS and v.p.distance_to(outlet)<=maxf(2,cell.radius*.08)):return
		accelerator.command(11,excretion_credit,outlet,maxf(2,cell.radius*.08))
		for packet in accelerator._unpack(accelerator.transfer):
			excretion_credit=maxf(0,excretion_credit-packet.amount);_expel(sim,cell,packet,packet.amount)
		return
	var budget: float=excretion_credit
	var food_by_compartment: Dictionary={}
	for food in particles:
		if food.species=="food":food_by_compartment[food.compartment]=true
	for packet in particles:
		if packet.species!="waste" or float(packet.get("age",0))<RESIDENCE_SECONDS or packet.p.distance_to(outlet)>maxf(2,cell.radius*.08):continue
		if food_by_compartment.has(packet.compartment):continue
		var used: float=minf(1.8,packet.amount)
		if budget+.00000001<used:continue
		budget-=used
		_consume(packet,used);_expel(sim,cell,packet,used)
	excretion_credit=maxf(0,budget)
	refresh()
func _expel(sim, cell, _packet: Dictionary, quantity: float) -> void:
	if quantity<=0:return
	var normal: Vector2=cell.local_normal(cell.excretion_angle()).rotated(cell.angle)
	sim.spawn_particle(2,cell.excretion_position()+normal*9,normal*12,quantity,cell.id)
	expelled+=quantity
func _expel_gas(sim,cell,packet: Dictionary) -> void:
	if packet.amount<=0:return
	var normal: Vector2=packet.p.normalized().rotated(cell.angle)
	var at: Vector2=cell.position+normal*(cell.support(normal.angle())+8)
	sim.spawn_particle(1 if packet.species=="oxygen" else 5,at,normal*12,packet.amount,cell.id)

func ensure_cpu() -> void:
	if accelerator!=null:accelerator.release()
func particle_count() -> int:return accelerator.live_count if accelerator!=null else int(presentation_totals.get("packets",particles.size()))
func particle_snapshots(presentation: bool=false) -> Array:return accelerator.snapshot(presentation) if accelerator!=null else particles
func clone_for(cell):
	var copy=get_script().new();copy.owner=weakref(cell)
	copy.particles=particle_snapshots().duplicate(true);copy.next_packet=next_packet;copy.tick=tick;copy.heat=heat;copy.expelled=expelled
	copy.gas_credit=gas_credit;copy.excretion_credit=excretion_credit
	for key in ["solar_work","light_flux","pending_time","coarse_due","simulated_time","fine_updates","coarse_updates"]:copy.set(key,get(key))
	copy.presentation_totals=presentation_totals.duplicate(true);copy.refresh()
	return copy
# Archived pathway configuration is deliberately inactive in this revision.
func inherit_configuration(_parent) -> void:pass
func partition(parent,fraction: float) -> float:
	# Rare birth transfer: detach resident ownership once, never copy inventory.
	parent.ensure_cpu();ensure_cpu();fraction=clampf(fraction,0,1)
	var moved:=0.0
	var compartments: Dictionary={}
	var child=owner.get_ref()
	batching=true
	for packet in parent.particles:
		if not packet.alive:continue
		var amount: float=packet.amount*fraction
		var nutrition: float=float(packet.get("nutrition",0))/maxf(.000000001,packet.amount)
		var fuel: float=parent._consume(packet,amount)
		if not compartments.has(packet.compartment):
			compartments[packet.compartment]=next_packet;next_packet+=1
		var first:=next_packet
		emit(packet.species,amount,constrain(child,packet.p*(1-fraction),1.4 if packet.species in ["oxygen","carbon"] else 7),packet.source,compartments[packet.compartment],fuel,0,nutrition)
		for transfer in particles:
			if transfer.id>=first:
				transfer.age=float(packet.get("age",0));transfer.v=packet.v;transfer.angle=packet.angle
		moved+=amount
	batching=false;parent.refresh();refresh()
	return moved
func anchor_photosynthesis(_cell,_organ: Dictionary) -> void:pass
func food_share(sim,cell) -> float:
	return 1.0 if sim.Investment.strategy(sim,cell)=="producer" or cell.synergy()=="producer" else .25

func photosynthesize(sim,cell,organ: Dictionary,dt: float) -> void:
	if cell.synergy()=="producer":dt*=1.15
	# Bound newly released parcels and render-thread work without losing time.
	organ["photo_elapsed"]=float(organ.get("photo_elapsed",0))+dt
	if organ.photo_elapsed<.25:return
	dt=organ.photo_elapsed;organ.photo_elapsed=0.0
	if dt<=0 or amount("carbon")<=.0000001:return
	var light: float=sim.light_at(cell.organ_position(organ))
	var response: float=maxf(MIN_LEAF_LIGHT,light*cell.Genes.factor(organ,"sun" if light>=.5 else "shade"))
	var budget: float=minf(MAX_LEAF_FIXATION,3.5*response)*organ.scale*organ.scale*organ.hp/organ.max_hp*dt
	var baseline_budget: float = budget/cell.Genes.output(organ)
	var extra_cost: float = .2*cell.Genes.inefficiency(organ)
	budget = baseline_budget+minf(budget-baseline_budget,cell.energy/extra_cost)
	var site: Vector2=cell.local_point(organ.a)*.72
	var share:=food_share(sim,cell)
	var used:=0.0
	if accelerator!=null:
		used=accelerator.command(10,budget,site,24,-1,-1,-1,0,0,"carbon",{22:share})

	else:
		batching=true
		used=_near_consume("carbon",budget,site,24)
		if used>0:
			emit("food",used*LEAF_FOOD*(1-share),site,organ.id,-1,used*LEAF_FOOD*(1-share)*FOOD_FUEL)
			emit("oxygen",used*2.5,site,organ.id,-1,0)
			cell.biomass+=used*LEAF_BIOMASS;solar_work+=used*LEAF_SOLAR_WORK;heat+=used*(4-LEAF_ATP_YIELD)
		batching=false;refresh()
	if used>0:
		var normal: Vector2=cell.organ_normal(organ).rotated(cell.angle)
		sim.spawn_particle(0,cell.organ_position(organ)+normal*12,normal*12,used*LEAF_FOOD*share,cell.id)
		cell.spend_energy(maxf(0,used-baseline_budget)*extra_cost,organ,"photosynthesis")
		cell.gain_energy(used*LEAF_ATP_YIELD,organ)
		cell.spend_work(dt*used/maxf(.00000001,budget),organ,"photosynthesis")
		cell.fixed_carbon+=used;cell.oxygen_produced+=used*2.5
		light_flux+=used/maxf(dt,.00000001)
		cell.consumed(organ,used);cell.emitted(organ)
		if cell==sim.player:sim.evolution.record("photo",used)
func configuration() -> Dictionary:return {"version":2,"model":"food-vacuoles"}
func load_configuration(_value: Dictionary) -> String:return "Pathway editing is retired; digestion is automatic."
