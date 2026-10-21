extends "res://scripts/resident_view.gd"
## WebGL presentation only: interpolate real server poses, never run chemistry.
var count := 100000
var work_count := 0
var texture := ImageTexture.new()
var previous_texture := ImageTexture.new()
var bodies_texture := ImageTexture.new()
var outlines_texture := ImageTexture.new()
var grid_texture:=ImageTexture.new()

func _ready() -> void:
	_upload(texture,PackedFloat32Array([0,0,0,1,0,0,0,0]),2,1,Image.FORMAT_RGBAF)
	initialize(self)
	batch.material.shader=preload("res://shaders/network_particles.gdshader")
	batch.material.set_shader_parameter("state_texture",texture)
	batch.material.set_shader_parameter("previous_texture",previous_texture)
	batch.material.set_shader_parameter("bodies_texture",bodies_texture)
	batch.material.set_shader_parameter("outlines_texture",outlines_texture)
	batch.material.set_shader_parameter("body_grid",grid_texture)
	batch.multimesh.visible_instance_count=0

func prepare(packets: Array,cells: Array) -> void:
	work_count=packets.size()
	var rows:=maxi(1,ceili(work_count/256.0))
	var current:=PackedFloat32Array();current.resize(rows*256*8)
	var prior:=PackedFloat32Array();prior.resize(rows*256*4)
	for i in packets.size():
		var p: Dictionary=packets[i]
		var diameter: float=2*preload("res://scripts/simulation.gd").particle_radius(p.kind)*preload("res://scripts/simulation.gd").particle_scale(p.amount)
		var at:=i*8;var old:=i*4
		current[at]=p.p.x;current[at+1]=p.p.y;current[at+2]=p.angle
		current[at+3]=diameter;current[at+4]=p.kind;current[at+5]=p.amount
		prior[old]=p.previous.x;prior[old+1]=p.previous.y
		prior[old+2]=p.previous_angle;prior[old+3]=diameter
	_upload(texture,current,512,rows,Image.FORMAT_RGBAF)
	_upload(previous_texture,prior,256,rows,Image.FORMAT_RGBAF)
	var Grid=preload("res://scripts/network/body_grid.gd")
	_upload(grid_texture,Grid.pixels(cells),Grid.WIDTH,Grid.HEIGHT,Image.FORMAT_RGBAF)
	var bodies:=PackedFloat32Array();bodies.resize(64*12)
	var points:=PackedFloat32Array()
	var n:=0
	for cell in cells:
		if cell.dead: continue
		if n>=64: push_error("Network renderer exceeds supported body count");break
		var outline: PackedVector2Array=cell.membrane.outline()
		assert(outline.size()<=512)
		var start:=points.size()/2
		for point in outline: points.append(point.x);points.append(point.y)
		var row:=PackedFloat32Array([cell.position.x,cell.position.y,cell.angle,cell.extent(),cell.previous_position.x,cell.previous_position.y,cell.previous_angle,cell.extent(),start,outline.size(),0,0])
		for j in 12:bodies[n*12+j]=row[j]
		n+=1
	_upload(bodies_texture,bodies,3,64,Image.FORMAT_RGBAF)
	var point_rows:=maxi(1,ceili(points.size()/512.0))
	points.resize(point_rows*512)
	_upload(outlines_texture,points,256,point_rows,Image.FORMAT_RGF)
	batch.material.set_shader_parameter("body_count",n)
	batch.multimesh.visible_instance_count=work_count

func draw_camera(at: Vector2,alpha: float) -> void:
	if batch==null:return
	camera(at)
	batch.material.set_shader_parameter("interpolation",alpha)

func _upload(target: ImageTexture,data: PackedFloat32Array,width: int,height: int,format: Image.Format) -> void:
	var image:=Image.create_from_data(width,height,false,format,data.to_byte_array())
	if target.get_width()==width and target.get_height()==height: target.update(image)
	else: target.set_image(image)
