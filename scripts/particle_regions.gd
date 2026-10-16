extends RefCounted
## Authoritative sparse cold storage. No per-frame scan of the stored world.
const SIZE:=256.0
var dimensions:=Vector2i.ZERO # Zero: unbounded chunk coordinates.
var chunks: Dictionary={}
var due: Array=[] # Min heap of [time, serial, key].
var positions: Dictionary={} # One heap entry per stored chunk.
var serial:=0
var count:=0
var living:=0
var signals:=0
var visits:=0
var kernels # Optional batched partitioning; owns no second copy of packet state.

func key(at: Vector2) -> Vector2i:
	var k:=Vector2i((at/SIZE).floor())
	return Vector2i(posmod(k.x,dimensions.x),posmod(k.y,dimensions.y)) if dimensions!=Vector2i.ZERO else k

func _less(a: Array,b: Array) -> bool:
	return a[0]<b[0] or (a[0]==b[0] and a[1]<b[1])

func _swap(a: int,b: int) -> void:
	var item=due[a];due[a]=due[b];due[b]=item
	positions[due[a][2]]=a;positions[due[b][2]]=b

func _repair(index: int) -> void:
	var i:=index
	while i>0:
		var parent: int=(i-1)/2
		if not _less(due[i],due[parent]): break
		_swap(i,parent);i=parent
	while i*2+1<due.size():
		var child:=i*2+1
		if child+1<due.size() and _less(due[child+1],due[child]): child+=1
		if not _less(due[child],due[i]): break
		_swap(i,child);i=child

func _push(item: Array) -> void:
	assert(not positions.has(item[2]))
	positions[item[2]]=due.size();due.append(item);_repair(due.size()-1)

func _remove(k: Vector2i) -> void:
	if not positions.has(k): return
	var i: int=positions[k]
	positions.erase(k)
	var last=due.pop_back()
	if i<due.size():
		due[i]=last;positions[last[2]]=i;_repair(i)

func _pop() -> Array:
	var result: Array=due[0]
	_remove(result[2]);return result

func put(packet: Dictionary, now: float) -> void:
	if not packet.alive: return
	var k:=key(packet.p)
	if not chunks.has(k):
		serial+=1
		chunks[k]={"packets":[],"head":0,"serial":serial,"key":k,"transport_due":now+.5,"chemical_due":INF,"living":0,"signals":0}
		_push([now+.5,serial,k])
	chunks[k].packets.append(packet);count+=1;living+=1;chunks[k].living+=1
	if packet.get("kind",-1)==3:signals+=1;chunks[k].signals+=1
	chunks[k].transport_due=minf(chunks[k].transport_due,packet.get("transport_at",now)+.5)
	if packet.get("kind",0)!=3: chunks[k].chemical_due=minf(chunks[k].chemical_due,packet.get("chemical_at",now)+.5)

func put_all(packets: Array,now: float) -> void:
	if kernels!=null and kernels.has_method("packet_regions"):
		for chunk in kernels.packet_regions(packets,now,dimensions): restore(chunk,now)
	else:
		for packet in packets: put(packet,now)

func keys_in(at: Vector2,half: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i]=[]
	var lo:=Vector2i(((at-half)/SIZE).floor())
	var hi:=Vector2i(((at+half)/SIZE).floor())
	for x in range(lo.x,mini(hi.x+1,lo.x+dimensions.x) if dimensions.x>0 else hi.x+1):
		for y in range(lo.y,mini(hi.y+1,lo.y+dimensions.y) if dimensions.y>0 else hi.y+1):
			var k:=Vector2i(posmod(x,dimensions.x),posmod(y,dimensions.y)) if dimensions!=Vector2i.ZERO else Vector2i(x,y)
			if chunks.has(k): result.append(k)
	return result

