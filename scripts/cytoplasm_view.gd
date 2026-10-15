extends MultiMeshInstance2D
## Native samples resident poses directly; web interpolates detached snapshots.
const Catalog=preload("res://scripts/chemistry_catalog.gd")
const Visuals=preload("res://scripts/visuals.gd")
var allocated:=0
var component
var is_cpu:=true
var packet_buffer:=PackedFloat32Array()
func _ready() -> void:
	var mesh:=QuadMesh.new();mesh.size=Vector2.ONE*2
	multimesh=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_2D;multimesh.use_colors=true;multimesh.use_custom_data=true;multimesh.mesh=mesh
	multimesh.custom_aabb=AABB(Vector3(-8192,-8192,-1),Vector3(16384,16384,2))
	material=ShaderMaterial.new();material.shader=preload("res://shaders/resident_cytoplasm.gdshader")
	var atlas:=Image.create(192,96,false,Image.FORMAT_RGBA8)
	for j in 2:
		var glyph: Image=preload("res://scripts/particle_art.gd").texture(0 if j==0 else 2).get_image()
		glyph.convert(Image.FORMAT_RGBA8);atlas.blit_rect(glyph,Rect2i(0,0,96,96),Vector2i(j*96,0))
	atlas.generate_mipmaps();material.set_shader_parameter("glyph_atlas",ImageTexture.create_from_image(atlas))

func sync(chem,alpha: float,mask: Texture2D,extent: float) -> void:
	material.set_shader_parameter("focus_mask",mask)
	material.set_shader_parameter("focus_extent",extent)
	var gpu=chem.accelerator
	var cpu: bool=gpu==null
	var count: int=chem.particles.size() if cpu else chem.particle_count()
	var required: int=gpu.capacity if not cpu else count
	if required>allocated or is_cpu!=cpu:
		allocated=maxi(64,required);multimesh.instance_count=allocated
		packet_buffer.resize(allocated*16)
		for i in allocated:
			packet_buffer[i*16]=1;packet_buffer[i*16+5]=1
			for j in range(8,12):packet_buffer[i*16+j]=1
		multimesh.buffer=packet_buffer
		is_cpu=cpu
	material.set_shader_parameter("cpu_instances",cpu)
	multimesh.visible_instance_count=count
	if not cpu:
		if component!=gpu:component=gpu;material.set_shader_parameter("state_texture",gpu.texture)
		return
	var keys: Array=Catalog.data().species.keys()
	for i in count:
		var packet: Dictionary=chem.particles[i];var origin: Dictionary=chem.render_origins.get(packet.id,{})
		var previous: Vector2=origin.get("p",packet.p)
		var at: Vector2=previous.lerp(packet.p,alpha)
		var angle:=lerp_angle(float(origin.get("angle",packet.angle)),packet.angle,alpha)
		var radius: float=Visuals.internal_particle_radius(packet)
		var co:=cos(angle)*radius;var si:=sin(angle)*radius;var index:=i*16
		packet_buffer[index]=co;packet_buffer[index+1]=-si;packet_buffer[index+3]=at.x;packet_buffer[index+4]=si;packet_buffer[index+5]=co;packet_buffer[index+7]=at.y
		var color:=Color(Catalog.data().species[packet.species].color)
		packet_buffer[index+8]=1;packet_buffer[index+9]=1;packet_buffer[index+10]=1;packet_buffer[index+11]=1
		packet_buffer[index+12]=keys.find(packet.species)+fposmod(angle,TAU)/TAU*.5
		packet_buffer[index+13]=at.x;packet_buffer[index+14]=at.y;packet_buffer[index+15]=radius
	multimesh.buffer=packet_buffer
