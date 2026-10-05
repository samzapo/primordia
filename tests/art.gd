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
