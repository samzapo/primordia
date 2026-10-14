extends RefCounted
## All intracellular chemical authority lives in finite moving particles.
## Totals are a derived cache; no graph edge transports or credits a stock.
const Catalog = preload("res://scripts/chemistry_catalog.gd")
const MAX_NODES := 16
const MAX_COMPARTMENTS := 8
const REACTOR_COST := 10.0
var nodes: Array = []
var edges: Array = []
var particles: Array = []
var totals: Dictionary = {}
var bins: Dictionary = {}
var vacuoles: Array = []
var flux: Dictionary = {}
var limiting: Dictionary = {}
var reactor_mass := 0.0
var next_id := 0
var next_packet := 0
var tick := 0
var owner: WeakRef
var water_in := 0.0
var water_out := 0.0
var water_clock := 0.0
var osmotic_stress := 0.0
var expelled := 0.0
var solar_work := 0.0
var heat := 0.0
var frame_dt := 1.0
var light_flux := 0.0

func _init() -> void:
	for identity in ["digestion","glycolysis","respiration","fermentation","biosynthesis","salvage","transport","osmosis","photosynthesis","adenylate"]:
		_add(identity,true)
	for route in [["digestion","glycolysis","glucose"],["photosynthesis","glycolysis","glucose"],["digestion","biosynthesis","precursor"],["digestion","salvage","salvage"],["salvage","biosynthesis","precursor"],["glycolysis","respiration","pyruvate"],["glycolysis","fermentation","pyruvate"],["respiration","biosynthesis","precursor"],["respiration","adenylate","precursor"],["digestion","adenylate","precursor"],["fermentation","transport","lactate"]]:
		edges.append({"from":find_module(route[0]),"to":find_module(route[1]),"species":route[2]})

func setup(cell) -> void:
	owner = weakref(cell)
	for pair in [["food",4.0],["oxygen",16.0],["carbon",8.0],["atp",72.0],["adp",24.0],["nad",1.0]]:
		assign(pair[0],pair[1])
	# Basal catalytic proteins come from retained tissue, never free material.
	for node in nodes:
		cell.body -= 0.025
		emit("catalyst",0.025,site(node),node.id,node.id)

func _add(identity: String, basal: bool) -> int:
	var definition := Catalog.module(identity)
	var node := {"id":next_id,"module":identity,"compartment":definition.compartment,"allocation":1.0,"enabled":true,"basal":basal,"position":Vector2((next_id%3)*235,(next_id/3)*175),"local":Vector2.from_angle(next_id*2.399963)*0.48}
	if identity == "digestion": node.local = Vector2(0.65,0.0)
	if identity == "glycolysis": node.local = Vector2(0.30,0.10)
	if identity == "respiration": node.local = Vector2(0.12,0.43)
	if identity == "fermentation": node.local = Vector2(-0.34,0.29)
	if identity == "biosynthesis": node.local = Vector2(-0.40,-0.32)
	nodes.append(node)
	next_id += 1
	return node.id

func site(node: Dictionary) -> Vector2:
	var cell = owner.get_ref() if owner != null else null
	return node.local*(cell.radius if cell != null else 47.0)

func find_module(identity: String) -> int:
	for node in nodes:
		if node.module == identity: return node.id
	return -1

func node_at(identity: int) -> Dictionary:
	for node in nodes:
		if node.id == identity: return node
	return {}

func enabled(identity: String) -> bool:
	for node in nodes:
		if node.module == identity and node.enabled and node.allocation > 0: return true
	return false

func compartment_count() -> int:
	var kinds: Dictionary = {}
	for node in nodes:
		if node.compartment not in ["digestive","contractile","membrane"]: kinds[node.compartment] = true
	return kinds.size()

func amount(species: String) -> float:
	return maxf(0,float(totals.get(species,0)))

func material() -> float:
	var total := reactor_mass
	for packet in particles:
		if packet.alive: total += packet.amount*float(Catalog.data().species[packet.species].material)
	for vacuole in vacuoles: total += vacuole.material
	return total

