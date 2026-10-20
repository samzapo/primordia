extends RefCounted
const Chemistry = preload("res://scripts/cell_chemistry.gd")
const Surface = preload("res://scripts/surface_chemistry.gd")
var chemistry = Chemistry.new()
var combat_context: Dictionary={} # Shared authority-derived rules, excluded from saves.
func accepts_attack(source: int) -> bool:
	var rule: Dictionary=combat_context.get("sources",{}).get(source,{})
	if rule.get("no_damage",false):return false
	if rule.get("selective",false):
		return organs.any(func(organ):return organ.kind in ["toxin","poreforming","acidifying"] and organ.hp>0)
	return true
var raw_fuel: float:
	get: return chemistry.raw_fuel()
	set(value): chemistry.set_raw_fuel(value)
var surface_complexes: Array = []
const Genes = preload("res://scripts/mutations.gd")
const Membrane = preload("res://scripts/membrane.gd")
const KINDS := ["propulsion", "protection", "poreforming", "regenerative", "feeding", "sensing", "photosynthesis", "toxin", "neutralizing", "acidifying", "hunting", "cilia", "mitochondrion", "counterattack", "toxin_sac", "family_toward", "family_away"]
const COST := [8.0, 10.0, 12.0, 10.0, 8.0, 0.0, 12.0, 12.0, 10.0, 12.0, 0.0, 8.0, 10.0, 12.0, 10.0, 0.0, 0.0]
const WIDTH := [19.0, 34.0, 26.0, 27.0, 36.0, 20.0, 30.0, 26.0, 26.0, 26.0, 20.0, 24.0, 0.0, 24.0, 0.0, 20.0, 20.0]
const SENSE_MODES := ["flee"]
const MODES := ["graze"]
const BASAL_UPKEEP := 0.18
const ORGAN_UPKEEP := 0.35
const LEAF_UPKEEP := 0.04
const MITOCHONDRION_UPKEEP := 0.04
const MOTION_UPKEEP := 0.20
const PUMP_UPKEEP := 0.10
const CILIA_MOTION := 0.16
const CILIA_PUMP := 0.08
const CILIA_THRUST := 1800.0
const CILIA_REACH := 170.0
const CILIA_FLOW := 52.0
const LOW_POWER_ATP := 12.0
const POWER_RECOVERY_ATP := 18.0
const LOW_POWER_CAPACITY := 0.25
const SECRETION_COST := 0.10
const AEROBIC_ATP := 2.25
const FERMENT_ATP := 1.0
const STARVATION_GRACE := 300.0
const STARVATION_DAMAGE := 0.1
# In this 2D habitat, enclosed area is the represented cytoplasmic volume.
const TISSUE_AREA := Membrane.COUNT*0.5*sin(TAU/Membrane.COUNT)*47.0*47.0/78.0
const ATP_TURNOVER := 0.002
const ORAL_FLOW := 64.0
const ORAL_REACH := 170.0
var automatic_division:=true
var division_requested:=false # One paid birth at the next safe opportunity; never inherited.
var merge_after:=0.0
var behavior: Dictionary={} # Bounded physiology latches and current received escape direction.
var exploration := 0.25 # Legacy checkpoint fact; inert.
var response_cycle := 4.0
var drive_active := false
var id := 0
var lineage := -1
var generation := 0
var death_hint := "Membrane failed"
var rival_name := ""
var role := "grazer"
var previous_position := Vector2.ZERO
var previous_angle := 0.0
var energy_budget := preload("res://scripts/energy_budget.gd").new()
var target_id := -1
var target_lineage := -1
var target_memory := 0.0
var target_score := 0.0 # Unweighted salience, evaluated with current anatomy settings.
var target_sample_at := -INF
var target_expires_at := INF
var target_position := Vector2.ZERO
var target_mode := "graze"
var target_mouth := 0.0
var target_organ_id := -1
var facing := Vector2.RIGHT
var shape_acceleration := Vector2.ZERO
var resource_packets: Array = []
var resource_effects_enabled:=true
var resource_budget: Dictionary = {}
var next_organ_id := 0
var last_wound := 0.0
var feeding_feedback := ""
var render_revision := 0
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var angle := 0.0
var angular_velocity := 0.0
var body := 60.0
var ap := 0 # Legacy save compatibility only; gameplay uses biomass.
var automatic_budding:=true
var lifecycle_version:=1
var favorite:=false
var favorite_name:=""
var unattended_protected:=false
var investment_retry_at:=0.0 # Saved cell-local automatic buy/sell cooldown.
var biomass := 18.0
var substrate: float:
	get: return chemistry.amount("food")
	set(value): chemistry.assign("food",value)
var oxygen: float:
	get:return chemistry.amount("oxygen")
	set(value):chemistry.assign("oxygen",value)
var carbon: float:
	get:return chemistry.amount("carbon")
	set(value):chemistry.assign("carbon",value)
