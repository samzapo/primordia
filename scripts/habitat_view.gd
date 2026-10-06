extends Node2D
## Finite fractal geometry rasterizes once per habitat; no per-leaf nodes or physics.
var habitat
var textures: Array[Texture2D] = []
var sprites: Array[Sprite2D] = []
const PALETTES := [["12475d","1ebc98","a5ef73"],["472369","a544b7","f89cbe"],["14447d","298bcc","64dddb"],["72363b","e99143","ffe98c"]]

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
			var blade: bool = form.get("leaf","oval") == "blade"
			if blade:
				# Lanceolate pinnules cover each finest branch, with a simple vein.
				var middle := a.lerp(b,0.55)
				var normal := (b-a).orthogonal().normalized()*clampf(a.distance_to(b)*0.3,2.0,4.0)
				var left := middle+normal
				var right := middle-normal
				output += "<path d='M %.3f %.3f Q %.3f %.3f %.3f %.3f Q %.3f %.3f %.3f %.3f Z' fill='#%s'/><path d='M %.3f %.3f L %.3f %.3f' stroke='#%s' stroke-width='0.65'/>" % [a.x,a.y,left.x,left.y,b.x,b.y,right.x,right.y,a.x,a.y,palette[1],a.x,a.y,b.x,b.y,palette[2]]
				continue
			var bud: bool = form.get("leaf","oval") == "bud"
			var rx := 3.2 if bud else 4.5
			var ry := 3.2 if bud else 2.6
			output += "<ellipse cx='%.3f' cy='%.3f' rx='%.2f' ry='%.2f' transform='rotate(%.2f %.3f %.3f)' fill='#%s'/><ellipse cx='%.3f' cy='%.3f' rx='%.2f' ry='%.2f' transform='rotate(%.2f %.3f %.3f)' fill='#%s'/>" % [b.x,b.y,rx,ry,angle,b.x,b.y,palette[1],b.x,b.y-0.5,rx*0.58,ry*0.53,angle,b.x,b.y,palette[2]]
	# The basal cap lies inside the shared stem footprint, including fern roots.
	var root: Vector2 = form.get("root",Vector2.ZERO)
	var radius: float = form.get("root_radius",7.0)*0.92
	output += "<circle cx='%.3f' cy='%.3f' r='%.3f' fill='#%s'/><circle cx='%.3f' cy='%.3f' r='%.3f' fill='#%s'/></g></svg>" % [root.x,root.y,radius,palette[0],root.x,root.y-radius*0.15,radius*0.65,palette[2]]
	return output
