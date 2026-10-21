extends RefCounted
## Explicit radial mesh follows the actual star-shaped membrane, including dents.
## Rings give the shader an exact boundary coordinate without triangulating polygons.
const RINGS := [0.76,0.90,1.0,1.95]
static var topologies: Dictionary={}
static var kernels = preload("res://scripts/backend.gd").create()
static func arrays(outline: PackedVector2Array, native: bool = true) -> Array:
	if native and kernels != null: return kernels.membrane_mesh(outline)
	var n:=outline.size()
	var points:=PackedVector2Array();points.resize(1+RINGS.size()*n)
	var colors:=PackedColorArray();colors.resize(points.size());colors[0]=Color(.5,.5,0,1)
	var directions:=PackedColorArray();directions.resize(n)
	for i in n:
		var direction:=outline[i].normalized()
		directions[i]=Color(direction.x*.5+.5,direction.y*.5+.5,0,1)
	for ring in RINGS.size():
		for i in n:
			points[1+ring*n+i]=outline[i]*RINGS[ring]
			colors[1+ring*n+i]=directions[i]
	if not topologies.has(n):
		var uv:=PackedVector2Array();uv.resize(points.size())
		for ring in RINGS.size():
			for i in n:uv[1+ring*n+i]=Vector2(RINGS[ring],0)
		var indices:=PackedInt32Array();indices.resize(n*(3+6*(RINGS.size()-1)))
		var at:=0
		for i in n:
			var next: int=(i+1)%n
			for value in [0,1+i,1+next]:indices[at]=value;at+=1
			for ring in range(1,RINGS.size()):
				var a:=1+(ring-1)*n+i;var b:=1+(ring-1)*n+next
				var c:=1+ring*n+i;var d:=1+ring*n+next
				for value in [a,c,d,a,d,b]:indices[at]=value;at+=1
		topologies[n]={"uv":uv,"indices":indices}
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = points
	result[Mesh.ARRAY_TEX_UV] = topologies[n].uv
	result[Mesh.ARRAY_COLOR] = colors
	result[Mesh.ARRAY_INDEX] = topologies[n].indices
	return result
static func mesh(outline: PackedVector2Array, native: bool = true) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays(outline,native))
	return result
