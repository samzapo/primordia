extends RefCounted
## Authored vector paths; raster textures and mipmaps are generated once at runtime.
## Every glyph faces +X, the same axis used by Simulation's binding direction.
const NAMES := ["Nutrient", "Oxygen", "Waste", "Cell trace", "Toxin", "Carbon", "Enzyme", "Antitoxin", "Acid", "Buffer", "Decoy"]
const GLYPHS := [
	{"color":"8de86c", "shade":"368d67", "path":"M -28 0 H -6 L 24 -21 M -6 0 L 24 21", "tips":"M 23 -21 H 26 M 23 21 H 26"},
	{"color":"55ddec", "shade":"278cb9", "path":"M -23 0 H 25", "lobes":"<circle cx='-20' cy='0' r='15'/><circle cx='23' cy='0' r='11'/>", "tips":"M 23 -2 H 27"},
	{"color":"ae80ce", "shade":"67458d", "path":"M -28 -16 L -12 16 L 7 -14 L 27 4", "tips":"M 25 2 L 28 5"},
	{"color":"ff869b", "shade":"b7467b", "path":"M -25 -19 L -3 0 L -25 19 M -3 0 H 29", "tips":"M 26 0 H 30"},
	{"color":"ff779b", "shade":"b34379", "path":"M -28 0 H 29 M -8 0 L 18 -23 M -8 0 L 18 23", "tips":"M 25 0 H 29"},
	{"color":"e8bd84", "shade":"a87960", "path":"M -26 -19 L -8 0 L -26 19 M -8 0 H 24", "lobes":"<circle cx='22' cy='0' r='12'/>", "tips":"M 22 -2 H 27"},
	{"color":"e1db64", "shade":"8b9951", "path":"M -25 -23 V 23 M -25 -23 H 23 M -25 0 H 13 M -25 23 H 23", "tips":"M 21 -23 H 25 M 21 23 H 25"},
	{"color":"63b6ff", "shade":"5c62c8", "path":"M -29 0 H -12 L 7 -21 H 24 M -12 0 L 7 21 H 24", "tips":"M 22 -21 H 26 M 22 21 H 26"},
	{"color":"ff82bf", "shade":"bb4587", "path":"M -27 17 L -8 0 H 28 M -8 0 V -24", "tips":"M 25 0 H 29"},
	{"color":"63e9c9", "shade":"3298af", "path":"M 24 -22 H -8 Q -29 -22 -29 0 Q -29 22 -8 22 H 24", "tips":"M 21 -22 H 25 M 21 22 H 25"},
	{"color":"d783f3", "shade":"8551bd", "path":"M -29 0 H 28 M -16 0 V -23 M 0 0 V 20", "tips":"M 25 0 H 29"}
]
static var _textures: Array[Texture2D] = []

static func texture(kind: int) -> Texture2D:
	if _textures.is_empty():
		for glyph in GLYPHS:
			var image := Image.new()
			var error := image.load_svg_from_string(_svg(glyph))
			assert(error == OK, "Particle vector artwork failed to load")
			image.generate_mipmaps()
			_textures.append(ImageTexture.create_from_image(image))
	return _textures[kind]

static func _svg(glyph: Dictionary) -> String:
	# A dark underside, saturated body and short bright front make rotation legible.
	# Decorative branches do not add extra reaction sites or collision geometry.
	var path := "<path d='%s' fill='none'/>" % glyph.path
	var lobes: String = glyph.get("lobes", "")
	return """<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="-48 -48 96 96">
<g stroke-linecap="round" stroke-linejoin="round">
<g transform="translate(0 3)" stroke="#%s" fill="#%s" stroke-width="17">%s%s</g>
<g stroke="#%s" fill="#%s" stroke-width="13">%s%s</g>
<path d="%s" fill="none" stroke="#fff4d3" stroke-width="8"/>
</g></svg>""" % [glyph.shade,glyph.shade,path,lobes,glyph.color,glyph.color,path,lobes,glyph.tips]