var energy := 72.0
var health := 100.0
var radius := 47.0
var mass := 100.0
var inertia := 100000.0
var aspect := 1.0
var membrane = Membrane.new()
var organs: Array = []
var lost_organs: Array = []
var brood_mass := 0.0
var reproduction_elapsed := 0.0
var reproduction_retry_at := 0.0
var brood_energy := 0.0
var holes: Array = []
var leaks: Array = []
var signals: Array = []
var target := Vector2.RIGHT
var threat := Vector2.ZERO
var state := "EXPLORING"
var sensed := false
var hurt_flash := 0.0
var reaction_flash := 0.0
var attack_clock := 0.0
var sense_clock := 0.0
var emission_clock := 0.0
var waste: float:
	get: return chemistry.amount("waste")
	set(value): chemistry.assign("waste",value)
var processed := 0.0
var eaten := 0.0
var foreign_intake := 0.0
var reserve_used := 0.0
var reserve_activity := 0.0
var starvation_seconds := 0.0
var fermented := 0.0
var fermentation_activity := 0.0
var acid_stress := 0.0
var fixed_carbon := 0.0
var oxygen_produced := 0.0
var activity := 1.0
var age := 0.0
var dead := false
# Unprocessed real time, never a growth/health multiplier.
var coarse_elapsed := 0.0
var coarse_due := 1.0
var coarse_handling := 0.0

func _init(identity: int = 0, at: Vector2 = Vector2.ZERO) -> void:
	coarse_due = 0.25+fposmod(identity*0.61803398875,0.75)
	id = identity
	membrane = Membrane.new(radius,maxi(0,identity))
	position = at
	previous_position = at
	chemistry.setup(self)

func count(kind: String) -> int:
	var n = 0
	for organ in organs:
		if organ.kind == kind: n += 1
	return n

const RECEPTORS:=["sensing","hunting","family_toward","family_away"]
static func receptor(kind: String) -> bool:return kind in RECEPTORS

func construction_price(kind: String="") -> int:
	# Count equipped ordinary organs, not past purchases or free receptors.
	if kind=="" or receptor(kind):return 0
	var count:=organs.filter(func(organ):return not receptor(organ.kind)).size()
	if count<2:return 0
	var a:=1;var b:=1
	for i in range(count-2):
		# Saturating integer arithmetic prevents astronomical quotes wrapping free.
		var next:=a+mini(b,922337203685477580-a)
		a=b;b=next
	return a*10

func construction_refund(organ: Dictionary) -> float:
	var current=organ_by_id(int(organ.get("id",-1)))
	return 0.0 if current.is_empty() else minf(float(current.material),float(current.get("paid_material",current.material)))*.5

func synergy() -> String:
	var attack=int(working("poreforming"))+int(working("toxin"))+int(working("counterattack"))
	if working("hunting") and working("propulsion") and attack>0 and count("photosynthesis")==0:return "hunter"
	if working("photosynthesis",2) and working("mitochondrion") and attack==0 and count("feeding")==0:return "producer"
	if working("feeding") and working("cilia") and count("photosynthesis")==0 and attack==0:return "grazer"
	return ""

func working(kind: String, minimum: int=1) -> bool:
	return organs.filter(func(organ):return organ.kind==kind and organ.hp>0).size()>=minimum


func has_mode(mode: String) -> bool:
	for organ in organs:
		if organ.kind == "feeding" and organ.mode == mode: return true
	return false

func organ_mass() -> float:
	var result = 0.0
	for organ in organs: result += organ.material+float(organ.get("stored_toxin",0))
	return result

func organic_mass() -> float:
	return body + biomass + organ_mass() + brood_mass + chemistry.material() + surface_material()

func surface_material() -> float:
	var amount := 0.0
	for complex in surface_complexes: amount += complex.material
	return amount

func accept_surface(kind: int, amount: float, world_angle: float, source: int = -1) -> bool:
	if kind in [Surface.TAG,Surface.SUBUNIT] and (not accepts_attack(source) or (source==id and synergy()=="hunter")):return false
	return Surface.bind(self,kind,amount,world_angle,source)

func update_geometry() -> void:
	# One retained tissue unit adds exactly TISSUE_AREA of represented volume.
	radius = tissue_radius(maxf(8,body+biomass+brood_mass+chemistry.reactor_mass+chemistry.amount("catalyst")))
	membrane.oral_angle = NAN
	for organ in organs:
		if organ.kind=="feeding": membrane.oral_angle = organ.a
	_sync_oral_link()
	membrane.cell_wall=synergy()=="producer"
	mass = maxf(4, organic_mass()*0.45)
	inertia = (body + biomass + substrate + waste + carbon + brood_mass) * radius * radius * 0.5
	for organ in organs:
		var arm = local_point(organ.a)
		inertia += organ.material * arm.length_squared()+float(organ.get("stored_toxin",0))*organ_local_position(organ).length_squared()
	inertia = maxf(inertia*0.22, 50)
	aspect = 1.6 # Broad-phase bound; shape is no longer an ellipse.

