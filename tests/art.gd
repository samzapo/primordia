extends RefCounted
const Art = preload("res://scripts/cell_art.gd")
const Particles = preload("res://scripts/particle_art.gd")
static func run(check: Callable) -> void:
	# Prevent the invalid-polygon regression for every procedural nucleus family.
	for form in 3:
		for phase in [0.0,0.7,2.3,4.1,5.8]:
			var points := Art.nucleus_outline(form,phase)
			check.call(Geometry2D.triangulate_polygon(points).size() == (points.size()-2)*3,"Procedural nucleus is a valid simple polygon")
	# Both texture levels must remain within the chemistry's circular envelope.
	for kind in Particles.GLYPHS.size():
		for small in [false,true]:
			var glyph: Dictionary = Particles.GLYPHS[kind].duplicate()
			if small: glyph.path = Particles.SIMPLE_PATHS[kind]
			var image := Image.new()
			check.call(image.load_svg_from_string(Particles._svg(glyph,small)) == OK,"Detailed and simplified chemistry glyphs rasterize")
			var inside := true
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x,y).a > 0.1 and Vector2(x+0.5-48,y+0.5-48).length() > 48: inside = false
			check.call(inside,"Chemistry artwork fits the circular contact envelope")

	# Every depth surface ring follows the real outline, including compressed lobes.
	var Surface = preload("res://scripts/membrane_art.gd")
	var membrane = preload("res://scripts/membrane.gd").new(55)
	for i in 180:
		if i%7 == 0: membrane.points[i%membrane.COUNT] *= 0.2
		membrane.step(1.0/60,55,Vector2(240*sin(i),100*cos(i)),i/60.0)
	for scale in [1.0,30.0]:
		var outline: PackedVector2Array = membrane.outline()
		outline = Transform2D(0,Vector2.ONE*scale,0,Vector2.ZERO)*outline
		var arrays: Array = Surface.arrays(outline)
		var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var finite := true
		var matches := true
		for v in vertices: finite = finite and v.is_finite()
		for i in outline.size():
			var boundary := 1+2*outline.size()+i
			matches = matches and vertices[boundary].is_equal_approx(outline[i]) and uv[boundary].x == 1
		for i in indices: finite = finite and i >= 0 and i < vertices.size()
		check.call(finite and indices.size()%3 == 0,"Membrane shading mesh stays finite and indexed under compression and growth")
		check.call(matches,"Shaded boundary exactly matches the deformed membrane, rather than a circle proxy")
	var Flow = preload("res://scripts/flow_view.gd")
	var camera := Vector2(4030,2510)
	for half in [Vector2(632,395),Vector2(1264,395),Vector2(4000,2500)]:
		var a: Dictionary = Flow.seeds(camera,half)
		var b: Dictionary = Flow.seeds(camera+preload("res://scripts/medium.gd").WORLD,half)
		check.call(a.data.size() <= Flow.MAX_STREAMERS and a.data == b.data,"Flow seeds stay bounded and identical across toroidal seams")
	var habitat = preload("res://scripts/habitat.gd").new(41)
	var anchors: Array[Color] = Flow.anchors(habitat)
	check.call(anchors.size() <= Flow.MAX_WAKE_ANCHORS and anchors.size() > 0,"Plant disturbance batch samples a bounded set of stout stems")
	var medium = preload("res://scripts/medium.gd").new()
	var image := Image.create_from_data(medium.COLS,medium.ROWS,false,Image.FORMAT_RGF,medium.velocity.to_byte_array())
	var v: Vector2 = medium.velocity[11*medium.COLS+23]
	var pixel := image.get_pixel(23,11)
	check.call(Vector2(pixel.r,pixel.g).is_equal_approx(v),"GPU flow texture preserves signed field velocities without quantization")
