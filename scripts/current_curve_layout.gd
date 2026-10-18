extends RefCounted
## Presentation-only admission. Keep whole curves; omit conflicting samples.
var bins: Dictionary={}
var segments: Array=[]
var segment_low:=PackedVector2Array()
var segment_high:=PackedVector2Array()
var owners: Array=[]
var owned: Dictionary={}
var owner_bins: Dictionary={}
var next_group:=-2
var visited:=PackedInt32Array()
var visit_serial:=0
var gap:=1.0
var bin_size:=64.0
func _init(clearance: float) -> void:
	gap=clearance;bin_size=maxf(16.0,2*gap)
func cells(a: Vector2,b: Vector2) -> Array[Vector2i]:
	var low:=Vector2i(((a.min(b)-Vector2.ONE*gap)/bin_size).floor())
	var high:=Vector2i(((a.max(b)+Vector2.ONE*gap)/bin_size).floor())
	var result: Array[Vector2i]=[]
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):result.append(Vector2i(x,y))
	return result
func close(a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> bool:
	if Geometry2D.segment_intersects_segment(a,b,c,d)!=null:return true
	return a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d))<gap or b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d))<gap or c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b))<gap or d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))<gap
func accept(points: PackedVector2Array,owner: int=-1) -> bool:
	var low:=PackedVector2Array();var high:=PackedVector2Array()
	low.resize(points.size());high.resize(points.size())
	for i in range(1,points.size()):
		if not points[i-1].is_finite() or not points[i].is_finite():return false
		low[i]=points[i-1].min(points[i]);high[i]=points[i-1].max(points[i])
	for i in range(1,points.size()):
		var a:=points[i-1];var b:=points[i]
		var own_low: Vector2=low[i]-Vector2.ONE*.00001
		var own_high: Vector2=high[i]+Vector2.ONE*.00001
		for j in range(1,i-1):
			if own_low.x>high[j].x or own_low.y>high[j].y or own_high.x<low[j].x or own_high.y<low[j].y:continue
			if Geometry2D.segment_intersects_segment(a,b,points[j-1],points[j])!=null:return false
		var near_low: Vector2=low[i]-Vector2.ONE*maxf(gap,.00001)
		var near_high: Vector2=high[i]+Vector2.ONE*maxf(gap,.00001)
		visit_serial+=1
		for cell in cells(a,b):
			var bucket: Dictionary=bins.get(cell,{})
			for group in bucket:
				# A replacement never tests against its own previously reserved path.
				if owner>=0 and group==owner:continue
				for index in bucket[group]:
					if visited[index]==visit_serial:continue
					visited[index]=visit_serial
					if near_low.x>segment_high[index].x or near_low.y>segment_high[index].y or near_high.x<segment_low[index].x or near_high.y<segment_low[index].y:continue
					var other: PackedVector2Array=segments[index]
					if close(a,b,other[0],other[1]):return false
	reserve(points,owner)
	return true

func reserve(points: PackedVector2Array,owner: int=-1) -> void:
	# Remove replaced paths from the index rather than scanning dead entries.
	# Previously visible curves still reserve their last safe geometry while fading.
	if owner>=0:
		for cell in owner_bins.get(owner,{}):
			var bucket: Dictionary=bins[cell]
			bucket.erase(owner)
			if bucket.is_empty():bins.erase(cell)
		for index in owned.get(owner,[]):segments[index]=null
		owned[owner]=[]
		owner_bins[owner]={}
	var group:=owner
	if owner<0:group=next_group;next_group-=1
	for i in range(1,points.size()):
		var index:=segments.size()
		segments.append(PackedVector2Array([points[i-1],points[i]]));owners.append(owner);visited.append(0)
		segment_low.append(points[i-1].min(points[i]));segment_high.append(points[i-1].max(points[i]))
		if owner>=0:owned[owner].append(index)
		for cell in cells(points[i-1],points[i]):
			if not bins.has(cell):bins[cell]={}
			if not bins[cell].has(group):bins[cell][group]=[]
			bins[cell][group].append(index)
			if owner>=0:owner_bins[owner][cell]=true