func local_point(a: float) -> Vector2:
	var phase = fposmod(a, TAU) / TAU * membrane.COUNT
	var i = int(phase)
	return membrane.points[i].lerp(membrane.points[(i+1) % membrane.COUNT], phase-i)

func local_normal(a: float) -> Vector2:
	# Smooth normals of the same ordered curve used by membrane artwork.
	var curve: PackedVector2Array = membrane.outline()
	var phase: float = fposmod(a,TAU)/TAU*curve.size()
	var i := int(phase)
	var tangent_a: Vector2 = curve[(i+1)%curve.size()]-curve[posmod(i-1,curve.size())]
	var tangent_b: Vector2 = curve[(i+2)%curve.size()]-curve[i]
	var tangent := tangent_a.lerp(tangent_b,phase-i)
	return Vector2(tangent.y,-tangent.x).normalized() if tangent.length_squared() > 0.000001 else local_point(a).normalized()

func organ_normal(organ: Dictionary) -> Vector2:
	return local_normal(organ.a)

var fast_support := true

func surface_parameter(local_angle: float) -> float:
	# Stabilized nodes stay in ordered polar sectors. The ray can intersect
	# only a neighboring edge; preserve global edge order at the wrapping seam.
	# An imported/test outline outside those sectors still gets a full search.
	var ray := Vector2.from_angle(local_angle)
	var guess := floori(fposmod(local_angle,TAU)/TAU*membrane.COUNT)
	var neighbors := range(membrane.COUNT) if not fast_support else [0,1,membrane.COUNT-1] if guess == 0 else [0,membrane.COUNT-2,membrane.COUNT-1] if guess == membrane.COUNT-1 else [guess-1,guess,guess+1]
	for pass_index in 2:
		for i in neighbors if pass_index == 0 else range(membrane.COUNT):
			var a: Vector2 = membrane.points[i]
			var edge: Vector2 = membrane.points[(i+1)%membrane.COUNT]-a
			var denominator := ray.cross(edge)
			if absf(denominator) < 0.00001: continue
			var along := a.cross(ray)/denominator
			var distance := a.cross(edge)/denominator
			if along >= 0 and along <= 1 and distance >= 0:
				return TAU*(i+along)/membrane.COUNT
	return fposmod(local_angle,TAU)

func arc_coordinate(a: float) -> float:
	membrane.refresh_arcs()
	var phase: float = fposmod(a,TAU)/TAU*membrane.COUNT
	var i := int(phase)
	return lerpf(membrane.arcs[i],membrane.arcs[i+1],phase-i)

func arc_gap(a: float, b: float) -> float:
	var length := perimeter()
	return wrapf(arc_coordinate(a)-arc_coordinate(b),-length*0.5,length*0.5)

static func internal_organ(kind: String) -> bool:
	return kind in ["mitochondrion","toxin_sac"]

func organ_local_position(organ: Dictionary) -> Vector2:
	if internal_organ(organ.kind):return local_point(organ.a)*.55
	return local_point(organ.a)+organ_normal(organ)*5*organ.scale

func organ_position(organ: Dictionary) -> Vector2:
	return position+organ_local_position(organ).rotated(angle)

func update_power_state() -> void:
	if energy<LOW_POWER_ATP:behavior["low_power"]=true
	elif energy>=POWER_RECOVERY_ATP:behavior.erase("low_power")

func work_capacity(required: float=0.0) -> float:
	# Read-only, including when used by presentation or coarse intake requests.
	var threshold: float=POWER_RECOVERY_ATP if behavior.get("low_power",false) else LOW_POWER_ATP
	return LOW_POWER_CAPACITY if energy+0.0000001<maxf(threshold,required) else 1.0

func mitochondrial_efficiency() -> float:
	# Read-only capacity: each healthy normal-sized organ adds50%, capped5x.
	var strength:=0.0
	for organ in organs:
		if organ.kind=="mitochondrion" and organ.hp>0:
			strength+=organ.scale*organ.scale*organ.hp/organ.max_hp
	return 1+minf(4,strength*.5)

func mitochondrial_gain(_dt: float) -> float:
	if chemistry.amount("food")<=0 or chemistry.amount("oxygen")<=0:return 1.0
	return mitochondrial_efficiency()

func excretion_angle() -> float:
	return (membrane.oral_angle if is_finite(membrane.oral_angle) else 0.0)+PI*0.85

func excretion_position() -> Vector2:
	var a := excretion_angle()
	return position+(local_point(a)+local_normal(a)*12).rotated(angle)

func support(world_angle: float) -> float:
	return local_point(surface_parameter(world_angle-angle)).length()

func extent() -> float:
	return membrane.maximum_radius*1.05

