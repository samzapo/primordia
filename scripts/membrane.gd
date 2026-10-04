extends RefCounted
## XPBD ring: compliant edge-length and enclosed-area constraints.
## Coordinates are local to the organism. Render interpolation is separate.
const COUNT := 28
var points := PackedVector2Array()
var previous := PackedVector2Array()
var edge_lambda := PackedFloat32Array()
var area_lambda := 0.0

func _init(radius: float = 47.0) -> void:
	for i in COUNT:
		points.append(Vector2.from_angle(TAU * i / COUNT) * radius)
	previous = points.duplicate()
	edge_lambda.resize(COUNT)

func step(dt: float, radius: float, acceleration: Vector2, time: float, aspect: float = 1.0) -> void:
	for i in COUNT:
		var p := points[i]
		var rest := Vector2.from_angle(TAU * i / COUNT) * radius * Vector2(aspect, 1.0/aspect)
		var motion := (p - previous[i]) * 0.91
		previous[i] = p
		# Weak shape recovery keeps the unconstrained ring from folding over.
		points[i] += motion + (rest - p) * dt * 1.6 - acceleration * dt * dt * 0.22
		points[i] += rest.normalized() * sin(time * 2.1 + i * 0.9) * dt * 0.7
	edge_lambda.fill(0.0)
	area_lambda = 0.0
	var edge_alpha := 0.00002 / (dt * dt)
	var area_alpha := 0.00001 / (dt * dt)
	for iteration in 6:
		for i in COUNT:
			var j := (i + 1) % COUNT
			var delta := points[j] - points[i]
			var length := delta.length()
			if length < 0.0001:
				continue
			var rest_a := Vector2.from_angle(TAU*i/COUNT)*radius*Vector2(aspect,1.0/aspect)
			var rest_b := Vector2.from_angle(TAU*j/COUNT)*radius*Vector2(aspect,1.0/aspect)
			var rest_length := rest_a.distance_to(rest_b)
			var dl := (-(length - rest_length) - edge_alpha * edge_lambda[i]) / (2.0 + edge_alpha)
			edge_lambda[i] += dl
			points[i] -= delta / length * dl
			points[j] += delta / length * dl
		# Internal microtubule-inspired tensile chords oppose hydrostatic pressure.
		for ends in [[0,14], [7,21], [3,17], [10,24]]:
			var i: int = ends[0]
			var j: int = ends[1]
			var rest_a := Vector2.from_angle(TAU*i/COUNT)*radius*Vector2(aspect,1.0/aspect)
			var rest_b := Vector2.from_angle(TAU*j/COUNT)*radius*Vector2(aspect,1.0/aspect)
			var delta := points[j]-points[i]
			var extension := delta.length()-rest_a.distance_to(rest_b)
			if extension > 0:
				var correction := delta.normalized()*extension*0.24
				points[i] += correction
				points[j] -= correction
		var gradients := PackedVector2Array()
		var denominator := area_alpha
		var area := 0.0
		for i in COUNT:
			var next := points[(i + 1) % COUNT]
			var prev := points[posmod(i - 1, COUNT)]
			area += points[i].cross(next) * 0.5
			var gradient := Vector2(next.y - prev.y, prev.x - next.x) * 0.5
			gradients.append(gradient)
			denominator += gradient.length_squared()
		var target := COUNT * radius * radius * sin(TAU / COUNT) * 0.5
		var dl := (-(area - target) - area_alpha * area_lambda) / denominator
		area_lambda += dl
		for i in COUNT:
			points[i] += gradients[i] * dl
	var center := Vector2.ZERO
	for point in points:
		center += point / COUNT
	for i in COUNT:
		points[i] -= center
		previous[i] -= center

func outline() -> PackedVector2Array:
	var curve := PackedVector2Array()
	for i in COUNT:
		var a := points[posmod(i - 1, COUNT)]
		var b := points[i]
		var c := points[(i + 1) % COUNT]
		var d := points[(i + 2) % COUNT]
		for j in 4:
			var t := j / 4.0
			curve.append(0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t*t + (-a + 3.0*b - 3.0*c + d) * t*t*t))
	return curve
