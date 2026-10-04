extends RefCounted
const Membrane = preload("res://scripts/membrane.gd")
const KINDS := ["propulsion", "protection", "offensive", "regenerative", "feeding", "sensing"]
const COST := [8.0, 10.0, 12.0, 10.0, 8.0, 6.0]
const WIDTH := [19.0, 34.0, 26.0, 27.0, 30.0, 20.0]
const MODES := ["graze", "engulf", "parasite"]
var id := 0
var role := "grazer"
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
	mass = maxf(8, organic_mass())
	inertia = (body + biomass + substrate + waste) * radius * radius * 0.5
	var bias = Vector2.ZERO
	for organ in organs:
		var arm = local_point(organ.a)
		inertia += organ.material * arm.length_squared()
		bias += Vector2.from_angle(organ.a * 2) * organ.material
	inertia = maxf(inertia, 100)
	aspect = 1.08 + minf(0.18, bias.length() / maxf(1, organ_mass()) * 0.18)

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
	var phase: float = fposmod(a,TAU)/TAU*membrane.COUNT
	var total := 0.0
	for i in int(phase): total += membrane.points[i].distance_to(membrane.points[(i+1)%membrane.COUNT])
	var i := int(phase)
	return total+membrane.points[i].distance_to(membrane.points[(i+1)%membrane.COUNT])*(phase-i)

func arc_gap(a: float, b: float) -> float:
	var length := perimeter()
	return wrapf(arc_coordinate(a)-arc_coordinate(b),-length*0.5,length*0.5)

func organ_position(organ: Dictionary) -> Vector2:
	return position + (local_point(organ.a) + Vector2.from_angle(organ.a)*5).rotated(angle)

func support(world_angle: float) -> float:
	return local_point(surface_parameter(world_angle-angle)).length()

func perimeter() -> float:
	var length = 0.0
	for i in membrane.COUNT: length += membrane.points[i].distance_to(membrane.points[(i+1)%membrane.COUNT])
	return length

func occupied() -> float:
	var total = 0.0
	for organ in organs: total += WIDTH[KINDS.find(organ.kind)] + 4
	return total

func can_fit(kind: String, a: float) -> bool:
	var k = KINDS.find(kind)
	if k < 0 or not is_finite(a): return false
	var length = perimeter() * pow(maxf(8,body+biomass-COST[k])/maxf(8,body+biomass),1.0/3.0)
	if occupied() + WIDTH[k] + 4 > length: return false
	for organ in organs:
		var gap = absf(arc_gap(a,organ.a)) * length/perimeter()
		if gap < (WIDTH[k]+WIDTH[KINDS.find(organ.kind)])*0.5+4: return false
	return true

func add_organ(kind: String, a: float, mode: String = "graze", paid: bool = true) -> bool:
	var k = KINDS.find(kind)
	if dead or k < 0 or not MODES.has(mode) or not can_fit(kind,a): return false
	if paid and biomass < COST[k]: return false
	if paid: biomass -= COST[k]
	var max_health = 70.0 if kind == "protection" else 25.0
	organs.append({"kind":kind, "a":fposmod(a,TAU), "mode":mode, "hp":max_health, "max_hp":max_health, "material":COST[k]})
	update_geometry()
	return true

func recycle(index: int) -> float:
	if dead or index < 0 or index >= organs.size(): return -1.0
	var material: float = organs[index].material
	biomass += material * 0.5
	organs.remove_at(index)
	update_geometry()
	return material * 0.5

func drift_organs(dt: float, local_flow: Vector2) -> void:
	for organ in organs:
		var tangent = Vector2.from_angle(organ.a).orthogonal()
		organ.a = fposmod(organ.a + tangent.dot(local_flow)*dt*0.0007, TAU)
	# Arc-length packing, symmetric displacement. There is no count limit.
	for iteration in 5:
		for i in organs.size():
			for j in range(i+1, organs.size()):
				var gap: float = arc_gap(organs[j].a,organs[i].a)
				var need: float = (WIDTH[KINDS.find(organs[i].kind)]+WIDTH[KINDS.find(organs[j].kind)])*0.5+4
				if absf(gap) < need:
					var push = (need-absf(gap))*0.5*(1 if gap >= 0 else -1)*TAU/maxf(perimeter(),occupied())
					organs[i].a = fposmod(organs[i].a-push,TAU)
					organs[j].a = fposmod(organs[j].a+push,TAU)

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
	var hit = -1
	var distance = INF
	for i in organs.size():
		var arc = absf(arc_gap(organs[i].a,local_angle))
		if arc < WIDTH[KINDS.find(organs[i].kind)]*0.6 and arc < distance:
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
		energy -= healed*0.2
		for organ in organs:
			var unit: float = COST[KINDS.find(organ.kind)] / organ.max_hp
			var restore = minf(organ.max_hp-organ.hp,minf(dt*1.3*repair,minf(biomass/unit,energy/0.15)))
			organ.hp += restore
			organ.material += restore*unit
			biomass -= restore*unit
			energy -= restore*0.15
	return leaked