func visible_support(local_angle: float) -> float:
	var outline: PackedVector2Array = membrane.outline()
	var ray := Vector2.from_angle(local_angle)
	# Boundary nodes stay within their ordered angular sectors. Only the three
	# neighboring spline segments can intersect this ray (12 edges, not 112).
	var guess := floori(fposmod(local_angle,TAU)/TAU*membrane.COUNT)*4
	for phase in range(guess-4,guess+8):
		var i := posmod(phase,outline.size())
		var point: Vector2 = outline[i]
		var edge: Vector2 = outline[(i+1)%outline.size()]-point
		var denominator := ray.cross(edge)
		if absf(denominator) < 0.000001: continue
		var t := point.cross(ray)/denominator
		var distance := point.cross(edge)/denominator
		if t >= -0.00001 and t <= 1.00001 and distance >= 0: return distance
	return support(local_angle+angle)

func perimeter() -> float:
	membrane.refresh_arcs()
	return membrane.arcs[membrane.COUNT]

func growth_scale() -> float:
	return pow(maxf(1.0,(body+biomass+brood_mass)/78.0),2.0/3.0)

func gut_capacity() -> float:
	return maxf(0,24.0*growth_scale()*(1.25 if synergy()=="grazer" else 1.0)-chemistry.storage_used())

func oxygen_capacity() -> float:
	return 14.0*growth_scale()

static func tissue_radius(amount: float) -> float:
	return 47.0*sqrt(maxf(0,amount)/78.0)

static func inherent(organ: Dictionary) -> bool:
	return false # All equipped organelles, including oral grooves, are optional.

func energy_reference() -> float:
	# A concentration scale for turnover and drawing, never a storage ceiling.
	return 100.0*growth_scale()

func atp_decay_rate() -> float:
	return ATP_TURNOVER*energy*energy/energy_reference()

func decay_energy(dt: float) -> void:
	var before := energy
	energy=energy/(1+ATP_TURNOVER*energy/energy_reference()*maxf(0,dt))
	var spent := before-energy
	energy_budget.record(age,0,0,spent,-1,"turnover")

static func organ_cost(kind: String, size: float = 1.0) -> float:
	var k := KINDS.find(kind)
	return COST[k]*size*size if k >= 0 else INF

static func organ_width(organ: Dictionary) -> float:
	return 0.0 if internal_organ(organ.kind) else WIDTH[KINDS.find(organ.kind)]*organ.scale+4

func organ_by_id(identity: int) -> Dictionary:
	for organ in organs:
		if organ.id == identity: return organ
	return {}

func occupied() -> float:
	var total := 0.0
	for organ in organs: total += organ_width(organ)
	return total

func can_fit(kind: String, a: float, size: float = 1.0, paid: bool = true) -> bool:
	var k := KINDS.find(kind)
	if k < 0 or not is_finite(a) or not is_finite(size) or size < 0.5: return false
	var cost: float=construction_price(kind) if paid else 0.0
	var length := perimeter()*pow(maxf(8,body+biomass+brood_mass-cost)/maxf(8,body+biomass+brood_mass),0.5)
	if internal_organ(kind):return count(kind)<maxi(1,floori(growth_scale()*3)) and occupied()<=length
	return occupied()+WIDTH[k]*size+4 <= length

func parameter_at_arc(distance: float) -> float:
	membrane.refresh_arcs()
	distance = fposmod(distance,perimeter())
	for i in membrane.COUNT:
		if distance <= membrane.arcs[i+1]:
			return TAU*(i+(distance-membrane.arcs[i])/maxf(0.001,membrane.arcs[i+1]-membrane.arcs[i]))/membrane.COUNT
	return 0.0

func _make_room(anchor: float, width: float, length: float) -> void:
	# Cut the circular arc at the new fixed attachment. Project existing centers
	# onto non-overlapping intervals in both directions, retaining their order.
	var original_length := perimeter()
	var origin := arc_coordinate(anchor)
	var items: Array = []
	for organ in organs:
		if internal_organ(organ.kind):continue
		items.append({"organ":organ,"x":fposmod(arc_coordinate(organ.a)-origin,original_length)*length/original_length,"half":organ_width(organ)*0.5})
	items.sort_custom(func(a,b): return a.x < b.x)
	var end := width*0.5
	for item in items:
		item.x = maxf(item.x,end+item.half)
		end = item.x+item.half
	end = length-width*0.5
	for i in range(items.size()-1,-1,-1):
		var item: Dictionary = items[i]
		item.x = minf(item.x,end-item.half)
		end = item.x-item.half
	for item in items: item.organ.a = parameter_at_arc(origin+item.x*original_length/length)

static func steering_strength(organ: Dictionary) -> float:
	# Legacy percentages remain saved verbatim; all working senses are automatic.
	return 1.0 if organ.get("kind","") in ["feeding","hunting","photosynthesis","sensing","counterattack","family_toward","family_away"] else 0.0