func storage_used() -> float:
	var total := 0.0
	for packet in particles:
		if packet.alive and packet.species in ["glucose","pyruvate","lactate","precursor","salvage","catalyst_a","catalyst_b"]:
			total += packet.amount
	return total

func potential() -> float:
	var total := reactor_mass*7.5
	for packet in particles:
		if packet.alive: total += packet.fuel
	return total

func _quantum(species: String) -> float:
	return float(Catalog.data().species[species].get("quantum",0.2))*float(Catalog.data().ecology.get("parcel_scale",1))

func emit(species: String, quantity: float, at: Vector2, source: int = -1, compartment: int = -1, fuel: float = -1.0, spread: float = 0.0) -> void:
	if quantity <= 0: return
	var definition: Dictionary = Catalog.data().species[species]
	var left := quantity
	var quantum := maxf(_quantum(species),quantity/128.0)
	# Coalescence is local too. Restore particle identity order before the
	# sequential update so using bins preserves the original finite result.
	var nearby := _local_packets(species,at,2)
	nearby.sort_custom(func(a,b): return a.id<b.id)
	for existing in nearby:
		if existing.source != source or existing.compartment != compartment: continue
		if existing.p.distance_squared_to(at) > 4 or existing.amount >= quantum: continue
		var added := minf(left,quantum-existing.amount)
		existing.amount += added
		existing.fuel += added*float(definition.potential) if fuel < 0 else fuel*added/quantity
		left -= added
		if left <= 0.0000001: break
	while left > 0.0000001:
		var value := minf(left,quantum)
		var phase := float(next_packet)*2.399963
		var p := at+Vector2.from_angle(phase)*(spread*sqrt(clampf((quantity-left+value*0.5)/quantity,0,1)) if spread > 0 else 1.5)
		var energy := value*float(definition.potential) if fuel < 0 else fuel*value/quantity
		var particle := {"id":next_packet,"species":species,"amount":value,"fuel":energy,"p":p,"previous":p,"v":Vector2.ZERO,"angle":phase,"source":source,"compartment":compartment,"alive":true}
		particles.append(particle)
		_index(particle)
		next_packet += 1
		left -= value
	totals[species] = amount(species)+quantity

func _consume(packet: Dictionary, value: float) -> float:
	value = minf(value,packet.amount)
	var fuel: float = packet.fuel*value/maxf(0.00000001,packet.amount)
	packet.fuel -= fuel
	packet.amount -= value
	totals[packet.species] = maxf(0,amount(packet.species)-value)
	if packet.amount < 0.0000001: packet.alive = false
	return fuel

func assign(species: String, quantity: float) -> void:
	# Compatibility for explicit initial conditions and legacy fixtures.
	# Gameplay uptake calls receive() with the physical membrane contact.
	quantity = maxf(0,quantity)
	var difference := quantity-amount(species)
	if difference > 0:
		var at := Vector2.ZERO
		var cell = owner.get_ref() if owner != null else null
		if cell != null:
			at = cell.local_point(0)*0.70 if species == "food" else Vector2.ZERO
		emit(species,difference,at,-1,-1,-1.0,cell.radius*0.65 if cell != null and species != "food" else 0.0)
	elif difference < 0:
		var left := -difference
		for packet in particles:
			if not packet.alive or packet.species != species: continue
			var taken := minf(left,packet.amount)
			_consume(packet,taken)
			left -= taken
			if left < 0.0000001: break

func raw_fuel() -> float:
	var value := 0.0
	for packet in particles:
		if packet.alive and packet.species == "food": value += packet.fuel
	return value

func set_raw_fuel(value: float) -> void:
	var current := raw_fuel()
	var count := amount("food")
	for packet in particles:
		if packet.alive and packet.species == "food":
			packet.fuel = maxf(0,value)*packet.fuel/current if current > 0.0000001 else maxf(0,value)*packet.amount/maxf(0.0000001,count)

func receive(kind: int, quantity: float, capacity: float, world_at: Vector2) -> void:
	var cell = owner.get_ref()
	var local := Vector2(wrapf(world_at.x-cell.position.x,-2048,2048),wrapf(world_at.y-cell.position.y,-1280,1280)).rotated(-cell.angle)
	var normal := local.normalized()
	local = normal*minf(local.length(),cell.support(local.angle()+cell.angle)-2)
	var species := "food" if kind == 0 else "oxygen" if kind == 1 else "carbon"
	emit(species,quantity,local,-1,-1,minf(quantity,capacity)*7.5 if kind == 0 else -1.0)

