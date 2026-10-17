extends Node2D
## Two bounded GPU batches. Reads the fluid cache; no ecological particles or RNG.
const Medium = preload("res://scripts/medium.gd")
const MAX_STREAMERS := 640
const SEED_STRIDE := 4
const MAX_WAKE_ANCHORS := 30
const PAD := 384.0
const STRIP_SEGMENTS := 24
var streamers := MultiMeshInstance2D.new()
var wakes := MultiMeshInstance2D.new()
var field: ImageTexture
var previous_field: ImageTexture
var cached_field: Image
var last_field_time := -INF
var bounds := Rect2i()
var spacing := 0
var habitat_cache
var anchor_data: Array[Color] = []
var prepare_usec := 0

func _ready() -> void:
	z_index = 0
	streamers.multimesh = batch(strip_mesh(),MAX_STREAMERS)
	streamers.material = shader("res://shaders/flow_streamer.gdshader")
	wakes.multimesh = batch(quad_mesh(),MAX_WAKE_ANCHORS)
	wakes.material = shader("res://shaders/flow_wake.gdshader")
	add_child(streamers)
	add_child(wakes)

static func shader(path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(path)
	return material

static func batch(mesh: Mesh, count: int) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_2D
	result.use_custom_data = true
	result.mesh = mesh
	result.instance_count = count
	result.visible_instance_count = 0
	# Vertices are displaced in the shader, so the undeformed unit mesh is not a
	# useful culling bound. Parent is the camera-relative world layer.
	result.custom_aabb = AABB(Vector3(-8192,-8192,-1),Vector3(16384,16384,2))
	for i in count: result.set_instance_transform_2d(i,Transform2D.IDENTITY)
	return result

static func strip_mesh() -> ArrayMesh:
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in STRIP_SEGMENTS+1:
		for side in 2:
			points.append(Vector2(float(i)/STRIP_SEGMENTS,side))
			uv.append(Vector2(float(i)/STRIP_SEGMENTS,side))
		if i > 0:
			var a := (i-1)*2
			indices.append_array(PackedInt32Array([a,a+2,a+3,a,a+3,a+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func quad_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	return mesh

static func seeds(camera: Vector2, half_view: Vector2) -> Dictionary:
	var step := 64
	var low := Vector2i(((camera-half_view-Vector2.ONE*PAD)/step).floor())
	var high := Vector2i(((camera+half_view+Vector2.ONE*PAD)/step).ceil())
	while (high.x-low.x+1)*(high.y-low.y+1) > MAX_STREAMERS:
		step *= 2
		low = Vector2i(((camera-half_view-Vector2.ONE*PAD)/step).floor())
		high = Vector2i(((camera+half_view+Vector2.ONE*PAD)/step).ceil())
	var data: Array[Color] = []
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var wx := posmod(x,int(Medium.WORLD.x)/step)
			var wy := posmod(y,int(Medium.WORLD.y)/step)
			# Presentation hash, periodic across seams; never draw simulation RNG.
			var h := posmod(wx*73856093 ^ wy*19349663,65521)
			# Thin by a periodic stable hash, preserving the original tile scale.
			# Coarsening beyond 512 would stop dividing the 2560-high torus.
			if h%SEED_STRIDE!=0:continue
			var jitter := Vector2(float(h%97)/97.0,float(h%89)/89.0)
			var p := (Vector2(wx,wy)+jitter)*step
			data.append(Color(p.x,p.y,float(h%101)/101.0,0.6+float(h%31)/77.5))
	return {"bounds":Rect2i(low,high-low+Vector2i.ONE),"spacing":step,"data":data}

static func anchors(habitat) -> Array[Color]:
	var data: Array[Color] = []
	for plant in habitat.plants:
		var form: Dictionary = habitat.forms[plant.form]
		var candidates: Array = form.branches.filter(func(branch): return branch.depth > 0 and branch.r >= 2.5)
		if candidates.is_empty(): continue
		for sample in mini(3,candidates.size()):
			var branch: Dictionary = candidates[int(float(sample)*candidates.size()/3)]
			var at: Vector2 = (branch.a+branch.b)*0.5
			at = Medium.wrap_position(plant.p+(at*plant.radius/100.0).rotated(plant.angle))
			data.append(Color(at.x,at.y,maxf(5.0,branch.r*plant.radius/100.0),float(data.size())*1.73))
			if data.size() == MAX_WAKE_ANCHORS: return data
	return data

func sync(world, camera: Vector2, half_view: Vector2, zoom: float, show_streams: bool, show_wakes: bool) -> void:
	var started := Time.get_ticks_usec()
	streamers.visible = show_streams
	wakes.visible = show_wakes and world.habitat_geometry.enabled
	if not show_streams and not show_wakes:
		prepare_usec = Time.get_ticks_usec()-started
		return
	var reset: bool = habitat_cache != world.habitat_geometry
	if field == null or reset or world.time-last_field_time >= 1.0/15 or world.time < last_field_time:
		var image := Image.create_from_data(Medium.COLS,Medium.ROWS,false,Image.FORMAT_RGF,world.fluid.velocity.to_byte_array())
		if field == null:
			field = ImageTexture.create_from_image(image)
			previous_field = ImageTexture.create_from_image(image)
			for view in [streamers,wakes]:
				view.material.set_shader_parameter("flow_map",field)
				view.material.set_shader_parameter("flow_map_old",previous_field)
		else:
			previous_field.update(image if reset or world.time < last_field_time else cached_field)
			field.update(image)
		cached_field = image
		last_field_time = world.time
	# Avoid regenerating seed arrays while the camera remains in the same tiles.
	var low := Vector2i(((camera-half_view-Vector2.ONE*PAD)/maxi(spacing,64)).floor())
	var high := Vector2i(((camera+half_view+Vector2.ONE*PAD)/maxi(spacing,64)).ceil())
	var desired := Rect2i(low,high-low+Vector2i.ONE)
	if spacing == 0 or desired != bounds:
		var generated := seeds(camera,half_view)
		bounds = generated.bounds
		spacing = generated.spacing
		streamers.multimesh.visible_instance_count = generated.data.size()
		for i in generated.data.size(): streamers.multimesh.set_instance_custom_data(i,generated.data[i])
	if reset:
		habitat_cache = world.habitat_geometry
		anchor_data.clear()
	if anchor_data.is_empty():
		anchor_data = anchors(world.habitat_geometry)
		wakes.multimesh.visible_instance_count = anchor_data.size()
		for i in anchor_data.size(): wakes.multimesh.set_instance_custom_data(i,anchor_data[i])
	for view in [streamers,wakes]:
		view.material.set_shader_parameter("camera",camera)
		view.material.set_shader_parameter("clock",world.time)
		view.material.set_shader_parameter("field_mix",clampf((world.time-last_field_time)*15.0,0,1))
	var sources:=PackedVector4Array()
	for source in preload("res://scripts/induced_currents.gd").sources(world.seed_value,world.time):
		sources.append(Vector4(source.p.x,source.p.y,source.radius*.22,source.envelope))
	streamers.material.set_shader_parameter("eddy_sources",sources)
	streamers.material.set_shader_parameter("zoom",zoom)
	prepare_usec = Time.get_ticks_usec()-started