func set_steering_strength(_identity: int, _strength: float) -> bool:return false
func set_exploration(_strength: float) -> bool:return false
func set_response_cycle(_seconds: float) -> bool:return false

func add_organ(kind: String, a: float, mode: String = "graze", paid: bool = true, size: float = 1.0) -> bool:
	var k := KINDS.find(kind)
	if dead or k < 0 or not can_fit(kind,a,size,paid): return false
	if receptor(kind):
		var required: String={"sensing":"flee","hunting":"hunt","family_toward":"kin_toward","family_away":"kin_away"}[kind]
		if mode == "graze": mode = required
		if mode != required: return false
	elif not MODES.has(mode): return false
	if kind == "feeding" and count("feeding") > 0: return false
	var cost: float=construction_price(kind) if paid else 0.0
	var tissue: float=maxf(organ_cost(kind,size),cost)
	if paid and biomass < cost: return false
	var length := perimeter()*pow(maxf(8,body+biomass+brood_mass-(cost if paid else 0.0))/maxf(8,body+biomass+brood_mass),0.5)
	if not internal_organ(kind):_make_room(a,WIDTH[k]*size+4,length)
	if paid: biomass -= cost
	var max_health := (70.0 if kind == "protection" else 25.0)*size*size
	organs.append({"id":next_organ_id,"kind":kind,"a":fposmod(a,TAU),"scale":size,"mode":mode,"hp":max_health,"max_hp":max_health,"material":tissue,"max_material":tissue,"mutation":"","steering":1.0,"growth_spent":size*size,"ap_spent":maxi(1,ceili(size*size-0.000001)),"target_id":-1,"progress":0.0,"coverage":0.0,"feeding":false,"link":Vector2.ZERO,"feedback":"","consume_flash":0.0,"consume_clock":0.0,"charge_flash":0.0,"consumed_total":0.0,"blocked":0.0})
	if kind=="toxin_sac":organs[-1]["stored_toxin"]=0.0
	organs[-1]["paid_material"]=cost if paid else 0.0
	if kind == "photosynthesis" and count("photosynthesis") == 1: chemistry.anchor_photosynthesis(self,organs[-1])
	next_organ_id += 1
	update_geometry()
	render_revision += 1
	return true

func sensory_output(_organ: Dictionary,_paid: bool=false) -> float:
	return 1.0 # All receptors use their ordinary reach; no output/ATP multiplier.

func pore_radius(organ: Dictionary) -> float:
	return 18.0*organ.scale*Genes.factor(organ,"intake")

func pore_center(organ: Dictionary) -> Vector2:
	return organ_position(organ)+organ_normal(organ).rotated(angle)*pore_radius(organ)*0.65

func emitted(organ: Dictionary) -> void:
	organ["emission_serial"]=int(organ.get("emission_serial",0))+1
	organ["emission_age"]=age

func consumed(organ: Dictionary, amount: float) -> void:
	if amount <= 0: return
	organ.consumed_total += amount
	if organ.consume_clock <= 0:
		organ.consume_flash = 1.0
		organ.consume_clock = 0.28
	reaction_flash = 1.0

func spend_energy(amount: float, organ: Dictionary = {}, category: String = "upkeep", shares: Dictionary = {}) -> float:
	var spent := minf(energy,maxf(0,amount))
	energy-=spent
	energy_budget.record(age,0,0,maxf(0,spent),organ.get("id",-1),category,shares)
	if spent > 0: resource_effect("atp",organ.a if not organ.is_empty() else last_wound,spent,organ.get("id",-1))
	return spent

func available_energy(_organ: Dictionary = {}) -> float:
	return energy

func spend_energy_at(amount: float, _at: Vector2, _reach: float, category: String) -> float:
	var spent := minf(energy,maxf(0,amount))
	energy-=spent
	energy_budget.record(age,0,0,spent,-1,category)
	return spent

func gain_energy(amount: float, organ: Dictionary = {}) -> void:
	energy+=maxf(0,amount)
	report_energy_gain(maxf(0,amount),organ)

func report_energy_gain(amount: float, organ: Dictionary = {}) -> void:
	energy_budget.record(age,maxf(0,amount),maxf(0,amount),0,organ.get("id",-1),"production")
	if amount > 0: resource_effect("gain",organ.get("a",0.0),amount,organ.get("id",-1))

func receive_particle(kind: int, amount: float, capacity: float, at: Vector2) -> void:
	chemistry.receive(kind,amount,capacity,at)

static func metabolic_upkeep(organ: Dictionary) -> float:
	if float(organ.get("hp",1))<=0:return 0.0
	var base: float=0.0 if organ.kind=="feeding" else LEAF_UPKEEP if organ.kind=="photosynthesis" else MITOCHONDRION_UPKEEP if organ.kind=="mitochondrion" else ORGAN_UPKEEP
	return (base+Genes.factor(organ,"upkeep",0.0))*float(organ.get("scale",1.0))*float(organ.get("scale",1.0))

