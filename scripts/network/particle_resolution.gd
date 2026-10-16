extends RefCounted
## Explicit checkpoint-resolution migration, never a transport or reaction path.
const VERSION := 3
const GROUP := 10
const EXTERNAL_BIN := 256.0
const INTERNAL_BIN := 8.0

static func _join(a: Dictionary,b: Dictionary,internal: bool) -> void:
	var total: float=a.amount+b.amount
	var weight: float=b.amount/total
	a.p=a.p.lerp(b.p,weight);a.previous=a.p
	a.v=a.v.lerp(b.v,weight)
	if internal:
		a.fuel+=b.fuel
		if a.has("nutrition") or b.has("nutrition"):a.nutrition=float(a.get("nutrition",0))+float(b.get("nutrition",0))
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

static func _legacy_apply(world) -> Dictionary:
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

static func _morton(at: Vector2) -> int:
	var x:=clampi(floori(at.x*4)+32768,0,65535)
	var y:=clampi(floori(at.y*4)+32768,0,65535)
	var key:=0
	for bit in 16:key|=((x>>bit)&1)<<(bit*2);key|=((y>>bit)&1)<<(bit*2+1)
	return key

static func _internal_tenth(packets: Array,radius: float) -> Dictionary:
	var kinds: Dictionary={};var output: Array=[];var displacement:=0.0
	for packet in packets:
		if not packet.alive:continue
		# Installed catalysts retain individual sites and identities.
		if packet.species=="catalyst" or packet.amount<=0 or packet.keys().any(func(key):return key not in ["id","species","amount","fuel","p","previous","v","angle","source","compartment","alive"]):output.append(packet.duplicate(true));continue
		var key:=var_to_bytes([packet.species,packet.source,packet.compartment]).hex_encode()
		if not kinds.has(key):kinds[key]=[]
		kinds[key].append({"packet":packet,"order":_morton(packet.p)})
	for group in kinds.values():
		# Spatial order keeps coarse parcels local. A hard diameter bound avoids
		# joining distant substrates just to hit an exact global packet count.
		group.sort_custom(func(a,b):
			return a.packet.id<b.packet.id if a.order==b.order else a.order<b.order)
		var chunk: Array=[];var low:=Vector2.ZERO;var high:=Vector2.ZERO
		for item in group:
			var packet: Dictionary=item.packet
			var next_low: Vector2=packet.p if chunk.is_empty() else low.min(packet.p)
			var next_high: Vector2=packet.p if chunk.is_empty() else high.max(packet.p)
			if chunk.size()>=GROUP or (not chunk.is_empty() and next_low.distance_to(next_high)>maxf(8,radius*.25)):
				displacement=maxf(displacement,_flush_internal(chunk,output));chunk=[];next_low=packet.p;next_high=packet.p
			chunk.append(packet);low=next_low;high=next_high
		if not chunk.is_empty():displacement=maxf(displacement,_flush_internal(chunk,output))
	# Retain original identity/insertion order through the one-time conversion.
	output.sort_custom(func(a,b):return a.id<b.id)
	return {"particles":output,"max_displacement":displacement}

static func _flush_internal(chunk: Array,output: Array) -> float:
	var joined: Dictionary=chunk[0].duplicate(true)
	for i in range(1,chunk.size()):_join(joined,chunk[i],true)
	var distance:=0.0
	for packet in chunk:distance=maxf(distance,packet.p.distance_to(joined.p))
	output.append(joined)
	return distance

static func apply(world,from_version: int=0) -> Dictionary:
	if from_version>=VERSION:
		var count: int=world.cells.reduce(func(total,cell):return total+cell.chemistry.particle_count(),0)
		return {"version":VERSION,"external_before":world.particles.size(),"external_after":world.particles.size(),"internal_before":count,"internal_after":count,"already_applied":true}
	assert(world.resident==null and not world.particle_pool)
	var report:=_legacy_apply(world) if from_version<1 else {"external_before":world.particles.size(),"external_after":world.particles.size()}
	report.version=VERSION;report.internal_before=0;report.internal_after=0;report.max_internal_displacement=0.0
	for cell in world.cells:
		var chem=cell.chemistry;report.internal_before+=chem.particles.size()
		# The archived chemistry migration already bounds food/waste carriers.
		# Never apply the retired catalyst/substrate reducers to this new model.
		report.internal_after+=chem.particles.size()
	return report
