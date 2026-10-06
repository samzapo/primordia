extends RefCounted
## A tension network with membrane anchors and free internal junctions.
## Branching splits an existing link; its segments retain one tension group.
var links: Array = []
var junctions: Dictionary = {}
var next_link := 0
var next_group := 0
var next_junction := 0
var last_radius := 0.0

func point(anchor: Dictionary, membrane) -> Vector2:
	if anchor.kind == "point": return anchor.p
	if anchor.kind == "junction": return junctions[anchor.id].p
	if anchor.kind == "link":
		var link := link_by_id(anchor.id)
		if link.is_empty(): return Vector2.ZERO
		return point(link.a,membrane).lerp(point(link.b,membrane),anchor.t)
	var phase: float = fposmod(anchor.a,TAU)/TAU*membrane.COUNT
	var i := int(phase)
	return membrane.points[i].lerp(membrane.points[(i+1)%membrane.COUNT],phase-i)

func link_by_id(identity: int) -> Dictionary:
	for link in links:
		if link.id == identity: return link
	return {}

func valid(anchor: Dictionary) -> bool:
	if anchor.is_empty(): return false
	if anchor.kind == "point": return anchor.p.is_finite()
	if anchor.kind == "membrane": return is_finite(anchor.a)
	if anchor.kind == "junction": return junctions.has(anchor.id)
	if anchor.kind == "link": return not link_by_id(anchor.id).is_empty() and is_finite(anchor.t) and anchor.t >= 0 and anchor.t <= 1
	return false

func _segment(a: Dictionary, b: Dictionary, tension: float, length: float, radius: float, group: int) -> int:
	var identity := next_link
	next_link += 1
	links.append({"id":identity,"group":group,"a":a.duplicate(),"b":b.duplicate(),"tension":tension,"length":length,"radius":radius,"lambda":0.0})
	return identity

func connect_points(start: Dictionary, end: Dictionary, tension: float, membrane, radius: float) -> int:
	if not valid(start) or not valid(end) or not is_finite(tension): return -1
	var distance := point(start,membrane).distance_to(point(end,membrane))
	if distance < 6: return -1
	var anchors: Array = [start.duplicate(),end.duplicate()]
	var split_ids: Array[int] = []
	for anchor in anchors:
		if anchor.kind == "link" and not split_ids.has(anchor.id): split_ids.append(anchor.id)
	for identity in split_ids:
		var link := link_by_id(identity)
		var cuts: Array = []
		for anchor in anchors:
			if anchor.kind == "link" and anchor.id == identity: cuts.append(anchor)
		cuts.sort_custom(func(a,b): return a.t < b.t)
		var prior: Dictionary = link.a
		var previous_t := 0.0
		for cut in cuts:
			var t: float = cut.t
			var endpoint: Dictionary
			if t < 0.001: endpoint = link.a
			elif t > 0.999: endpoint = link.b
			else:
				var at := point(cut,membrane)
				junctions[next_junction] = {"p":at,"previous":at}
				endpoint = {"kind":"junction","id":next_junction}
				next_junction += 1
				_segment(prior,endpoint,link.tension,link.length*(t-previous_t),link.radius,link.group)
				prior = endpoint
				previous_t = t
			cut.clear()
			cut.merge(endpoint)
		if previous_t < 0.999: _segment(prior,link.b,link.tension,link.length*(1-previous_t),link.radius,link.group)
		links.erase(link)
	for anchor in anchors:
		if anchor.kind == "point":
			junctions[next_junction] = {"p":anchor.p,"previous":anchor.p}
			anchor.clear()
			anchor.merge({"kind":"junction","id":next_junction})
			next_junction += 1
	var group := next_group
	next_group += 1
	_segment(anchors[0],anchors[1],clampf(tension,0,1),distance,radius,group)
	return group

func set_tension(group: int, value: float) -> void:
	for link in links:
		if link.group == group: link.tension = clampf(value,0,1)

func remove_group(group: int) -> void:
	links = links.filter(func(link): return link.group != group)
	var used: Dictionary = {}
	for link in links:
		for endpoint in [link.a,link.b]:
			if endpoint.kind == "junction": used[endpoint.id] = true
	for identity in junctions.keys():
		if not used.has(identity): junctions.erase(identity)

func begin(radius: float) -> void:
	var growth := radius/last_radius if last_radius > 0 else 1.0
	last_radius = radius
	for junction in junctions.values():
		junction.p *= growth
		junction.previous *= growth
		var old: Vector2 = junction.p
		junction.p += (junction.p-junction.previous)*0.8
		junction.previous = old
	for link in links: link.lambda = 0.0

func _inverse_mass(anchor: Dictionary, count: int) -> float:
	if anchor.kind == "junction": return 1.5
	var fraction := fposmod(anchor.a,TAU)/TAU*count
	fraction -= floorf(fraction)
	return pow(1-fraction,2)+fraction*fraction

func _move(anchor: Dictionary, displacement: Vector2, membrane) -> void:
	if anchor.kind == "junction":
		junctions[anchor.id].p += displacement*1.5
		return
	var phase: float = fposmod(anchor.a,TAU)/TAU*membrane.COUNT
	var i := int(phase)
	membrane.points[i] += displacement*(1-(phase-i))
	membrane.points[(i+1)%membrane.COUNT] += displacement*(phase-i)

func solve(membrane, dt: float, radius: float) -> void:
	var compliance := 0.00012/(dt*dt)
	for link in links:
		var delta := point(link.b,membrane)-point(link.a,membrane)
		var length := delta.length()
		var rest: float = link.length*radius/link.radius*(1-link.tension*0.65)
		if length < 0.0001 or length <= rest: continue
		var dl: float = (-(length-rest)-compliance*link.lambda)/(_inverse_mass(link.a,membrane.COUNT)+_inverse_mass(link.b,membrane.COUNT)+compliance)
		link.lambda += dl
		_move(link.a,-delta/length*dl,membrane)
		_move(link.b,delta/length*dl,membrane)

func seed_layout(seed_number: int, membrane, radius: float) -> void:
	# A separate RNG keeps anatomy generation from consuming the ecology stream.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_number ^ 0x4d595df4
	var count := rng.randi_range(0,4)
	for i in count:
		for attempt in 32:
			# Each link is committed before choosing the next endpoints. A later
			# link can attach anywhere along an earlier one, on either end.
			var a := _seed_anchor(rng)
			var b := _seed_anchor(rng)
			if point(a,membrane).distance_to(point(b,membrane)) < maxf(6,radius*0.30): continue
			if connect_points(a,b,rng.randf(),membrane,radius) >= 0: break

func _seed_anchor(rng: RandomNumberGenerator) -> Dictionary:
	if not links.is_empty() and rng.randf() < 0.45:
		var link: Dictionary = links[rng.randi_range(0,links.size()-1)]
		return {"kind":"link","id":link.id,"t":rng.randf_range(0.15,0.85)}
	return {"kind":"membrane","a":rng.randf()*TAU}