static func organ_upkeep(organ: Dictionary) -> float:
	var area: float = float(organ.get("scale",1.0))*float(organ.get("scale",1.0))
	var rate := metabolic_upkeep(organ)
	if organ.kind == "propulsion": rate += MOTION_UPKEEP*area*Genes.factor(organ,"motion_cost")
	elif organ.kind == "feeding": rate += PUMP_UPKEEP*area*Genes.output_cost(organ)
	elif organ.kind == "cilia": rate += (CILIA_MOTION+CILIA_PUMP)*area*Genes.output_cost(organ)
	if organ.kind=="toxin_sac" and float(organ.get("stored_toxin",0))<preload("res://scripts/toxin_sac.gd").capacity(organ):
		var rule: Dictionary=preload("res://scripts/chemistry_catalog.gd").data().combat.toxin_sac
		rate+=float(rule.fill_rate)*float(rule.atp_per_unit)*area
	if organ.kind in ["feeding","sensing","hunting","photosynthesis","family_toward","family_away"]:
		rate += .1*(Genes.output(organ)-1)*Genes.inefficiency(organ)*area
	if organ.kind in ["feeding","neutralizing","acidifying","regenerative"]:
		rate += (0.35 if organ.kind == "feeding" else 2.0)*area*Genes.factor(organ,"secretion")*SECRETION_COST*Genes.factor(organ,"secretion_cost")
	return rate

func resource_effect(kind: String, a: float, amount: float, organ_id: int = -1) -> void:
	if not resource_effects_enabled:return
	var key := kind+str(organ_id)
	resource_budget[key] = resource_budget.get(key,0.0)+amount
	if resource_budget[key] < 0.12: return
	var count := mini(3,int(resource_budget[key]/0.12))
	resource_budget[key] = fmod(resource_budget[key],0.12)
	for i in count:
		if resource_packets.size() >= 64: break
		resource_packets.append({"kind":kind,"p":Vector2(-0.15,-0.15)*radius,"a":a,"organ_id":organ_id,"life":2.0,"delay":i*0.06})

func animate_resources(dt: float) -> void:
	for organ in organs:
		organ.consume_flash = maxf(0,organ.consume_flash-dt*4)
		organ.consume_clock = maxf(0,organ.consume_clock-dt)
		organ.charge_flash = maxf(0,organ.charge_flash-dt*4)
	for packet in resource_packets:
		packet.delay -= dt
		if packet.delay > 0: continue
		var organ := organ_by_id(packet.organ_id)
		var a: float = packet.a if organ.is_empty() else organ.a
		var destination := local_point(a)*0.96
		packet.p = packet.p.move_toward(destination,(110+radius*2)*dt)
		packet.life -= dt
		if packet.p.distance_to(destination) < 3:
			if not organ.is_empty(): organ.charge_flash = 1.0
			packet.life = 0
	resource_packets = resource_packets.filter(func(packet): return packet.life > 0)

func recycle(index: int) -> float:
	if dead or unattended_protected or index < 0 or index >= organs.size() or inherent(organs[index]): return -1.0
	var material: float = organs[index].material+float(organs[index].get("stored_toxin",0))
	var refund: float=construction_refund(organs[index])+float(organs[index].get("stored_toxin",0))*.5
	biomass += refund
	organs.remove_at(index)
	update_geometry()
	render_revision += 1
	return material-refund

func drain(amount: float) -> float:
	var taken = minf(biomass, amount)
	biomass -= taken
	var remainder = 0.0 if unattended_protected else minf(maxf(0,body-4), amount-taken)
	body -= remainder
	if body <= 4.0001 and not unattended_protected: health = 0
	return taken + remainder

func damage(amount: float, world_angle: float, source: int=-1) -> float:
	if dead or unattended_protected or amount <= 0 or not accepts_attack(source): return 0.0
	var released = 0.0
	var local_angle = surface_parameter(world_angle-angle)
	last_wound = local_angle
	behavior["wounded_until"]=age+3.0
	behavior["wound_direction"]=Vector2.from_angle(world_angle)
	var hit = -1
	var distance = INF
	for i in organs.size():
		if organs[i].kind=="feeding" or internal_organ(organs[i].kind): continue # A groove is exposed membrane, not armor.
		var arc = absf(arc_gap(organs[i].a,local_angle))
		if arc < organ_width(organs[i])*0.6 and arc < distance:
			hit = i
			distance = arc
	if hit >= 0:
		var organ: Dictionary = organs[hit]
		var output: float = Genes.output(organ) if organ.kind == "protection" else 1.0
		var absorbed: float = minf(amount,organ.hp*output)
		var demand: float = (absorbed-absorbed/output)*.2*Genes.inefficiency(organ)
		if demand > energy:
			output = 1.0; absorbed = minf(amount,organ.hp); demand = 0.0
		if demand > 0: spend_energy(demand,organ,"protection")
		var tissue_damage: float = absorbed/output
		var lost: float = organ.material * tissue_damage / organ.hp
		organ["paid_material"]=float(organ.get("paid_material",organ.material))*maxf(0,1-tissue_damage/organ.hp)
		organ.material -= lost
		organ.hp -= tissue_damage
		released += lost
		amount -= absorbed
		if organ.hp <= 0:
			released+=float(organ.get("stored_toxin",0))
			if organ.has("stored_toxin"):organ.stored_toxin=0.0
			lost_organs.append(organ.duplicate(true))
			organs.remove_at(hit)
	if amount > 0:
		health = maxf(0,health-amount)
		var merged := false
		for hole in holes:
			if absf(wrapf(hole.a-local_angle,-PI,PI)) < 0.2:
				hole.size = minf(1.2,hole.size+amount/16.0)
				merged = true
				break
		if not merged: holes.append({"a":local_angle,"size":minf(1.2,amount/16.0)})
	hurt_flash = 1.0
	return released

