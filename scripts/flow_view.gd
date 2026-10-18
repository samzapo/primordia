extends Node2D
## Mutually exclusive current styles plus wakes; no ecological particles or RNG.
const Medium = preload("res://scripts/medium.gd")
const Currents=preload("res://scripts/induced_currents.gd")
const MAX_STREAMERS := 640
const MAX_CRESTS := 96
const MAX_DRAWN := 64
const CURVE_INTERVAL := .05
const CurveLayout=preload("res://scripts/current_curve_layout.gd")
const UM_PER_UNIT=preload("res://scripts/scale_bar.gd").MICROMETERS_PER_UNIT
const SEED_STRIDE := 4
const MAX_WAKE_ANCHORS := 30
const PAD := 384.0
const STRIP_SEGMENTS := 32
var streamers := MultiMeshInstance2D.new()
var crests := MultiMeshInstance2D.new()
var use_crests := false
var crest_tracks: Dictionary={}
var crest_world
var crest_clock := -INF
var wakes := MultiMeshInstance2D.new()
var field: ImageTexture
var previous_field: ImageTexture
var cached_field: Image
var cached_velocity:=PackedVector2Array()
var previous_velocity:=PackedVector2Array()
var display_mix:=1.0
var last_field_time := -INF
var habitat_cache
var anchor_data: Array[Color] = []
var prepare_usec := 0
var streamer_data: Array[Color]=[]
var curve_image: Image
var curve_texture: ImageTexture
var drawn_paths: Array[PackedVector2Array]=[]
var drawn_samples: Array[Dictionary]=[]
var curve_time:=-INF
var curve_field_time:=-INF
var curve_camera:=Vector2(INF,INF)
var curve_half:=Vector2.ZERO
var curve_zoom:=0.0
var curve_style:=false
var field_speed:=0.0
var curve_baselines: Array[Vector2]=[]

func _ready() -> void:
	z_index = 0
	streamers.multimesh = batch(strip_mesh(),MAX_STREAMERS)
	streamers.material = shader("res://shaders/flow_streamer.gdshader")
	crests.multimesh = batch(strip_mesh(),MAX_CRESTS)
	crests.material = shader("res://shaders/flow_crests.gdshader")
	crests.hide()
	wakes.multimesh = batch(quad_mesh(),MAX_WAKE_ANCHORS)
	wakes.material = shader("res://shaders/flow_wake.gdshader")
	add_child(streamers)
	add_child(crests)
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


func sync(world,camera: Vector2,half_view: Vector2,zoom: float,show_streams: bool,show_wakes: bool) -> void:
	var started:=Time.get_ticks_usec()
	streamers.visible=show_streams and not use_crests;crests.visible=show_streams and use_crests
	wakes.visible=show_wakes and world.habitat_geometry.enabled
	if not show_streams and not show_wakes:return
	var reset: bool=habitat_cache!=world.habitat_geometry or crest_world!=world or world.time<crest_clock
	if reset:
		crest_tracks.clear();curve_time=-INF;crest_world=world
	crest_clock=world.time
	if field==null or reset or world.time-last_field_time>=1.0/15:
		var image:=Image.create_from_data(Medium.COLS,Medium.ROWS,false,Image.FORMAT_RGF,world.fluid.velocity.to_byte_array())
		if field==null:
			field=ImageTexture.create_from_image(image);previous_field=ImageTexture.create_from_image(image)
			wakes.material.set_shader_parameter("flow_map",field);wakes.material.set_shader_parameter("flow_map_old",previous_field)
		else:
			previous_field.update(image if reset else cached_field);field.update(image)
		previous_velocity=world.fluid.velocity.duplicate() if cached_velocity.is_empty() or reset else cached_velocity
		cached_velocity=world.fluid.velocity.duplicate();cached_field=image;last_field_time=world.time
		field_speed=0
		for values in [previous_velocity,cached_velocity]:
			for velocity in values:field_speed=maxf(field_speed,velocity.length())
	display_mix=clampf((world.time-last_field_time)*15.0,0,1)
	if reset:habitat_cache=world.habitat_geometry;anchor_data.clear()
	if anchor_data.is_empty():
		anchor_data=anchors(world.habitat_geometry);wakes.multimesh.visible_instance_count=anchor_data.size()
		for i in anchor_data.size():wakes.multimesh.set_instance_custom_data(i,anchor_data[i])
	wakes.material.set_shader_parameter("camera",camera);wakes.material.set_shader_parameter("clock",world.time);wakes.material.set_shader_parameter("field_mix",display_mix)
	var final_scale: Vector2=get_viewport().get_final_transform().get_scale().abs()
	var stroke_zoom: float=zoom*maxf(.001,minf(final_scale.x,final_scale.y))
	var events:=Currents.sources(world.seed_value,world.time)
	var sources:=PackedVector4Array()
	for event in events:sources.append(Vector4(event.p.x,event.p.y,event.radius*Currents.GOLD_CORE,event.envelope))
	for view in [streamers,crests]:
		view.material.set_shader_parameter("eddy_sources",sources);view.material.set_shader_parameter("zoom",stroke_zoom);view.material.set_shader_parameter("camera",camera)
	if show_streams:
		if reset or world.time-curve_time>=CURVE_INTERVAL or curve_field_time!=last_field_time or curve_style!=use_crests or Medium.offset(curve_camera,camera).length()>64 or half_view!=curve_half or not is_equal_approx(stroke_zoom,curve_zoom):
			_build_curves(world,events,camera,half_view,stroke_zoom)
		_move_drawn(world.time,camera)
	prepare_usec=Time.get_ticks_usec()-started