func _index(packet: Dictionary) -> void:
	var bin := Vector2i(floori(packet.p.x/20),floori(packet.p.y/20))
	if not bins.has(bin): bins[bin] = []
	bins[bin].append(packet)

func _local_packets(species: String, center: Vector2, reach: float, node_id: int = -1) -> Array:
	var result: Array = []
	var low := Vector2i(floori((center.x-reach)/20),floori((center.y-reach)/20))
	var high := Vector2i(floori((center.x+reach)/20),floori((center.y+reach)/20))
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for packet in bins.get(Vector2i(x,y),[]):
				if not packet.alive or packet.species != species or packet.p.distance_squared_to(center) > reach*reach: continue
				if node_id >= 0 and packet.source >= 0 and packet.source != node_id:
					var permitted := species in ["oxygen","carbon","atp","adp","nad","nadh","catalyst_a","catalyst_b"]
					for edge in edges:
						if edge.from == packet.source and edge.to == node_id and edge.species == species: permitted = true; break
					if not permitted: continue
				result.append(packet)
	return result

func _local_amount(species: String, center: Vector2, reach: float, node_id: int = -1) -> float:
	var value := 0.0
	for packet in _local_packets(species,center,reach,node_id): value += packet.amount
	return value

func _take_local(species: String, value: float, center: Vector2, reach: float, node_id: int = -1) -> float:
	var energy := 0.0
	for packet in _local_packets(species,center,reach,node_id):
		var taken := minf(value,packet.amount)
		energy += _consume(packet,taken)
		value -= taken
		if value < 0.0000001: break
	return energy

func spend_atp(value: float, at: Vector2, reach: float) -> float:
	var taken := minf(maxf(0,value),_local_amount("atp",at,reach))
	_take_local("atp",taken,at,reach)
	emit("adp",taken,at)
	heat += taken
	return taken

func produce_atp(value: float, at: Vector2, reach: float) -> float:
	var made := minf(maxf(0,value),_local_amount("adp",at,reach))
	_take_local("adp",made,at,reach)
	emit("atp",made,at)
	return made

func reserve_atp(quantity: float, storing: bool) -> void:
	var source := "atp" if storing else "reserved_atp"
	var destination := "reserved_atp" if storing else "atp"
	var remaining := minf(maxf(0,quantity),amount(source))
	var original: Array = particles.duplicate()
	for packet in original:
		if not packet.alive or packet.species != source: continue
		var value: float = minf(remaining,packet.amount)
		var fuel := _consume(packet,value)
		emit(destination,value,packet.p,-1,-1,fuel)
		remaining -= value
		if remaining <= 0.0000001: break

func _capture_food(cell) -> void:
	if vacuoles.size() >= 12: return
	for packet in particles:
		if not packet.alive or packet.species != "food" or packet.compartment != -1: continue
		if cell.biomass < 0.025: return
		cell.biomass -= 0.025
		var id := next_packet+1000000
		var center: Vector2 = packet.p
		vacuoles.append({"id":id,"p":center,"radius":8.0,"acid":0.0,"material":0.0125,"age":0.0})
		for nearby in _local_packets("food",center,8): nearby.compartment = id
		emit("catalyst",0.0125,center,find_module("digestion"),id)
		return

