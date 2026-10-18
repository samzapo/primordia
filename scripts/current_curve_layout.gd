extends RefCounted
## Presentation-only admission. Keep whole curves; omit conflicting samples.
var bins: Dictionary={}
var segments: Array=[]
var gap:=1.0
const BIN:=64.0
func _init(clearance: float) -> void:gap=clearance
func cells(a: Vector2,b: Vector2) -> Array[Vector2i]:
	var low:=Vector2i(((a.min(b)-Vector2.ONE*gap)/BIN).floor())
	var high:=Vector2i(((a.max(b)+Vector2.ONE*gap)/BIN).floor())
	var result: Array[Vector2i]=[]
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):result.append(Vector2i(x,y))
	return result
func close(a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> bool:
	if Geometry2D.segment_intersects_segment(a,b,c,d)!=null:return true
	return a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d))<gap or b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d))<gap or c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b))<gap or d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))<gap
func accept(points: PackedVector2Array) -> bool:
	for i in range(1,points.size()):
		var a:=points[i-1];var b:=points[i]
		if not a.is_finite() or not b.is_finite():return false
		for j in range(1,i-1):
			if Geometry2D.segment_intersects_segment(a,b,points[j-1],points[j])!=null:return false
		var seen: Dictionary={}
		for cell in cells(a,b):
			for index in bins.get(cell,[]):
				if seen.has(index):continue
				seen[index]=true
				var other: PackedVector2Array=segments[index]
				if close(a,b,other[0],other[1]):return false
	for i in range(1,points.size()):
		var index:=segments.size()
		segments.append(PackedVector2Array([points[i-1],points[i]]))
		for cell in cells(points[i-1],points[i]):
			if not bins.has(cell):bins[cell]=[]
			bins[cell].append(index)
	return true
