extends RefCounted
## Conservative membrane AABBs including interpolation sweep, on the same torus.
const Medium = preload("res://scripts/medium.gd")
const SIZE := 128.0
const COLS := 32
const ROWS := 20
var buckets: Dictionary = {}
func rebuild(cells: Array) -> void:
	buckets.clear()
	for i in cells.size():
		var cell = cells[i]
		if cell.dead: continue
		var travel := Medium.offset(cell.previous_position,cell.position)
		var center: Vector2 = cell.previous_position+travel*0.5
		var half: Vector2 = travel.abs()*0.5+Vector2.ONE*(cell.extent()+12)
		var lo := Vector2i(((center-half)/SIZE).floor())
		var hi := Vector2i(((center+half)/SIZE).floor())
		for y in range(lo.y,mini(hi.y+1,lo.y+ROWS)):
			for x in range(lo.x,mini(hi.x+1,lo.x+COLS)):
				var key := Vector2i(posmod(x,COLS),posmod(y,ROWS))
				if not buckets.has(key): buckets[key] = []
				buckets[key].append(i)
func at(p: Vector2) -> Array:
	return buckets.get(Vector2i(posmod(floori(p.x/SIZE),COLS),posmod(floori(p.y/SIZE),ROWS)),[])