func _digest(cell, h: float) -> void:
	var node := node_at(find_module("digestion"))
	if not node.enabled or node.allocation <= 0: return
	for vacuole in vacuoles:
		vacuole.age += h
		var center: Vector2 = vacuole.p
		var pump := minf(1-vacuole.acid,h*0.55)
		var paid := spend_atp(pump*0.025,center,18)
		if pump > 0: vacuole.acid += pump*minf(1,paid/maxf(0.000001,pump*0.025))
		if vacuole.acid < 0.35: continue
		var enzyme := {}
		for packet in _local_packets("catalyst",center,9):
			if packet.compartment == vacuole.id: enzyme = packet; break
		if enzyme.is_empty(): continue
		var candidates := _local_packets("food",enzyme.p,9)
		for packet in candidates:
			if packet.compartment != vacuole.id: continue
			var extent: float = minf(packet.amount,h*float(Catalog.module("digestion").rate)*cell.growth_scale()*float(node.allocation))
			extent = minf(extent,_local_amount("atp",enzyme.p,18)/0.08)
			if extent <= 0: limiting[node.id] = "Local ATP"; break
			var fuel := _consume(packet,extent)
			var rich := clampf(fuel/7.5,0,extent)
			spend_atp(extent*0.08,enzyme.p,18)
			emit("glucose",rich*0.85,enzyme.p,node.id)
			emit("precursor",rich*0.10,enzyme.p,node.id)
			emit("waste",rich*0.05,enzyme.p,node.id)
			emit("salvage",extent-rich,enzyme.p,node.id)
			heat += maxf(0,fuel-rich*7.125)
			flux[node.id] = float(flux.get(node.id,0))+extent/maxf(0.000001,frame_dt)
			break
	var retained: Array = []
	for vacuole in vacuoles:
		var food := 0.0
		for packet in particles:
			if packet.alive and packet.compartment == vacuole.id and packet.species == "food": food += packet.amount
		if food > 0.000001: retained.append(vacuole)
		else:
			cell.biomass += vacuole.material
			for packet in particles:
				if packet.alive and packet.compartment == vacuole.id: packet.compartment = -1
	vacuoles = retained

func _react(cell, node: Dictionary, enzyme: Dictionary, h: float) -> void:
	var definition := Catalog.module(node.module)
	if definition.has("action"): return
	var center: Vector2 = enzyme.p
	var reach := maxf(10,cell.radius*0.28)
	var extent: float = float(definition.rate)*h*cell.growth_scale()*float(node.allocation)
	var limit := "Capacity"
	for species in definition.inputs:
		var possible := _local_amount(species,center,reach,node.id)/float(definition.inputs[species])
		if possible < extent: extent = possible; limit = Catalog.data().species[species].name
	var cost := maxf(0,-float(definition.atp))
	var gain := maxf(0,float(definition.atp))
	if cost > 0: extent = minf(extent,_local_amount("atp",center,reach)/cost)
	if gain > 0: extent = minf(extent,_local_amount("adp",center,reach)/gain)
	limiting[node.id] = limit
	if extent <= 0.00000001: return
	var energy_in := 0.0
	for species in definition.inputs:
		energy_in += _take_local(species,extent*float(definition.inputs[species]),center,reach,node.id)
	if cost > 0: spend_atp(extent*cost,center,reach)
	var output_potential := 0.0
	for species in definition.outputs:
		var quantity: float = extent*float(definition.outputs[species])
		output_potential += quantity*float(Catalog.data().species[species].potential)
		if species == "biomass":
			cell.biomass += quantity # Incorporation into stationary structure.
		else: emit(species,quantity,center,node.id)
	if gain > 0:
		var made := produce_atp(extent*gain,center,reach)
		cell.report_energy_gain(made)
	heat += maxf(0,energy_in-output_potential-extent*gain)
	flux[node.id] = float(flux.get(node.id,0))+extent/maxf(0.000001,frame_dt)
	if node.module == "glycolysis": cell.processed += extent
	if node.module == "fermentation": cell.fermented += extent; cell.fermentation_activity = 2

func _autocatalysis(cell, node: Dictionary, enzyme: Dictionary, h: float) -> void:
	var at: Vector2 = enzyme.p
	var reach := maxf(10,cell.radius*0.22)
	var a := _local_amount("catalyst_a",at,reach)
	var b := _local_amount("catalyst_b",at,reach)
	var feed := _local_amount("precursor",at,reach,node.id)
	var extent: float = minf(feed,h*0.25*(a+b)*float(node.allocation))
	extent = minf(extent,_local_amount("atp",at,reach)/0.25)
	if a <= 0 or b <= 0: extent = 0
	if extent > 0:
		_take_local("precursor",extent,at,reach,node.id)
		spend_atp(extent*0.25,at,reach)
		emit("catalyst_a",extent*b/(a+b),at,node.id,node.id)
		emit("catalyst_b",extent*a/(a+b),at,node.id,node.id)
	flux[node.id] = float(flux.get(node.id,0))+extent/maxf(0.000001,frame_dt)
	limiting[node.id] = "Local precursor and catalysts"