func heal(dt: float) -> float:
	leaks.clear()
	if health <= 0 or dead: return 0.0
	update_power_state()
	var capacity: float=work_capacity()
	var leaked = 0.0
	var repair := 1.0
	var repair_cost := 1.0
	for organ in organs:
		if organ.kind == "regenerative" and organ.hp>0:
			repair += 2.0*organ.scale*organ.scale*Genes.factor(organ,"repair")
			repair_cost = maxf(repair_cost,Genes.factor(organ,"repair_cost"))
	for hole in holes:
		if hole.get("stress",false):continue
		var loss: float = drain(hole.size * 7.0 * dt)
		leaked += loss
		if loss > 0: leaks.append({"a":hole.a,"amount":loss})
		hole.size = maxf(0,hole.size-dt*1.1*(1+(repair-1)*capacity))
	holes = holes.filter(func(h): return h.size > 0)
	if energy > 0 or repair>1:
		var healed = minf(100-health,minf(8.0*repair*dt*capacity,biomass/0.05))
		health += healed
		# Repaired membrane incorporates mass into structure rather than deleting it.
		biomass -= healed*0.05
		body += healed*0.05
		spend_energy(healed*0.2*repair_cost,{},"repair")
		if healed > 0: resource_effect("repair",last_wound,healed*0.05)
		for organ in organs:
			if inherent(organ): continue
			var unit: float = organ.get("max_material",organ_cost(organ.kind,organ.scale)) / organ.max_hp
			# Free receptors have zero represented construction material. Limit
			# their repair by time and ATP, never by the undefined ratio 0/0.
			var restore = minf(organ.max_hp-organ.hp,dt*1.3*repair*capacity)
			if unit>0: restore=minf(restore,biomass/unit)
			organ.hp += restore
			organ.material += restore*unit
			organ["paid_material"]=float(organ.get("paid_material",0))+restore*unit
			biomass -= restore*unit
			spend_energy(restore*0.15*repair_cost,organ,"repair")
			if restore > 0: resource_effect("repair",organ.a,restore*unit,organ.id)
	return leaked

func punctured_at(world_angle: float) -> bool:
	var local_angle := surface_parameter(world_angle-angle)
	for hole in holes:
		if absf(wrapf(hole.a-local_angle,-PI,PI)) < 0.23: return true
	return false

# Snapshot only script-owned state. Packed arrays use copy-on-write; dictionaries
# and arrays are deep-copied, while native kernels remain shared stateless helpers.
static func clone_state(source):
	var copy = source.get_script().new()
	for property in source.get_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var key: String = property.name
		if key in ["raw_fuel","substrate","waste","oxygen","carbon"]:continue
		var value = source.get(key)
		if key in ["membrane","skeleton"]: value = clone_state(value)
		elif key == "chemistry": value = value.clone_for(copy)
		elif value is Array or value is Dictionary: value = value.duplicate(true)
		elif typeof(value)>=TYPE_PACKED_BYTE_ARRAY and typeof(value)<=TYPE_PACKED_VECTOR4_ARRAY:value=value.duplicate()
		copy.set(key,value)
	return copy

func move_organ(_identity: int,_a: float) -> bool:
	return false # Position is chosen at construction; installed anatomy stays put.

func resize_quote(identity: int, size: float) -> Dictionary:
	var organ := organ_by_id(identity)
	if organ.is_empty() or inherent(organ) or not is_finite(size) or size < 0.5: return {}
	var ratio: float = size*size/(organ.scale*organ.scale)
	var growth: float = organ.get("growth_spent",organ.scale*organ.scale)+maxf(0,size*size-organ.scale*organ.scale)
	var paid: int = organ.get("ap_spent",maxi(1,ceili(organ.scale*organ.scale-0.000001)))
	return {"ratio":ratio,"growth":growth,"ap":maxi(0,ceili(growth-0.000001)-paid),"material":organ.material*(ratio-1.0)}