func take(k: Vector2i,limit: int=2147483647) -> Array:
	if not chunks.has(k): return []
	var chunk: Dictionary=chunks[k]
	var end: int=mini(chunk.packets.size(),chunk.head+limit)
	var result: Array=chunk.packets.slice(chunk.head,end)
	count-=result.size();chunk.head=end
	for packet in result:
		if packet.alive:
			living-=1;chunk.living-=1
			if packet.get("kind",-1)==3:signals-=1;chunk.signals-=1
	if end==chunk.packets.size(): chunks.erase(k);_remove(k)
	elif end>=1024 and end*2>=chunk.packets.size():
		chunk.packets=chunk.packets.slice(end);chunk.head=0
	return result

func borrow_region(at: Vector2,half: Vector2) -> Array:
	var result: Array=[]
	for k in keys_in(at,half):
		var chunk: Dictionary=chunks[k]
		if chunk.head>0: chunk.packets=chunk.packets.slice(chunk.head);chunk.head=0
		count-=chunk.packets.size();living-=chunk.living;signals-=chunk.signals;chunks.erase(k);_remove(k)
		result.append(chunk)
	return result

func restore(chunk: Dictionary,now: float) -> void:
	if chunk.packets.is_empty(): return
	var k: Vector2i=chunk.key
	chunk.living=0;chunk.signals=0
	for packet in chunk.packets:
		if packet.alive:
			chunk.living+=1
			if packet.get("kind",-1)==3:chunk.signals+=1
	living+=chunk.living;signals+=chunk.signals
	if chunks.has(k):
		var held: Dictionary=chunks[k]
		held.packets.append_array(chunk.packets);held.living+=chunk.living;held.signals+=chunk.signals
		held.transport_due=minf(held.transport_due,chunk.transport_due)
		held.chemical_due=minf(held.chemical_due,chunk.chemical_due)
		var index: int=positions[k]
		if held.transport_due<due[index][0]:
			due[index][0]=maxf(now,held.transport_due);_repair(index)
	else:
		serial+=1;chunk.serial=serial;chunk.head=0;chunks[k]=chunk
		_push([maxf(now,chunk.transport_due),serial,k])
	count+=chunk.packets.size()

func take_region(at: Vector2,half: Vector2,limit: int) -> Array:
	var result: Array=[]
	for k in keys_in(at,half):
		result.append_array(take(k,limit-result.size()))
		if result.size()>=limit: break
	return result

func take_due(now: float,limit: int=256,max_visits: int=8) -> Array:
	visits=0
	while not due.is_empty() and due[0][0]<=now and visits<max_visits:
		var entry:=_pop();visits+=1
		var k: Vector2i=entry[2]
		if not chunks.has(k) or chunks[k].serial!=entry[1]: continue
		var result:=take(k,limit)
		if chunks.has(k): _push([now+.5,entry[1],k])
		return result
	return []

func snapshots() -> Array:
	# Explicit save/diagnostic only, never called by a simulation tick.
	var result: Array=[]
	for chunk in chunks.values(): result.append_array(chunk.packets.slice(chunk.head).duplicate(true))
	return result

func thin(probability: float,random: RandomNumberGenerator) -> Dictionary:
	var budget=preload("res://scripts/particle_budget.gd")
	var result: Dictionary={"removed":0,"loss":0.0,"fuel_loss":0.0}
	for k in chunks.keys():
		var chunk: Dictionary=chunks[k]
		var packets: Array=chunk.packets.slice(chunk.head)
		budget.add(result,budget.thin(packets,probability,random))
		count-=packets.size();living-=chunk.living;signals-=chunk.signals
		var kept: Array=packets.filter(func(packet):return packet.alive)
		if kept.is_empty():chunks.erase(k);_remove(k);continue
		chunk.packets=kept;chunk.head=0;chunk.living=kept.size()
		chunk.signals=kept.filter(func(packet):return packet.get("kind",-1)==3).size()
		count+=kept.size();living+=chunk.living;signals+=chunk.signals
	return result
