extends Node2D
const ParticleArt=preload("res://scripts/particle_art.gd")
var batch: MultiMeshInstance2D
var particles: WeakRef
func initialize(gpu) -> void:
	particles=weakref(gpu)
	batch=MultiMeshInstance2D.new()
	var mesh := QuadMesh.new()
	mesh.size=Vector2.ONE
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_2D
	multi.use_colors=true
	multi.mesh=mesh
	multi.instance_count=gpu.count
	var transforms := PackedFloat32Array()
	transforms.resize(gpu.count*12)
	for i in gpu.count:
		transforms[i*12]=1;transforms[i*12+5]=1
		for j in range(8,12): transforms[i*12+j]=1
	multi.buffer=transforms
	multi.custom_aabb=AABB(Vector3(-4096,-2560,-1),Vector3(8192,5120,2))
	batch.multimesh=multi
	var atlas := Image.create(96*26,96,false,Image.FORMAT_RGBA8)
	for i in 26:
		var image: Image=ParticleArt.texture(i).get_image()
		image.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(image,Rect2i(0,0,96,96),Vector2i(i*96,0))
	atlas.generate_mipmaps()
	batch.texture=ImageTexture.create_from_image(atlas)
	batch.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/resident_particles.gdshader")
	material.set_shader_parameter("state_texture",gpu.texture)
	material.set_shader_parameter("camera",Vector2.ZERO)
	material.set_shader_parameter("cpu_instances",false)
	batch.material=material
	batch.position=Vector2.ZERO
	batch.scale=Vector2.ONE
	add_child(batch)
func camera(at: Vector2) -> void:
	batch.multimesh.visible_instance_count=particles.get_ref().work_count
	batch.material.set_shader_parameter("camera",at)