func _move(cell, h: float) -> void:
	# Circulation and sqrt(dt) diffusion physically carry every metabolite.
	for vacuole in vacuoles:
		var at: Vector2 = vacuole.p
		vacuole.p += Vector2(-at.y,at.x)*0.18*h
	for packet in particles:
		if not packet.alive: continue
		packet.previous = packet.p
		var at: Vector2 = packet.p
		var n := float(packet.id*73856093 ^ tick*19349663 ^ cell.id*83492791)
		var noise := Vector2(sin(n*0.000017),cos(n*0.000023))*sqrt(40*h)
		packet.angle = wrapf(packet.angle+sin(n*0.000013)*sqrt(h)*1.4,-PI,PI)
		var delta := Vector2(-at.y,at.x)*0.18*h+noise
		packet.p += delta
		if packet.species == "catalyst" and packet.compartment < 1000000:
			var node := node_at(packet.source)
			if not node.is_empty(): packet.p = site(node)+(packet.p-site(node)).limit_length(cell.radius*0.08)
		for vacuole in vacuoles:
			if packet.compartment == vacuole.id:
				var center: Vector2 = vacuole.p
				packet.p = center+(packet.p-center).limit_length(vacuole.radius-1)
		# Internal membranes retain their catalysts; permitted products diffuse
		# through them. An edge changes binding compatibility, never position.
		if packet.compartment >= 0 and packet.compartment < 1000000 and packet.species in ["catalyst_a","catalyst_b"]:
			var node := node_at(packet.compartment)
			if not node.is_empty(): packet.p = site(node)+(packet.p-site(node)).limit_length(cell.radius*0.20)
		var limit: float = maxf(2,cell.local_point(cell.surface_parameter(packet.p.angle())).length()-2)
		packet.p = packet.p.limit_length(limit)
		var nucleus: Vector2 = Vector2(-0.12,-0.10)*cell.radius
		var offset: Vector2 = packet.p-nucleus
		if offset.length() < cell.radius*0.24:
			packet.p = nucleus+offset.normalized()*cell.radius*0.24
	bins.clear()
	for packet in particles:
		if packet.alive: _index(packet)
	tick += 1

func _osmosis(cell, h: float, external: float) -> void:
	var concentration := (amount("food")+storage_used()+amount("waste"))/maxf(1,cell.growth_scale()*24)
	var incoming: float = maxf(0,concentration+0.22-external)*(0.18+cell.holes.size()*0.04)*h
	# Water enters at the real membrane from the implicit solvent reservoir.
	var at: Vector2 = cell.local_point(float(tick)*2.399963)*0.92
	var trials := incoming/0.04
	var entries := floori(trials)
	var phase := fposmod(sin(float(tick*7919+cell.id*104729))*43758.5453,1)
	if phase < trials-entries: entries += 1
	emit("water",entries*0.04,at)
	water_in = entries*0.04/h
	var pumped := 0.0
	if enabled("osmosis"):
		for side in [-1,1]:
			var center: Vector2 = Vector2(0.02,side*0.62)*cell.radius
			var taken := minf(_local_amount("water",center,cell.radius*0.22),0.16*cell.growth_scale()*h)
			taken = minf(taken,_local_amount("atp",center,cell.radius*0.35)/0.15)
			_take_local("water",taken,center,cell.radius*0.22)
			spend_atp(taken*0.15,center,cell.radius*0.35)
			pumped += taken
	expelled += pumped
	water_out = pumped/h
	water_clock += pumped/maxf(0.02,cell.growth_scale()*0.12)
	var load := amount("water")/maxf(0.1,cell.growth_scale()*2)
	osmotic_stress = clampf(load,0,1)
	if load > 1:
		cell.health = maxf(0,cell.health-(load-1)*2*h)
		cell.death_hint = "Osmotic overload; contractile pumping failed"

