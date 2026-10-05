extends RefCounted
const Membrane = preload("res://scripts/membrane.gd")
const KINDS := ["propulsion", "protection", "offensive", "regenerative", "feeding", "sensing"]
const COST := [8.0, 10.0, 12.0, 10.0, 8.0, 6.0]
const WIDTH := [19.0, 34.0, 26.0, 27.0, 36.0, 20.0]
const SENSE_MODES := ["flee"]
const MODES := ["graze", "engulf", "parasite"]
var id := 0
var role := "grazer"
var previous_position := Vector2.ZERO
var previous_angle := 0.0
var target_id := -1
var target_memory := 0.0
var target_position := Vector2.ZERO
var target_mode := "graze"
var target_mouth := 0.0
var target_organ_id := -1
var facing := Vector2.RIGHT
var shape_acceleration := Vector2.ZERO
var resource_packets: Array = []
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
var biomass := 18.0
var substrate := 4.0
var oxygen := 16.0
var energy := 72.0
var health := 100.0
var radius := 47.0
var mass := 100.0
var inertia := 100000.0
var aspect := 1.0
var membrane = Membrane.new()
var organs: Array = []
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
var waste := 0.0
var processed := 0.0
var eaten := 0.0
var stolen := 0.0
var engulfed := 0
var activity := 1.0
var age := 0.0
var dead := false

func _init(identity: int = 0, at: Vector2 = Vector2.ZERO) -> void:
	id = identity
	position = at
	previous_position = at

func count(kind: String) -> int:
	var n = 0
	for organ in organs:
		if organ.kind == kind: n += 1
	return n

func has_mode(mode: String) -> bool:
	for organ in organs:
		if organ.kind == "feeding" and organ.mode == mode: return true
	return false

func organ_mass() -> float:
	var result = 0.0
	for organ in organs: result += organ.material
	return result

func organic_mass() -> float:
	return body + biomass + organ_mass() + substrate + waste

func update_geometry() -> void:
	# Effective volume is retained cytoplasm. Sphere radius projected into 2D;
	# usable membrane capacity is its simulated perimeter, not a claim of 3D packing.
	radius = 47.0 * pow(maxf(8, body + biomass) / 78.0, 1.0/3.0)
	mass = maxf(4, organic_mass()*0.45)
	inertia = (body + biomass + substrate + waste) * radius * radius * 0.5
	for organ in organs:
		var arm = local_point(organ.a)
		inertia += organ.material * arm.length_squared()
	inertia = maxf(inertia*0.22, 50)
	aspect = 1.6 # Broad-phase bound; shape is no longer an ellipse.

func local_point(a: float) -> Vector2:
	var phase = fposmod(a, TAU) / TAU * membrane.COUNT
	var i = int(phase)
	return membrane.points[i].lerp(membrane.points[(i+1) % membrane.COUNT], phase-i)

func surface_parameter(local_angle: float) -> float:
	# Ray intersection maps a screen/contact angle onto the deformed boundary.
	var ray := Vector2.from_angle(local_angle)
	for i in membrane.COUNT:
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

func organ_position(organ: Dictionary) -> Vector2:
	return position + (local_point(organ.a) + local_point(organ.a).normalized()*5*organ.scale).rotated(angle)

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
	return pow(maxf(1.0,(body+biomass)/78.0),2.0/3.0)

func gut_capacity() -> float:
	return 24.0*growth_scale()

func oxygen_capacity() -> float:
	return 30.0*growth_scale()

func energy_capacity() -> float:
	return 100.0*growth_scale()

static func organ_cost(kind: String, size: float = 1.0) -> float:
	var k := KINDS.find(kind)
	return COST[k]*size*size if k >= 0 else INF

static func organ_width(organ: Dictionary) -> float:
	return WIDTH[KINDS.find(organ.kind)]*organ.scale+4

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
	var cost := organ_cost(kind,size) if paid else 0.0
	var length := perimeter()*pow(maxf(8,body+biomass-cost)/maxf(8,body+biomass),1.0/3.0)
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

