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
	material.set_shader_parameter("glyph_atlas",atlas())

static var cached_atlas: Texture2D
static func atlas() -> Texture2D:
	if cached_atlas!=null:return cached_atlas
	var image:=Image.create(192,96,false,Image.FORMAT_RGBA8)
	for j in 2:
		var glyph: Image=preload("res://scripts/particle_art.gd").texture(0 if j==0 else 2).get_image()
		glyph.convert(Image.FORMAT_RGBA8);image.blit_rect(glyph,Rect2i(0,0,96,96),Vector2i(j*96,0))
	image.generate_mipmaps();cached_atlas=ImageTexture.create_from_image(image)
	return cached_atlas

func sync(chem,alpha: float,mask: Texture2D,extent: float) -> void:
	material.set_shader_parameter("focus_mask",mask)
	material.set_shader_parameter("focus_extent",extent)
	var gpu=chem.accelerator
	var cpu: bool=gpu==null
	var carriers: Array=[]
	if cpu:
		for packet in chem.particles:
			if packet.species=="waste" and chem.particles.any(func(food):return food.species=="food" and food.compartment==packet.compartment):continue
			carriers.append(packet)
	var count: int=carriers.size() if cpu else chem.particle_count()
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
	for i in count:
		var packet: Dictionary=carriers[i];var origin: Dictionary=chem.render_origins.get(packet.id,{})
		var previous: Vector2=origin.get("p",packet.p)
		var at: Vector2=previous.lerp(packet.p,alpha)
		var angle:=0.0 # A spherical carrier has no physical angular state; illustrations stay in the cell frame.
		var radius: float=Visuals.internal_particle_radius(packet)
		var co:=cos(angle)*radius;var si:=sin(angle)*radius;var index:=i*16
		packet_buffer[index]=co;packet_buffer[index+1]=-si;packet_buffer[index+3]=at.x;packet_buffer[index+4]=si;packet_buffer[index+5]=co;packet_buffer[index+7]=at.y
		var food:=0.0;var total:=0.0
		for stock in chem.particles:
			if stock.compartment!=packet.compartment:continue
			total+=stock.amount
			if stock.species=="food":food+=stock.amount
		packet_buffer[index+8]=1;packet_buffer[index+9]=1;packet_buffer[index+10]=1;packet_buffer[index+11]=1
		packet_buffer[index+12]=food/maxf(.0000001,total)
		packet_buffer[index+13]=at.x;packet_buffer[index+14]=at.y;packet_buffer[index+15]=clampf(ceilf(total/.3),1,7)+clampf(sqrt(total/maxf(1,ceilf(minf(7,total/.3)))/.3),.8,1.7)*.5
	multimesh.buffer=packet_buffer
