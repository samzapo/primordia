extends RefCounted
## Authored vector paths; raster textures and mipmaps are generated once at runtime.
## Every glyph faces +X, the same axis used by Simulation's binding direction.
const NAMES := ["Nutrient", "Oxygen", "Waste", "Pheromone", "Toxin", "Carbon", "Enzyme", "Antitoxin", "Acid", "Buffer", "Decoy"]
const GLYPHS := [
	{"color":"91f04c", "shade":"268457", "path":"M -28 0 H -6 L 24 -21 M -6 0 L 24 21", "tips":"M 23 -21 H 26 M 23 21 H 26"},
	{"color":"22d7f2", "shade":"278cb9", "path":"M -23 0 H 25", "lobes":"<circle cx='-20' cy='0' r='15'/><circle cx='23' cy='0' r='11'/>", "tips":"M 23 -2 H 27"},
	{"color":"a955d0", "shade":"67458d", "path":"M -28 -16 L -12 16 L 7 -14 L 27 4", "tips":"M 25 2 L 28 5"},
	{"color":"ffb9cb", "shade":"b7467b", "point":true, "path":"", "tips":""},
	{"color":"ff407b", "shade":"b34379", "path":"M -28 0 H 29 M -8 0 L 18 -23 M -8 0 L 18 23", "tips":"M 25 0 H 29"},
	{"color":"f4a755", "shade":"a87960", "path":"M -26 -19 L -8 0 L -26 19 M -8 0 H 24", "lobes":"<circle cx='22' cy='0' r='12'/>", "tips":"M 22 -2 H 27"},
	{"color":"ffe34a", "shade":"8b9951", "path":"M -25 -23 V 23 M -25 -23 H 23 M -25 0 H 13 M -25 23 H 23", "tips":"M 21 -23 H 25 M 21 23 H 25"},
	{"color":"4094ff", "shade":"5c62c8", "path":"M -29 0 H -12 L 7 -21 H 24 M -12 0 L 7 21 H 24", "tips":"M 22 -21 H 26 M 22 21 H 26"},
	{"color":"f34db1", "shade":"bb4587", "path":"M -27 17 L -8 0 H 28 M -8 0 V -24", "tips":"M 25 0 H 29"},
	{"color":"2ce3bb", "shade":"3298af", "path":"M 24 -22 H -8 Q -29 -22 -29 0 Q -29 22 -8 22 H 24", "tips":"M 21 -22 H 25 M 21 22 H 25"},
	{"color":"ba50ee", "shade":"8551bd", "path":"M -29 0 H 28 M -16 0 V -23 M 0 0 V 20", "tips":"M 25 0 H 29"}
]
static var _textures: Array[Texture2D] = []
static var _small_textures: Array[Texture2D] = []
const SIMPLE_PATHS := [
	"M -27 0 H -5 L 25 -19 M -5 0 L 25 19",
	"M -24 0 H 26",
	"M -25 -13 L -9 13 L 9 -13 L 26 4",
	"M -24 -18 L -4 0 L -24 18 M -4 0 H 27",
	"M -27 0 H 27 M -5 0 L 17 -20 M -5 0 L 17 20",
	"M -25 -17 L -7 0 L -25 17 M -7 0 H 25",
	"M 24 -21 H -24 V 21 H 24 M -24 0 H 12",
	"M -27 0 H -10 L 9 -20 H 25 M -10 0 L 9 20 H 25",
	"M -25 15 L -7 0 H 27 M -7 0 V -23",
	"M 24 -21 H -8 Q -28 -21 -28 0 Q -28 21 -8 21 H 24",
	"M -27 0 H 27 M -14 0 V -21 M 2 0 V 19"
]

static func texture(kind: int, simplified: bool = false) -> Texture2D:
	var textures: Array[Texture2D] = _small_textures if simplified else _textures
	if textures.is_empty():
		for i in GLYPHS.size():
			var glyph: Dictionary = GLYPHS[i].duplicate()
			if simplified: glyph.path = SIMPLE_PATHS[i]
			var image := Image.new()
			var error := image.load_svg_from_string(_svg(glyph,simplified))
			assert(error == OK, "Particle vector artwork failed to load")
			image.generate_mipmaps()
			textures.append(ImageTexture.create_from_image(image))
	return textures[kind]

static func _svg(glyph: Dictionary, simplified: bool = false) -> String:
	if glyph.get("point",false):
		return "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96' viewBox='-48 -48 96 96'><circle r='38' fill='#%s'/><circle r='22' fill='#fff4df'/></svg>" % glyph.color
	# A dark underside, saturated body and short bright front make rotation legible.
	# Decorative branches do not add extra reaction sites or collision geometry.
	var path := "<path d='%s' fill='none'/>" % glyph.path
	var lobes: String = glyph.get("lobes", "")
	if simplified:
		return "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96' viewBox='-48 -48 96 96'><g stroke-linecap='round' stroke-linejoin='round' stroke='#%s' fill='#%s' stroke-width='18'>%s%s</g><path d='%s' fill='none' stroke='#fff1ac' stroke-width='10' stroke-linecap='round'/></svg>" % [glyph.color,glyph.color,path,lobes,glyph.tips]
	return """<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="-48 -48 96 96">
<g stroke-linecap="round" stroke-linejoin="round">
<g transform="translate(0 3)" stroke="#%s" fill="#%s" stroke-width="20">%s%s</g>
<g stroke="#%s" fill="#%s" stroke-width="16">%s%s</g>
<path d="%s" fill="none" stroke="#fff4d3" stroke-width="9"/>
</g></svg>""" % [glyph.shade,glyph.shade,path,lobes,glyph.color,glyph.color,path,lobes,glyph.tips]