func _move_track(track: Dictionary,now: float) -> void:
	var elapsed: float=maxf(0,now-float(track.time))
	if elapsed<=0:return
	var count:=clampi(ceili(elapsed/.1),1,64);var dt:=elapsed/count
	var at: Vector2=track.p
	for i in count:
		var v:=_display_flow(at)
		at=Medium.wrap_position(at+_display_flow(at+v*dt*.5)*dt)
	track.p=at;track.time=now

func _sample(world,seed: Color,dense: bool,retained: Dictionary) -> Dictionary:
	var phase: float=world.time+seed.b*20.0
	var episode:=floori(phase/20.0);var age:=fposmod(phase,20.0)
	var key:="%s:%s:%s:%s" % [dense,seed.r,seed.g,0 if dense else episode]
	var track: Dictionary
	if dense:
		track=crest_tracks.get(key,{})
		if track.is_empty() or world.time-float(track.birth)>=20.0:
			track={"p":Vector2(seed.r,seed.g),"time":world.time-seed.b*.2,"birth":world.time-seed.b*.2}
		age=world.time-float(track.birth)
	else:track=crest_tracks.get(key,{"p":Vector2(seed.r,seed.g),"time":world.time-age})
	_move_track(track,world.time);retained[key]=track
	var opacity: float=smoothstep(0,.08 if dense else 1.0,age)*(1-smoothstep(18.5,20.0,age))
	return {"track":track,"span":(10+90*pow(fposmod(seed.b*29.71+.13,1.0),1.5))/UM_PER_UNIT,"opacity":opacity*seed.a,"dense":dense}

func _curve(center: Vector2,span: float) -> PackedVector2Array:
	var result:=PackedVector2Array()
	if use_crests:
		var left:=PackedVector2Array();var right:=PackedVector2Array([center])
		for sign_step in [-1.0,1.0]:
			var at:=center
			for i in STRIP_SEGMENTS/2:
				var h: float=sign_step*span/STRIP_SEGMENTS/2.0
				for j in 2:
					var v:=_display_flow(at)
					if v.length()<1:return PackedVector2Array()
					var n:=Vector2(-v.y,v.x).normalized()
					var mid:=_display_flow(at+n*h*.5)
					if mid.length()<1:return PackedVector2Array()
					var normal:=Vector2(-mid.y,mid.x).normalized()
					if n.dot(normal)<.25:return PackedVector2Array()
					at+=normal*h
				if sign_step<0:left.append(at)
				else:right.append(at)
		left.reverse();result.append_array(left);result.append_array(right)
	else:
		var at:=center;result.append(at)
		var h: float=-8.4/STRIP_SEGMENTS/2.0
		for i in STRIP_SEGMENTS:
			for j in 2:
				var v:=_display_flow(at);at+=_display_flow(at+v*h*.5)*h
			result.append(at)
		result.reverse()
	return result

