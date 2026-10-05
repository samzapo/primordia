extends Node2D
## Finite fractal geometry rasterizes once per habitat; no per-leaf nodes or physics.
var habitat
var textures: Array[Texture2D] = []
var sprites: Array[Sprite2D] = []
const PALETTES := [["12475d","1ebc98","a5ef73"],["472369","a544b7","f89cbe"],["14447d","298bcc","64dddb"]]

func configure(value) -> void:
	habitat = value
	for sprite in sprites: sprite.queue_free()
	sprites.clear()
	textures.clear()
	for form in habitat.forms:
		var image := Image.new()
		var error := image.load_svg_from_string(svg(form))
		assert(error == OK,"Fractal colony SVG failed to rasterize")
		image.generate_mipmaps()
		textures.append(ImageTexture.create_from_image(image))
	# Periodic copies prevent a colony popping across the screen at very wide zoom.
	for plant in habitat.plants:
		for y in range(-1,2):
			for x in range(-1,2):
				var sprite := Sprite2D.new()
				sprite.texture = textures[plant.form]
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				sprite.scale = Vector2.ONE*(plant.radius*2.2/512.0)
				sprite.rotation = plant.angle
				add_child(sprite)
				sprites.append(sprite)

func sync(camera: Vector2, half_view: Vector2) -> void:
	var i := 0
	for plant in habitat.plants:
		var nearest: Vector2 = habitat.Medium.offset(camera,plant.p)
		for y in range(-1,2):
			for x in range(-1,2):
				var p: Vector2 = nearest+Vector2(x,y)*habitat.Medium.WORLD
				sprites[i].position = p
				sprites[i].visible = habitat.enabled and absf(p.x) < half_view.x+plant.radius and absf(p.y) < half_view.y+plant.radius
				i += 1

static func svg(form: Dictionary) -> String:
	var palette: Array = PALETTES[form.palette]
	var output := "<svg xmlns='http://www.w3.org/2000/svg' width='512' height='512' viewBox='-110 -110 220 220'><g stroke-linecap='round' stroke-linejoin='round'>"
	for branch in form.branches:
		var a: Vector2 = branch.a
		var b: Vector2 = branch.b
		var r: float = branch.r
		# Main stroke exactly matches the capsule diameter in habitat.gd.
		output += "<path d='M %.3f %.3f L %.3f %.3f' stroke='#%s' stroke-width='%.3f'/>" % [a.x,a.y,b.x,b.y,palette[0],r*2]
		output += "<path d='M %.3f %.3f L %.3f %.3f' stroke='#%s' stroke-width='%.3f'/>" % [a.x,a.y,b.x,b.y,palette[1],r*1.62]
		if branch.depth > 0:
			output += "<path d='M %.3f %.3f L %.3f %.3f' stroke='#%s' stroke-width='%.3f'/>" % [a.x,a.y-r*0.22,b.x,b.y-r*0.22,palette[2],r*0.45]
		else:
			# Rounded terminal bracts are fine, permeable foliage, not extra solids.
			var angle := rad_to_deg((b-a).angle())
			output += "<ellipse cx='%.3f' cy='%.3f' rx='4.5' ry='2.6' transform='rotate(%.2f %.3f %.3f)' fill='#%s'/><ellipse cx='%.3f' cy='%.3f' rx='2.6' ry='1.4' transform='rotate(%.2f %.3f %.3f)' fill='#%s'/>" % [b.x,b.y,angle,b.x,b.y,palette[1],b.x,b.y-0.5,angle,b.x,b.y,palette[2]]
	# Stems overlap at the origin; this center stays inside their shared footprint.
	output += "<circle r='6.5' fill='#%s'/><circle cy='-0.7' r='4.5' fill='#%s'/><circle cx='-1' cy='-1.5' r='2' fill='#%s'/></g></svg>" % [palette[0],palette[1],palette[2]]
	return output