func advance(cell, dt: float, external_osmolarity: float = 0.15) -> void:
	if dt <= 0 or cell.dead: return
	frame_dt = dt
	flux.clear()
	flux[find_module("photosynthesis")] = light_flux
	limiting.clear()
	var left := dt
	while left > 0.000001:
		var h := minf(left,0.125)
		left -= h
		_move(cell,h)
		_capture_food(cell)
		_digest(cell,h)
		var enzymes: Array = []
		for packet in particles:
			if packet.alive and packet.species == "catalyst" and packet.compartment < 1000000: enzymes.append(packet)
		for enzyme in enzymes:
			var node := node_at(enzyme.source)
			if node.is_empty() or not node.enabled or node.allocation <= 0: continue
			if node.module == "autocatalysis": _autocatalysis(cell,node,enzyme,h)
			else: _react(cell,node,enzyme,h)
		for packet in particles:
			if packet.alive and packet.species in ["catalyst_a","catalyst_b"]:
				var retired: float = packet.amount*(1-exp(-0.015*h))
				_consume(packet,retired)
				emit("waste",retired,packet.p,packet.source)
				heat += retired*7.5
		_osmosis(cell,h,external_osmolarity)
		particles = particles.filter(func(packet): return packet.alive)

func add_module(identity: String, cell) -> int:
	if Catalog.module(identity).is_empty() or nodes.size() >= MAX_NODES or cell.dead or cell.biomass < REACTOR_COST: return -1
	var definition := Catalog.module(identity)
	# These domains are inherent anatomy; their rate is configured in place.
	# Extra glycolytic/respiratory/synthetic enzymes and condensates are paid.
	if identity in ["digestion","osmosis","photosynthesis"] and find_module(identity)>=0: return -1
	var kinds: Dictionary = {}
	for node in nodes: kinds[node.compartment] = true
	if definition.compartment not in ["digestive","contractile","membrane"] and not kinds.has(definition.compartment) and compartment_count() >= MAX_COMPARTMENTS: return -1
	cell.biomass -= REACTOR_COST
	var id := _add(identity,false)
	var seed := 0.1 if identity == "autocatalysis" else 0.0
	reactor_mass += REACTOR_COST-0.025-seed
	emit("catalyst",0.025,site(node_at(id)),id,id)
	if seed > 0:
		emit("catalyst_a",seed*0.5,site(node_at(id)),id,id)
		emit("catalyst_b",seed*0.5,site(node_at(id)),id,id)
	cell.update_geometry()
	return id

func remove_module(identity: int, cell) -> bool:
	var node := node_at(identity)
	if node.is_empty() or node.basal: return false
	var material := REACTOR_COST-0.025-(0.1 if node.module == "autocatalysis" else 0.0)
	cell.biomass += material*0.5
	emit("waste",material*0.5,site(node),identity)
	reactor_mass -= material
	for packet in particles:
		if packet.compartment == identity: packet.compartment = -1
		if packet.alive and packet.species == "catalyst" and packet.source == identity:
			var quantity: float = packet.amount
			_consume(packet,quantity)
			emit("waste",quantity,packet.p)
	nodes.erase(node)
	edges = edges.filter(func(edge): return edge.from != identity and edge.to != identity)
	cell.update_geometry()
	return true

func connect_route(from_id: int, to_id: int, species: String) -> String:
	var a := node_at(from_id)
	var b := node_at(to_id)
	if a.is_empty() or b.is_empty() or from_id == to_id: return "Choose two different installed modules."
	var source := Catalog.module(a.module)
	var destination := Catalog.module(b.module)
	var produced: Dictionary = source.outputs.duplicate()
	if source.id == "digestion": produced["salvage"] = 1
	if not produced.has(species) or not destination.inputs.has(species): return "These ports carry different metabolites."
	for edge in edges:
		if edge.from == from_id and edge.to == to_id and edge.species == species: return ""
	edges.append({"from":from_id,"to":to_id,"species":species})
	return ""

func disconnect_route(from_id: int, to_id: int, species: String) -> void:
	edges = edges.filter(func(edge): return not (edge.from == from_id and edge.to == to_id and edge.species == species))

