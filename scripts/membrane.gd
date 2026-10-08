extends RefCounted
## XPBD ring: compliant edge-length and enclosed-area constraints.
## Coordinates are local to the organism. Render interpolation is separate.
const COUNT := 28
var kernels = preload("res://scripts/backend.gd").create()
var native_constraints := kernels != null
var native_compression := true
var native_outline: bool = kernels != null and kernels.has_method("membrane_outline")
const Network = preload("res://scripts/cytoskeleton.gd")
var skeleton = Network.new()
var maximum_radius := 47.0
var points := PackedVector2Array()
var previous := PackedVector2Array()
var edge_lambda := PackedFloat32Array()
var area_lambda := 0.0
var normals := PackedVector2Array()
var rest_points := PackedVector2Array()
var rest_lengths := PackedFloat32Array()
var gradients := PackedVector2Array()
var arcs := PackedFloat32Array()
var cached_outline := PackedVector2Array()
var geometry_dirty := true
var outline_dirty := true

func _init(radius: float = 47.0, anatomy_seed: int = -1) -> void:
	maximum_radius = radius
	for i in COUNT:
		normals.append(Vector2.from_angle(TAU*i/COUNT))
		points.append(normals[i]*radius)
	previous = points.duplicate()
	edge_lambda.resize(COUNT)
	rest_points.resize(COUNT)
	rest_lengths.resize(COUNT)
	gradients.resize(COUNT)
	arcs.resize(COUNT+1)
	if anatomy_seed >= 0: skeleton.seed_layout(anatomy_seed,self,radius)

func step(dt: float, radius: float, acceleration: Vector2, time: float, _aspect: float = 1.0, traction: PackedVector2Array = PackedVector2Array()) -> void:
	if dt < 0.000001: return
	invalidate()
	# A soft, actively contracting cortex has changing local rest lengths, not
	# an elliptical template. Area pressure and weak tensile chords resist it.
	for i in COUNT:
		var a := TAU*i/COUNT
		var contraction := (1.0+0.14*sin(a*3+time*0.48)+0.075*sin(a*5-time*0.71))/1.006
		rest_points[i] = normals[i]*radius*contraction
	for i in COUNT: rest_lengths[i] = rest_points[i].distance_to(rest_points[(i+1)%COUNT])
	for i in COUNT:
		var p := points[i]
		var motion := (p-previous[i])*0.84
		previous[i] = p
		points[i] += motion+(rest_points[i]-p)*dt*0.85-acceleration*dt*dt*0.18
		if traction.size() == COUNT: points[i] += traction[i]*dt*dt*22.0
	skeleton.begin(radius)
	edge_lambda.fill(0)
	area_lambda = 0
	var edge_alpha := 0.0008/(dt*dt)
	var area_alpha := 0.00001/(dt*dt)
	for iteration in 6:
		if native_constraints:
			var solved: Array = kernels.membrane_edges(points,rest_lengths,edge_lambda,edge_alpha)
			points = solved[0]
			edge_lambda = solved[1]
		else:
			for i in COUNT:
				var j := (i+1)%COUNT
				var delta := points[j]-points[i]
				var length := delta.length()
				if length < 0.0001: continue
				var dl := (-(length-rest_lengths[i])-edge_alpha*edge_lambda[i])/(2+edge_alpha)
				edge_lambda[i] += dl
				points[i] -= delta/length*dl
				points[j] += delta/length*dl
		skeleton.solve(self,dt,radius)
		if native_constraints:
			var solved: Array = kernels.membrane_area(points,area_lambda,area_alpha,COUNT*radius*radius*sin(TAU/COUNT)*0.5)
			points = solved[0]
			area_lambda = solved[1]
		else:
			var denominator := area_alpha
			var area := 0.0
			for i in COUNT:
				var next := points[(i+1)%COUNT]
				var prev := points[posmod(i-1,COUNT)]
				area += points[i].cross(next)*0.5
				gradients[i] = Vector2(next.y-prev.y,prev.x-next.x)*0.5
				denominator += gradients[i].length_squared()
			var target := COUNT*radius*radius*sin(TAU/COUNT)*0.5
			var dl := (-(area-target)-area_alpha*area_lambda)/maxf(denominator,0.0001)
			area_lambda += dl
			for i in COUNT: points[i] += gradients[i]*dl
	# Ordered polar sectors prevent folded edges and invalid render polygons
	# during compression. This is explicit numerical stabilization of the gel.
	for i in COUNT:
		var nominal := TAU*i/COUNT
		var point := points[i]
		if not point.is_finite(): point = rest_points[i]
		var angle := nominal+clampf(wrapf(point.angle()-nominal,-PI,PI),-TAU/COUNT*0.38,TAU/COUNT*0.38)
		var safe := Vector2.from_angle(angle)*clampf(point.length(),radius*0.58,radius*1.48)
		previous[i] += safe-points[i] if points[i].is_finite() else Vector2.ZERO
		if not previous[i].is_finite(): previous[i] = safe
		points[i] = safe

	# Bending resistance removes node-scale wrinkles without imposing an ellipse.
	var lengths := PackedFloat32Array()
	for point in points: lengths.append(point.length())
	for i in COUNT:
		var length := lengths[i]*0.6+(lengths[posmod(i-1,COUNT)]+lengths[(i+1)%COUNT])*0.2
		var corrected := points[i].normalized()*length
		previous[i] += corrected-points[i]
		points[i] = corrected
	var enclosed := 0.0
	for i in COUNT: enclosed += points[i].cross(points[(i+1)%COUNT])*0.5
	var pressure_scale := sqrt(COUNT*radius*radius*sin(TAU/COUNT)*0.5/maxf(0.001,enclosed))
	maximum_radius = 0.0
	for i in COUNT:
		var corrected := points[i]*pressure_scale
		maximum_radius = maxf(maximum_radius,corrected.length())
		previous[i] += corrected-points[i]
		points[i] = corrected