func resize_organ(identity: int, size: float) -> Dictionary:
	var organ := organ_by_id(identity)
	var quote := resize_quote(identity,size)
	if quote.is_empty(): return {}
	var cost: float = maxf(0,quote.material)
	var available := perimeter()*pow(maxf(8,body+biomass+brood_mass-cost)/maxf(8,body+biomass+brood_mass),0.5)
	if biomass < cost or occupied()-organ_width(organ)+WIDTH[KINDS.find(organ.kind)]*size+4 > available: return {}
	biomass -= cost
	var debris: float = maxf(0,-quote.material)*0.5
	biomass += debris
	organ.material *= quote.ratio
	organ.max_material *= quote.ratio
	organ.hp *= quote.ratio
	organ.max_hp *= quote.ratio
	organ.scale = size
	organ.growth_spent = quote.growth
	organ.ap_spent += quote.ap
	organs.erase(organ)
	_make_room(organ.a,organ_width(organ),available)
	organs.append(organ)
	update_geometry()
	render_revision += 1
	quote.debris = debris
	return quote

func specialize(identity: int, gene: String) -> bool:
	var organ := organ_by_id(identity)
	if organ.is_empty() or inherent(organ) or not Genes.DATA.has(gene) or Genes.DATA[gene].kind != organ.kind: return false
	var current: String = organ.get("mutation","")
	if current == gene: return false
	if current != "" and not (organ.kind == "photosynthesis" and current in Genes.LIGHT_ADAPTATIONS and gene in Genes.LIGHT_ADAPTATIONS): return false
	var cost := Genes.price(organ)
	if biomass < cost: return false
	var health: float = organ.hp/organ.max_hp
	biomass -= cost
	organ.mutation = gene
	if organ.kind=="photosynthesis":
		signals=signals.filter(func(packet):return packet.organ_id!=identity)
		if target_organ_id==identity:target_memory=0
		sense_clock=0 # The next ordinary sensory update reads the new preference.
	organ.max_material += cost
	# Added tissue joins a damaged organ at its current health; remaining tissue
	# waits as cell biomass for repair. No material disappears into a health bar.
	organ.material += cost*health
	organ["paid_material"]=float(organ.get("paid_material",0))+cost*health
	biomass += cost*(1-health)
	organ.max_hp *= Genes.factor(organ,"health")
	organ.hp = organ.max_hp*health
	update_geometry()
	render_revision += 1
	return true

func restore_organ(identity: int, paid: bool = true) -> bool:
	for record in lost_organs:
		if record.id != identity: continue
		var cost: float=construction_price(record.kind) if paid else 0.0
		var available := perimeter()*pow(maxf(8,body+biomass+brood_mass-(cost if paid else 0.0))/maxf(8,body+biomass+brood_mass),0.5)
		if (paid and biomass < cost) or occupied()+organ_width(record) > available: return false
		var organ: Dictionary = record.duplicate(true)
		_make_room(organ.a,organ_width(organ),available)
		if paid: biomass -= cost
		organ.material = maxf(record.max_material,cost)
		organ.max_material=organ.material
		organ["paid_material"]=cost
		if organ.has("stored_toxin"):organ.stored_toxin=0.0
		organ.hp = organ.max_hp
		organ.id = next_organ_id
		next_organ_id += 1
		organ.blocked = 0
		organs.append(organ)
		lost_organs.erase(record)
		update_geometry()
		render_revision += 1
		return true
	return false


func fluid_drag() -> float:
	# Stokes-inspired radius scaling. Baseline 47-unit cell retains total drag 90.
	return 90.0*radius/47.0

func operating_budget() -> Dictionary:
	var steady := BASAL_UPKEEP*growth_scale()+atp_decay_rate()
	for organ in organs: steady += organ_upkeep(organ)
	var income := minf(substrate,oxygen)*AEROBIC_ATP+maxf(0,substrate-oxygen)*FERMENT_ATP
	return {"steady":steady,"fuel":income}

func lineage_id() -> int:
	return id if lineage < 0 else lineage

func _sync_oral_link() -> void:
	var links=membrane.skeleton.links
	if not is_finite(membrane.oral_angle):
		for link in links.duplicate():
			if link.get("oral",false):membrane.skeleton.remove_group(link.group)
		return
	for link in links:
		if link.get("oral",false):
			link.a={"kind":"membrane","a":membrane.oral_angle}
			if link.b.kind!="center":
				link.length=radius;link.radius=radius;link.lambda=0.0
			link.b={"kind":"center"}
			link.tension=1.0
			return
	var group=membrane.skeleton.connect_points({"kind":"membrane","a":membrane.oral_angle},{"kind":"center"},1.0,membrane,radius)
	for link in membrane.skeleton.links:
		if link.group==group:link["oral"]=true
