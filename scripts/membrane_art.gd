extends RefCounted
## Explicit radial mesh follows the actual star-shaped membrane, including dents.
## Rings give the shader an exact boundary coordinate without triangulating polygons.
const RINGS := [0.76,0.90,1.0,1.42]
static func arrays(outline: PackedVector2Array) -> Array:
	var points := PackedVector2Array([Vector2.ZERO])
	var uv := PackedVector2Array([Vector2.ZERO])
	var colors := PackedColorArray([Color(0.5,0.5,0,1)])
	var indices := PackedInt32Array()
	var n := outline.size()
	for radius in RINGS:
		for point in outline:
			points.append(point*radius)
			uv.append(Vector2(radius,0))
			var direction := point.normalized()
			colors.append(Color(direction.x*0.5+0.5,direction.y*0.5+0.5,0,1))
	for i in n:
		var next := (i+1)%n
		indices.append_array(PackedInt32Array([0,1+i,1+next]))
		for ring in range(1,RINGS.size()):
			var a := 1+(ring-1)*n+i
			var b := 1+(ring-1)*n+next
			var c := 1+ring*n+i
			var d := 1+ring*n+next
			indices.append_array(PackedInt32Array([a,c,d,a,d,b]))
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = points
	result[Mesh.ARRAY_TEX_UV] = uv
	result[Mesh.ARRAY_COLOR] = colors
	result[Mesh.ARRAY_INDEX] = indices
	return result
static func mesh(outline: PackedVector2Array) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays(outline))
	return result