func configure(identity: int, allocation: float, active: bool) -> bool:
	var node := node_at(identity)
	if node.is_empty() or not is_finite(allocation) or allocation < 0 or allocation > 1: return false
	node.allocation = allocation
	node.enabled = active
	return true

func configuration() -> Dictionary:
	var saved: Array = []
	for node in nodes:
		var item: Dictionary = node.duplicate(true)
		item.position = [node.position.x,node.position.y]
		item.local = [node.local.x,node.local.y]
		saved.append(item)
	return {"version":1,"nodes":saved,"edges":edges.duplicate(true)}

func load_configuration(value: Dictionary) -> String:
	if value.get("version",0) != 1 or not value.get("nodes") is Array or not value.get("edges") is Array: return "Unsupported pathway blueprint."
	if value.nodes.size() != nodes.size(): return "Install matching modules before loading this configuration."
	var checked: Array = []
	var identities: Dictionary = {}
	for item in value.nodes:
		if not item is Dictionary: return "Invalid module."
		var identity = item.get("id")
		if not (identity is int or identity is float) or not is_finite(float(identity)): return "Invalid module identity."
		var current := node_at(int(identity))
		if current.is_empty() or current.module != item.get("module","") or identities.has(int(identity)): return "Module inventory differs."
		var allocation = item.get("allocation",1.0)
		var point = item.get("position",[])
		var local = item.get("local",[])
		if not (allocation is float or allocation is int) or not is_finite(float(allocation)) or allocation < 0 or allocation > 1: return "Invalid allocation."
		if not item.get("enabled",true) is bool or not point is Array or point.size() != 2 or not local is Array or local.size() != 2: return "Invalid module layout."
		for coordinate in point+local:
			if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)): return "Invalid coordinates."
		var copy := current.duplicate()
		copy.allocation = float(allocation)
		copy.enabled = item.get("enabled",true)
		copy.position = Vector2(clampf(point[0],-10000,10000),clampf(point[1],-10000,10000))
		# Loaded graph layout cannot teleport installed catalysts/compartments.
		checked.append(copy)
		identities[int(identity)] = true
	var old_edges := edges.duplicate(true)
	edges.clear()
	for edge in value.edges:
		if not edge is Dictionary or not edge.get("species","") is String: edges = old_edges; return "Invalid route."
		var a = edge.get("from")
		var b = edge.get("to")
		if not (a is int or a is float) or not (b is int or b is float): edges = old_edges; return "Invalid route identities."
		var error := connect_route(int(a),int(b),edge.species)
		if error != "": edges = old_edges; return error
	nodes = checked
	return ""

func inherit_configuration(parent) -> void:
	nodes = parent.nodes.duplicate(true)
	edges = parent.edges.duplicate(true)
	next_id = parent.next_id
	reactor_mass = parent.reactor_mass
	for node in nodes:
		if not node.basal: emit("catalyst",0.025,site(node),node.id,node.id)

func partition(parent, fraction: float) -> float:
	var transferred := 0.0
	var source: Array = parent.particles.duplicate()
	for packet in source:
		if not packet.alive or packet.species in ["atp","reserved_atp","adp","water","food","oxygen","carbon","waste","catalyst"]: continue
		var value: float = packet.amount*clampf(fraction,0,1)
		var fuel: float = parent._consume(packet,value)
		emit(packet.species,value,packet.p,packet.source,-1,fuel)
		transferred += value*float(Catalog.data().species[packet.species].material)
	return transferred

func anchor_photosynthesis(cell, organ: Dictionary) -> void:
	var node := node_at(find_module("photosynthesis"))
	if node.is_empty(): return
	var before := site(node)
	node.local = cell.local_point(organ.a)*0.85/maxf(1,cell.radius)
	var shift := site(node)-before
	for packet in particles:
		if packet.alive and packet.species == "catalyst" and packet.source == node.id: packet.p += shift