func add_organ(kind: String, a: float, mode: String = "graze", paid: bool = true, size: float = 1.0) -> bool:
	var k := KINDS.find(kind)
	if dead or k < 0 or not can_fit(kind,a,size,paid): return false
	if kind == "sensing":
		if mode == "graze": mode = "flee"
		if mode != "flee": return false
	elif not MODES.has(mode): return false
	var cost := organ_cost(kind,size)
	if paid and biomass < cost: return false
	var length := perimeter()*pow(maxf(8,body+biomass-(cost if paid else 0.0))/maxf(8,body+biomass),1.0/3.0)
	_make_room(a,WIDTH[k]*size+4,length)
	if paid: biomass -= cost
	var max_health := (70.0 if kind == "protection" else 25.0)*size*size
	organs.append({"id":next_organ_id,"kind":kind,"a":fposmod(a,TAU),"scale":size,"mode":mode,"hp":max_health,"max_hp":max_health,"material":cost,"target_id":-1,"progress":0.0,"coverage":0.0,"feeding":false,"link":Vector2.ZERO,"feedback":"","consume_flash":0.0,"consume_clock":0.0,"charge_flash":0.0,"consumed_total":0.0})
	next_organ_id += 1
	update_geometry()
	render_revision += 1
	return true

func pore_radius(organ: Dictionary) -> float:
	return 18.0*organ.scale

func pore_center(organ: Dictionary) -> Vector2:
	return organ_position(organ)+local_point(organ.a).normalized().rotated(angle)*pore_radius(organ)*0.65

func consumed(organ: Dictionary, amount: float) -> void:
	if amount <= 0: return
	organ.consumed_total += amount
	if organ.consume_clock <= 0:
		organ.consume_flash = 1.0
		organ.consume_clock = 0.28
	reaction_flash = 1.0

func spend_energy(amount: float, organ: Dictionary = {}) -> float:
	var spent := minf(energy,maxf(0,amount))
	energy -= spent
	if spent > 0: resource_effect("atp",organ.a if not organ.is_empty() else last_wound,spent,organ.get("id",-1))
	return spent

func resource_effect(kind: String, a: float, amount: float, organ_id: int = -1) -> void:
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
	if dead or index < 0 or index >= organs.size(): return -1.0
	var material: float = organs[index].material
	biomass += material * 0.5
	organs.remove_at(index)
	update_geometry()
	return material * 0.5

func drain(amount: float) -> float:
	var taken = minf(biomass, amount)
	biomass -= taken
	var remainder = minf(maxf(0,body-4), amount-taken)
	body -= remainder
	if body <= 4.0001: health = 0
	return taken + remainder

func damage(amount: float, world_angle: float) -> float:
	if dead or amount <= 0: return 0.0
	var released = 0.0
	var local_angle = surface_parameter(world_angle-angle)
	last_wound = local_angle
	var hit = -1
	var distance = INF
	for i in organs.size():
		var arc = absf(arc_gap(organs[i].a,local_angle))
		if arc < organ_width(organs[i])*0.6 and arc < distance:
			hit = i
			distance = arc
	if hit >= 0:
		var organ: Dictionary = organs[hit]
		var absorbed = minf(amount, organ.hp)
		var lost: float = organ.material * absorbed / organ.hp
		organ.material -= lost
		organ.hp -= absorbed
		released += lost
		amount -= absorbed
		if organ.hp <= 0: organs.remove_at(hit)
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
	var leaked = 0.0
	var repair = 1.0 + count("regenerative") * 2.0
	for hole in holes:
		var loss: float = drain(hole.size * 7.0 * dt)
		leaked += loss
		if loss > 0: leaks.append({"a":hole.a,"amount":loss})
		hole.size = maxf(0,hole.size-dt*1.1*repair)
	holes = holes.filter(func(h): return h.size > 0)
	if energy > 0:
		var healed = minf(100-health, minf(8.0*repair*dt, minf(biomass/0.05,energy/0.2)))
		health += healed
		# Repaired membrane incorporates mass into structure rather than deleting it.
		biomass -= healed*0.05
		body += healed*0.05
		spend_energy(healed*0.2)
		if healed > 0: resource_effect("repair",last_wound,healed*0.05)
		for organ in organs:
			var unit: float = organ_cost(organ.kind,organ.scale) / organ.max_hp
			var restore = minf(organ.max_hp-organ.hp,minf(dt*1.3*repair,minf(biomass/unit,energy/0.15)))
			organ.hp += restore
			organ.material += restore*unit
			biomass -= restore*unit
			spend_energy(restore*0.15,organ)
			if restore > 0: resource_effect("repair",organ.a,restore*unit,organ.id)
	return leaked

func punctured_at(world_angle: float) -> bool:
	var local_angle := surface_parameter(world_angle-angle)
	for hole in holes:
		if absf(wrapf(hole.a-local_angle,-PI,PI)) < 0.23: return true
	return false
