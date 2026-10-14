extends RefCounted
## Explicit checkpoint-resolution migration, never a transport or reaction path.
const VERSION := 1
const GROUP := 10
const EXTERNAL_BIN := 256.0
const INTERNAL_BIN := 8.0

static func _join(a: Dictionary,b: Dictionary,internal: bool) -> void:
	var total: float=a.amount+b.amount
	var weight: float=b.amount/total
	a.p=a.p.lerp(b.p,weight);a.previous=a.p
	a.v=a.v.lerp(b.v,weight)
	if internal: a.fuel+=b.fuel
	else:
		a.capacity=float(a.get("capacity",a.amount))+float(b.get("capacity",b.amount))
		a.age=lerpf(a.get("age",0),b.get("age",0),weight)
		a.spin=lerpf(a.get("spin",0),b.get("spin",0),weight)
	a.amount=total

static func _reduce(packets: Array,internal: bool) -> Array:
	var output: Array=[]
	var groups: Dictionary={}
	for original in packets:
		if not original.alive: continue
		var packet: Dictionary=original.duplicate(true)
		var eligible: bool=packet.species not in ["catalyst","catalyst_a","catalyst_b"] if internal else packet.kind in [0,1,2,5] and not packet.has("report")
		if not eligible or packet.amount<=0:
			output.append(packet);continue
		var bin:=Vector2i((packet.p/(INTERNAL_BIN if internal else EXTERNAL_BIN)).floor())
		# Never combine different species, ownership, pathway sources, vacuoles,
		# chunks, or external elapsed-time debts. Preserve sparse product facts.
		var facts: Array=[packet.species,packet.source,packet.compartment,bin] if internal else [packet.kind,packet.owner,bin,packet.get("source_radius",0),packet.get("product",null),packet.get("chemical_at",null),packet.get("transport_at",null)]
		var key: String=var_to_bytes(facts).hex_encode()
		if groups.has(key) and groups[key].count<GROUP:
			_join(groups[key].packet,packet,internal);groups[key].count+=1
		else:
			groups[key]={"packet":packet,"count":1};output.append(packet)
	return output

static func apply(world) -> Dictionary:
	assert(world.resident==null and not world.particle_pool)
	var report: Dictionary={"version":VERSION,"external_before":world.particles.size(),"internal_before":0,"internal_after":0}
	world.particles=_reduce(world.particles,false)
	report["external_after"]=world.particles.size()
	for cell in world.cells:
		var chemistry=cell.chemistry
		report.internal_before+=chemistry.particles.size()
		chemistry.particles=_reduce(chemistry.particles,true)
		report.internal_after+=chemistry.particles.size()
		chemistry.bins.clear()
		for packet in chemistry.particles: chemistry._index(packet)
	return report
