extends RefCounted
## Uniform grid for local chemical/receptor queries. Stable insertion order.
var buckets: Dictionary = {}
var native = null
var native_enabled := true
var source_size := 0
var size := 64.0
var cols := 64
var rows := 40

func _init(cell_size: float = 64.0) -> void:
	size = cell_size
	cols = roundi(4096/size)
	rows = roundi(2560/size)
	if OS.get_environment("PRIMORDIA_BACKEND") != "script" and preload("res://scripts/backend.gd").native_available():
		native = ClassDB.instantiate("PrimordiaGrid")
		native.configure(size)

func key_for(p: Vector2) -> Vector2i:
	var cell := Vector2i((p / size).floor())
	return Vector2i(posmod(cell.x,cols), posmod(cell.y,rows))

func rebuild(particles: Array) -> void:
	if native != null and native_enabled:
		native.rebuild(particles)
		source_size = particles.size()
		return
	buckets.clear()
	source_size = 0
	for i in particles.size(): insert(i,particles[i].p)

func insert(i: int, p: Vector2) -> void:
	if native != null and native_enabled:
		native.insert(i,p)
		source_size = maxi(source_size,i+1)
		return
	var key := key_for(p)
	if not buckets.has(key): buckets[key] = []
	buckets[key].append(i)
	source_size = maxi(source_size,i+1)

func move(i: int, old: Vector2, p: Vector2) -> void:
	if native != null and native_enabled:
		native.move(i,old,p)
		return
	var from := key_for(old)
	var to := key_for(p)
	if from == to: return
	if buckets.has(from): buckets[from].erase(i)
	if not buckets.has(to): buckets[to] = []
	buckets[to].append(i)

func query(position: Vector2, radius: float) -> Array[int]:
	return query_rect(position,Vector2.ONE*radius)

func query_rect(position: Vector2, half_extent: Vector2) -> Array[int]:
	if native != null and native_enabled: return native.query_rect(position,half_extent)
	var found: Array[int] = []
	var lo := Vector2i(((position-half_extent)/size).floor())
	var hi := Vector2i(((position+half_extent)/size).floor())
	for x in range(lo.x,mini(hi.x+1,lo.x+cols)):
		for y in range(lo.y,mini(hi.y+1,lo.y+rows)):
			var key := Vector2i(posmod(x,cols),posmod(y,rows))
			if buckets.has(key): found.append_array(buckets[key])
	return found

func clear() -> void:
	buckets.clear()
	source_size = 0
	if native != null: native.clear()