func photosynthesize(sim, cell, organ: Dictionary, dt: float) -> void:
	if not enabled("photosynthesis"): return
	var node := node_at(find_module("photosynthesis"))
	var center: Vector2 = cell.local_point(organ.a)*0.85
	var reach: float = maxf(12,cell.radius*0.30)
	var catalyst := false
	for packet in _local_packets("catalyst",center,reach):
		if packet.source == node.id: catalyst = true; break
	if not catalyst: limiting[node.id] = "Local catalyst"; return
	var light: float = sim.light_at(cell.organ_position(organ))
	var capacity: float = dt*float(Catalog.data().ecology.photosynthesis_rate)*0.35*light*organ.scale*organ.scale*organ.hp/organ.max_hp*float(node.allocation)
	var extent := minf(_local_amount("carbon",center,reach),capacity)
	if extent <= 0: limiting[node.id] = "Local dissolved carbon"; return
	_take_local("carbon",extent,center,reach)
	emit("glucose",extent*0.65,center,node.id)
	emit("oxygen",extent*2.5,center,node.id)
	cell.biomass += extent*0.35
	var made := produce_atp(extent*4,center,reach)
	cell.report_energy_gain(made,organ)
	solar_work += extent*7.5+made
	cell.fixed_carbon += extent
	cell.oxygen_produced += extent*2.5
	cell.consumed(organ,extent)
	light_flux += extent/dt
	flux[node.id] = light_flux
	limiting[node.id] = "Light and local carbon"
	if cell == sim.player: sim.evolution.record("photo",extent)

func excrete(sim, cell, dt: float) -> void:
	var outlet: Vector2 = cell.local_point(cell.excretion_angle())*0.88
	var waste_budget: float = dt*4*cell.growth_scale()
	for packet in particles:
		if not packet.alive: continue
		var kind := -1
		var allowed := 0.0
		if packet.species == "waste" and packet.p.distance_to(outlet) <= maxf(12,cell.radius*0.25):
			kind = 2
			allowed = minf(packet.amount,waste_budget)
		elif packet.species in ["oxygen","carbon","glucose"]:
			var bound: float = cell.local_point(cell.surface_parameter(packet.p.angle())).length()
			if packet.p.length() < bound-7: continue
			var threshold: float = cell.oxygen_capacity()*0.8 if packet.species == "oxygen" else (20.0 if cell.count("photosynthesis")>0 else 3.0) if packet.species == "carbon" else maxf(4,cell.growth_scale()*6)
			if amount(packet.species) <= threshold: continue
			kind = 1 if packet.species == "oxygen" else 5 if packet.species == "carbon" else 0
			allowed = packet.amount # A membrane crossing releases the actual finite packet.
		if kind < 0 or allowed <= 0: continue
		var potential := _consume(packet,allowed)
		var normal: Vector2 = packet.p.normalized().rotated(cell.angle)
		var at: Vector2 = cell.position+packet.p.rotated(cell.angle)+normal*9
		sim.spawn_particle(kind,at,normal*12,allowed,cell.id)
		if kind == 0:
			sim.last_spawn.capacity = minf(allowed,potential/7.5)
			sim._commit_spawn_metadata()
		if kind == 2: waste_budget -= allowed

func decay_atp(cell, dt: float) -> float:
	var total := amount("atp")
	if total <= 0 or dt <= 0: return 0
	var remaining: float = total/(1+cell.ATP_TURNOVER*total/cell.energy_reference()*dt)
	var fraction := clampf(1-remaining/total,0,1)
	var spent := 0.0
	var original: Array = particles.duplicate()
	for packet in original:
		if not packet.alive or packet.species != "atp": continue
		var value: float = packet.amount*fraction
		_consume(packet,value)
		emit("adp",value,packet.p)
		spent += value
	heat += spent
	return spent

func clone_for(cell):
	var copy = get_script().new()
	copy.owner = weakref(cell)
	for key in ["nodes","edges","particles","totals","vacuoles","flux","limiting"]:
		copy.set(key,get(key).duplicate(true))
	for key in ["reactor_mass","next_id","next_packet","tick","water_in","water_out","water_clock","osmotic_stress","expelled","solar_work","heat","frame_dt","light_flux"]: copy.set(key,get(key))
	copy.bins.clear()
	for packet in copy.particles:
		if packet.alive: copy._index(packet)
	return copy