func _build_curves(world,events: Array,camera: Vector2,half_view: Vector2,zoom: float) -> void:
	curve_time=world.time;curve_field_time=last_field_time;curve_style=use_crests
	curve_camera=camera;curve_half=half_view;curve_zoom=zoom
	var generated:=seeds(camera,half_view);streamer_data=generated.data
	var retained: Dictionary={};var candidates: Array[Dictionary]=[]
	var dense:=_dense_seeds(events,camera,half_view)
	for i in mini(96,dense.size()):candidates.append(_sample(world,dense[i],true,retained))
	var ambient:=0
	for seed in streamer_data:
		if use_crests and roundi(seed.b*101)%4!=0:continue
		candidates.append(_sample(world,seed,false,retained));ambient+=1
		if ambient>=64:break
	var layout=CurveLayout.new(5.0/maxf(zoom,.001)+2*field_speed*CURVE_INTERVAL)
	drawn_paths.clear();drawn_samples.clear();curve_baselines.clear()
	var dense_count:=0
	for sample in candidates:
		if drawn_paths.size()>=MAX_DRAWN:break
		if sample.dense and dense_count>=32:continue
		var center: Vector2=sample.track.p
		var beyond: Vector2=Medium.offset(camera,center).abs()-half_view-Vector2.ONE*384
		if beyond.x>0 or beyond.y>0 or _display_flow(center).length()<1:continue
		var points:=_curve(center,sample.span)
		if points.size()!=STRIP_SEGMENTS+1:continue
		var relative:=PackedVector2Array()
		var first: Vector2=Medium.offset(camera,points[0])
		for point in points:relative.append(first+point-points[0])
		if not layout.accept(relative):continue
		drawn_paths.append(points);drawn_samples.append(sample);curve_baselines.append(center)
		if sample.dense:dense_count+=1
	crest_tracks=retained
	publish_paths(drawn_paths,drawn_samples.map(func(sample):return sample.opacity))

func publish_paths(paths: Array[PackedVector2Array],opacities: Array=[],camera: Vector2=Vector2.ZERO) -> void:
	if curve_image==null:
		curve_image=Image.create(STRIP_SEGMENTS+1,MAX_CRESTS,false,Image.FORMAT_RGF)
		curve_texture=ImageTexture.create_from_image(curve_image)
		for view in [streamers,crests]:view.material.set_shader_parameter("curve_map",curve_texture)
	for row in paths.size():
		for column in paths[row].size():curve_image.set_pixel(column,row,Color(paths[row][column].x,paths[row][column].y,0))
	curve_texture.update(curve_image)
	var active:=crests if use_crests else streamers
	active.multimesh.visible_instance_count=paths.size()
	for row in paths.size():active.multimesh.set_instance_custom_data(row,Color(0,0,row,opacities[row] if row<opacities.size() else 1.0))

func _move_drawn(now: float,camera: Vector2) -> void:
	var active:=crests if use_crests else streamers
	for row in drawn_samples.size():
		var sample: Dictionary=drawn_samples[row];_move_track(sample.track,now)
		var shift:=Medium.offset(curve_baselines[row],sample.track.p)
		active.multimesh.set_instance_custom_data(row,Color(shift.x,shift.y,row,sample.opacity))

func _dense_seeds(events: Array,camera: Vector2,half_view: Vector2) -> Array[Color]:
	var chosen: Dictionary={}
	for source in events:
		if source.envelope<.1:continue
		var beyond: Vector2=Medium.offset(camera,source.p).abs()-half_view-Vector2.ONE*(source.radius+250)
		if beyond.x>0 or beyond.y>0:continue
		var tile:=Vector2i((source.p/32.0).floor())
		for y in range(tile.y-1,tile.y+2):
			for x in range(tile.x-1,tile.x+2):
				var key:=Vector2i(posmod(x,128),posmod(y,80))
				var h:=posmod(key.x*73856093 ^ key.y*19349663,65521)
				var jitter:=Vector2(.25+float(h%97)/194.0,.25+float(h%89)/178.0)
				var at: Vector2=(Vector2(key)+jitter)*32.0
				var sample:=Color(at.x,at.y,float(h%101)/101.0,source.envelope)
				if not chosen.has(key) or sample.a>chosen[key].a:chosen[key]=sample
	var result: Array[Color]=[]
	for sample in chosen.values():result.append(sample)
	return result

static func _sample_velocity(values: PackedVector2Array,p: Vector2) -> Vector2:
	var q:=Medium.wrap_position(p)/Medium.SIZE-Vector2.ONE*.5
	var x:=floori(q.x);var y:=floori(q.y);var f:=q-q.floor()
	var top:=values[Medium.index(x,y)].lerp(values[Medium.index(x+1,y)],f.x)
	var bottom:=values[Medium.index(x,y+1)].lerp(values[Medium.index(x+1,y+1)],f.x)
	return top.lerp(bottom,f.y)

func _display_flow(p: Vector2) -> Vector2:
	return _sample_velocity(previous_velocity,p).lerp(_sample_velocity(cached_velocity,p),display_mix)