func compress(local_angle: float, depth: float, radius: float) -> void:
	if native_constraints and native_compression:
		var solved: Array = kernels.membrane_compress(points,previous,local_angle,depth,radius)
		points = solved[0]
		previous = solved[1]
		maximum_radius = solved[2]
		invalidate()
		return
	# Spread dents across nodes, redistribute area, preserve polar ordering and
	# shift Verlet history so positional correction creates no launch velocity.
	var before_area := 0.0
	for i in COUNT: before_area += points[i].cross(points[(i+1)%COUNT])*0.5
	for i in COUNT:
		var distance := absf(wrapf(points[i].angle()-local_angle,-PI,PI))
		if distance >= 0.65: continue
		var weight := 0.5+0.5*cos(PI*distance/0.65)
		var corrected := points[i].normalized()*maxf(radius*0.58,points[i].length()-depth*weight)
		previous[i] += corrected-points[i]
		points[i] = corrected
	var area := 0.0
	for i in COUNT: area += points[i].cross(points[(i+1)%COUNT])*0.5
	var scale := sqrt(maxf(0.001,before_area)/maxf(0.001,area))
	maximum_radius = 0
	for i in COUNT:
		var corrected := points[i]*scale
		previous[i] += corrected-points[i]
		points[i] = corrected
		maximum_radius = maxf(maximum_radius,corrected.length())
	invalidate()

func invalidate() -> void:
	geometry_dirty = true
	outline_dirty = true

func refresh_arcs() -> void:
	if not geometry_dirty: return
	arcs[0] = 0
	for i in COUNT: arcs[i+1] = arcs[i]+points[i].distance_to(points[(i+1)%COUNT])
	geometry_dirty = false

func outline() -> PackedVector2Array:
	if not outline_dirty: return cached_outline
	if native_outline:
		cached_outline = kernels.membrane_outline(points)
		outline_dirty = false
		return cached_outline
	var curve := PackedVector2Array()
	# Interpolate positive radii across ordered angles. Cartesian Catmull-Rom
	# can loop after contact compression and trigger CanvasItem triangulation
	# failures; this radial spline cannot cross itself or cross the nucleus.
	for i in COUNT:
		var before := points[posmod(i-1,COUNT)].length()
		var start := points[i].length()
		var end := points[(i+1)%COUNT].length()
		var after := points[(i+2)%COUNT].length()
		var angle := points[i].angle()
		var angle_delta := fposmod(points[(i+1)%COUNT].angle()-angle,TAU)
		for j in 4:
			var t := j/4.0
			var radius := 0.5*((2*start)+(-before+end)*t+(2*before-5*start+4*end-after)*t*t+(-before+3*start-3*end+after)*t*t*t)
			radius = clampf(radius,maxf(0.1,minf(start,end)*0.95),maxf(start,end)*1.05)
			curve.append(Vector2.from_angle(angle+angle_delta*t)*radius)
	cached_outline = curve
	outline_dirty = false
	return cached_outline
