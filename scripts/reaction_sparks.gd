extends MultiMeshInstance2D
## One bounded GPU batch, sampled from successful pair reactions only.
const LIFETIME := 0.24
const LIMIT := 128
var buffer := PackedFloat32Array()
var displayed := 0

func _ready() -> void:
	z_index = 14
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*28
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = LIMIT
	multimesh.visible_instance_count = 0
	buffer.resize(LIMIT*12)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/reaction_spark.gdshader")
	material = shader_material

func sync(sim, camera: Vector2, half_view: Vector2, zoom: float, enabled: bool = true) -> void:
	displayed = 0
	if not enabled:
		multimesh.visible_instance_count = 0
		return
	var scale := 1.0/maxf(0.001,zoom)
	for event in sim.reaction_sparks:
		var age: float = sim.time-event.time
		if age < 0 or age >= LIFETIME: continue
		var at: Vector2 = sim.Medium.offset(camera,event.at)
		if absf(at.x) > half_view.x+28*scale or absf(at.y) > half_view.y+28*scale: continue
		var base := displayed*12
		buffer[base] = scale
		buffer[base+1] = 0
		buffer[base+2] = 0
		buffer[base+3] = at.x
		buffer[base+4] = 0
		buffer[base+5] = scale
		buffer[base+6] = 0
		buffer[base+7] = at.y
		buffer[base+8] = age/LIFETIME
		buffer[base+9] = float(event.serial%17)/17
		buffer[base+10] = 0
		buffer[base+11] = 1
		displayed += 1
		if displayed >= LIMIT: break
	if displayed > 0: multimesh.buffer = buffer
	multimesh.visible_instance_count = displayed
