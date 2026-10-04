extends RefCounted
## Uniform grid for local chemical/receptor queries. Stable insertion order.
var buckets: Dictionary = {}
const SIZE := 64.0
const COLS := 64
const ROWS := 40

func key_for(p: Vector2) -> Vector2i:
	var cell := Vector2i((p / SIZE).floor())
	return Vector2i(posmod(cell.x,COLS), posmod(cell.y,ROWS))

func rebuild(particles: Array) -> void:
	buckets.clear()
	for i in particles.size():
		var key := key_for(particles[i].p)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)

func query(position: Vector2, radius: float) -> Array[int]:
	var found: Array[int] = []
	var lo := Vector2i(((position - Vector2.ONE * radius) / SIZE).floor())
	var hi := Vector2i(((position + Vector2.ONE * radius) / SIZE).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var key := Vector2i(posmod(x,COLS),posmod(y,ROWS))
			if buckets.has(key):
				for index in buckets[key]:
					found.append(index)
	return found
