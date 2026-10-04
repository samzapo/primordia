extends RefCounted
## Uniform grid for local chemical/receptor queries. Stable insertion order.
var buckets: Dictionary = {}
const SIZE := 80.0

func rebuild(particles: Array) -> void:
	buckets.clear()
	for i in particles.size():
		var key := Vector2i((particles[i].p / SIZE).floor())
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)

func query(position: Vector2, radius: float) -> Array[int]:
	var found: Array[int] = []
	var lo := Vector2i(((position - Vector2.ONE * radius) / SIZE).floor())
	var hi := Vector2i(((position + Vector2.ONE * radius) / SIZE).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var key := Vector2i(x, y)
			if buckets.has(key):
				for index in buckets[key]:
					found.append(index)
	return found
