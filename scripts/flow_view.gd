extends Node2D
## Pale total-flow curves and an opposite-style gold input layer; presentation only.
const Medium = preload("res://scripts/medium.gd")
const Currents=preload("res://scripts/induced_currents.gd")
const MAX_STREAMERS := 640
const MAX_CRESTS := 96
const MAX_DRAWN := 64
const MAX_INPUT := 32
var mobile_quality:=false
var curve_budget=preload("res://scripts/current_curve_budget.gd").new()
const SOURCE_MARKERS := 64
const FADE_IN := .4
const FADE_OUT := .8
const CURVE_INTERVAL := .05
const CurveLayout=preload("res://scripts/current_curve_layout.gd")
const UM_PER_UNIT=preload("res://scripts/scale_bar.gd").MICROMETERS_PER_UNIT
const SEED_STRIDE := 4
const MAX_WAKE_ANCHORS := 30
const PAD := 384.0
const STRIP_SEGMENTS := 32
var streamers := MultiMeshInstance2D.new()
var crests := MultiMeshInstance2D.new()
var input_streamers := MultiMeshInstance2D.new()
var input_crests := MultiMeshInstance2D.new()
var input_events: Array=[]
var input_velocity:=PackedVector2Array()
var previous_input_velocity:=PackedVector2Array()
var input_mix:=1.0
var input_field_time := -INF
var visual_sources: Dictionary={}
var source_clock := -INF
var next_curve_id := 0
var input_paths: Array[PackedVector2Array]=[]
var input_samples: Array[Dictionary]=[]
var input_baselines: Array[Vector2]=[]
var input_image: Image
var input_texture: ImageTexture
var use_crests := true
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
var cached_field_speed:=0.0
var curve_baselines: Array[Vector2]=[]

func _ready() -> void:
	z_index = 0
	streamers.multimesh = batch(strip_mesh(),MAX_STREAMERS)
	streamers.material = shader("res://shaders/flow_streamer.gdshader")
	crests.multimesh = batch(strip_mesh(),MAX_CRESTS)
	crests.material = shader("res://shaders/flow_crests.gdshader")
	crests.hide()
	input_streamers.multimesh=batch(strip_mesh(),MAX_INPUT)
	input_streamers.material=shader("res://shaders/flow_streamer.gdshader")
	input_crests.multimesh=batch(strip_mesh(),MAX_INPUT)
	input_crests.material=shader("res://shaders/flow_crests.gdshader")
	for view in [input_streamers,input_crests]:
		view.z_index=1;view.material.set_shader_parameter("gold_only",true)
	wakes.multimesh = batch(quad_mesh(),MAX_WAKE_ANCHORS)
	wakes.material = shader("res://shaders/flow_wake.gdshader")
	add_child(streamers)
	add_child(crests)
	add_child(input_streamers)
	add_child(input_crests)
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
	input_streamers.visible=show_streams and use_crests;input_crests.visible=show_streams and not use_crests
	wakes.visible=show_wakes and world.habitat_geometry.enabled
	if not show_streams and not show_wakes:return
	if curve_budget.configure(mobile_quality):curve_time=-INF
	var reset: bool=habitat_cache!=world.habitat_geometry or crest_world!=world or world.time<crest_clock
	if reset:
		crest_tracks.clear();visual_sources.clear();source_clock=-INF;curve_time=-INF;crest_world=world
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
		var old_speed:=cached_field_speed
		var squared:=0.0
		for velocity in cached_velocity:squared=maxf(squared,velocity.length_squared())
		cached_field_speed=sqrt(squared)
		field_speed=maxf(old_speed,cached_field_speed)
	display_mix=clampf((world.time-last_field_time)*15.0,0,1)
	if reset:habitat_cache=world.habitat_geometry;anchor_data.clear()
	if anchor_data.is_empty():
		anchor_data=anchors(world.habitat_geometry);wakes.multimesh.visible_instance_count=anchor_data.size()
		for i in anchor_data.size():wakes.multimesh.set_instance_custom_data(i,anchor_data[i])
	wakes.material.set_shader_parameter("camera",camera);wakes.material.set_shader_parameter("clock",world.time);wakes.material.set_shader_parameter("field_mix",display_mix)
	var final_scale: Vector2=get_viewport().get_final_transform().get_scale().abs()
	var stroke_zoom: float=zoom*maxf(.001,minf(final_scale.x,final_scale.y))
	var events:=Currents.sources(world.seed_value,world.time)
	input_events=events
	if reset or world.time-input_field_time>=.1 or input_velocity.is_empty():
		var next:=Currents.raster_forcing(events)
		previous_input_velocity=next if reset or input_velocity.is_empty() else input_velocity
		input_velocity=next;input_field_time=world.time
	input_mix=clampf((world.time-input_field_time)*10,0,1)
	var sources:=_source_markers(events,world.time)
	for view in [streamers,crests,input_streamers,input_crests]:
		view.material.set_shader_parameter("eddy_sources",sources);view.material.set_shader_parameter("zoom",stroke_zoom);view.material.set_shader_parameter("camera",camera)
	if show_streams:
		if reset or world.time-curve_time>=CURVE_INTERVAL or curve_field_time!=last_field_time or curve_style!=use_crests or Medium.offset(curve_camera,camera).length()>64 or half_view!=curve_half or not is_equal_approx(stroke_zoom,curve_zoom):
			var build_start:=Time.get_ticks_usec()
			_build_curves(world,events,camera,half_view,stroke_zoom)
			curve_budget.observe(Time.get_ticks_usec()-build_start,Time.get_ticks_usec()/1000000.0)
		_move_drawn(world.time,camera)
	prepare_usec=Time.get_ticks_usec()-started

func _move_track(track: Dictionary,now: float,input: bool=false) -> void:
	var elapsed: float=maxf(0,now-float(track.time))
	if elapsed<=0:return
	var count:=clampi(ceili(elapsed/.1),1,64);var dt:=elapsed/count
	var at: Vector2=track.p
	for i in count:
		var v:=_velocity(at,input)
		at=Medium.wrap_position(at+_velocity(at+v*dt*.5,input)*dt)
	track.p=at;track.time=now

func _source_markers(events: Array,now: float) -> PackedVector4Array:
	var dt:=0.0 if not is_finite(source_clock) else maxf(0,now-source_clock)
	source_clock=now
	var wanted: Dictionary={}
	for i in events.size():
		var event: Dictionary=events[i]
		var episode:=floori((now+i*Currents.PERIOD/Currents.COUNT)/Currents.PERIOD)
		var key:="%s:%s" % [i,episode]
		if event.envelope<=0:continue
		wanted[key]=true
		var marker: Dictionary=visual_sources.get(key,{"source":event,"opacity":0.0})
		marker.source=event
		marker.opacity=move_toward(float(marker.opacity),float(event.envelope),dt/FADE_IN)
		visual_sources[key]=marker
	var data:=PackedVector4Array()
	for key in visual_sources.keys():
		var marker: Dictionary=visual_sources[key]
		if not wanted.has(key):marker.opacity=move_toward(float(marker.opacity),0,dt/FADE_OUT)
		if marker.opacity<=0 and not wanted.has(key):visual_sources.erase(key);continue
		var source: Dictionary=marker.source
		if data.size()<SOURCE_MARKERS:data.append(Vector4(source.p.x,source.p.y,source.radius,marker.opacity))
	while data.size()<SOURCE_MARKERS:data.append(Vector4(0,0,1,0))
	return data

func _candidate(seed: Color,dense: bool,input: bool,now: float) -> Dictionary:
	var episode:=floori((now+seed.b*20.0)/20.0)
	var age:=fposmod(now+seed.b*20.0,20.0)
	var key:="%s:%s:%s:%s:%s" % [input,dense,seed.r,seed.g,episode]
	return {"key":key,"seed":seed,"dense":dense,"input":input,"target":(1.0 if input else seed.a)*(1-smoothstep(18.0,20.0,age))}

func _velocity(at: Vector2,input: bool) -> Vector2:
	return _sample_velocity(previous_input_velocity,at).lerp(_sample_velocity(input_velocity,at),input_mix) if input else _display_flow(at)

func _curve(center: Vector2,span: float,waves: bool,input: bool=false) -> PackedVector2Array:
	var result:=PackedVector2Array()
	if waves:
		var left:=PackedVector2Array();var right:=PackedVector2Array([center])
		for sign_step in [-1.0,1.0]:
			var at:=center
			for i in STRIP_SEGMENTS/2:
				var h: float=sign_step*span/STRIP_SEGMENTS/2.0
				for j in 2:
					var v:=_velocity(at,input)
					if v.length()<.05:return PackedVector2Array()
					var n:=Vector2(-v.y,v.x).normalized()
					var mid:=_velocity(at+n*h*.5,input)
					if mid.length()<.05:return PackedVector2Array()
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
				var v:=_velocity(at,input);at+=_velocity(at+v*h*.5,input)*h
			result.append(at)
		result.reverse()
	return result

func _relative(points: PackedVector2Array,camera: Vector2) -> PackedVector2Array:
	var result:=PackedVector2Array()
	var first:=Medium.offset(camera,points[0])
	for point in points:result.append(first+point-points[0])
	return result

func _current_path(sample: Dictionary) -> PackedVector2Array:
	var shift:=Medium.offset(sample.baseline,sample.track.p)
	var result:=PackedVector2Array()
	for point in sample.points:result.append(point+shift)
	return result

func _build_curves(world,events: Array,camera: Vector2,half_view: Vector2,zoom: float) -> void:
	var style_changed:=curve_style!=use_crests
	if style_changed:crest_tracks.clear()
	var shape_dt:=CURVE_INTERVAL if not is_finite(curve_time) else maxf(0,world.time-curve_time)
	curve_time=world.time;curve_field_time=last_field_time;curve_style=use_crests
	curve_camera=camera;curve_half=half_view;curve_zoom=zoom
	var generated:=seeds(camera,half_view);streamer_data=generated.data
	var wanted: Dictionary={}
	# Gold traces only the true induced input. Ordinary denser samples show total flow.
	for input in [true,false]:
		var dense:=_dense_seeds(events,camera,half_view,Vector2(23,11) if input else Vector2.ZERO)
		for i in mini(128,dense.size()):
			var item:=_candidate(dense[i],true,input,world.time);wanted[item.key]=item
	var ambient:=0
	for seed in streamer_data:
		if use_crests and roundi(seed.b*101)%4!=0:continue
		var item:=_candidate(seed,false,false,world.time);wanted[item.key]=item;ambient+=1
		if ambient>=64:break
	# Reserve every already-visible curve before proposing replacements. A curve
	# which no longer fits keeps its last safe geometry throughout its fade.
	var layout=CurveLayout.new(5.0/maxf(zoom,.001)+2*maxf(field_speed,60)*CURVE_INTERVAL)
	for sample in crest_tracks.values():
		if sample.points.is_empty():continue
		var points:=_current_path(sample)
		sample.points=points;sample.baseline=sample.track.p
		layout.reserve(_relative(points,camera),sample.id)
	_budget_tracks()
	var counts:=[0,0]
	var dense_count:=0
	var limits: Vector2i=curve_budget.limits()
	for sample in crest_tracks.values():
		counts[1 if sample.input else 0]+=1
		if sample.dense and not sample.input:dense_count+=1
	for key in wanted:
		if crest_tracks.has(key):continue
		var item: Dictionary=wanted[key];var group:=1 if item.input else 0
		if counts[group]>=(limits.y if item.input else limits.x):continue
		if item.dense and not item.input and dense_count>=32:continue
		var seed: Color=item.seed
		var sample: Dictionary=item.duplicate()
		sample.merge({"id":next_curve_id,"track":{"p":Vector2(seed.r,seed.g),"time":world.time},"span":(10+90*pow(fposmod(seed.b*29.71+.13,1.0),1.5))/UM_PER_UNIT,"opacity":0.0,"fade_time":world.time,"retiring":false,"blocked":false,"points":PackedVector2Array(),"baseline":Vector2(seed.r,seed.g)})
		next_curve_id+=1;crest_tracks[key]=sample;counts[group]+=1
		if item.dense and not item.input:dense_count+=1
	for key in crest_tracks.keys():
		var sample: Dictionary=crest_tracks[key]
		if not wanted.has(key):sample.retiring=true
		var goal:=float(wanted[key].target) if wanted.has(key) and not sample.retiring else 0.0
		if goal<=.001:sample.retiring=true;goal=0
		sample.target=goal
		if sample.retiring:
			sample.track.time=world.time
		else:
			var proposal: Dictionary=sample.track.duplicate();_move_track(proposal,world.time,sample.input)
			var center: Vector2=proposal.p
			var beyond: Vector2=Medium.offset(camera,center).abs()-half_view-Vector2.ONE*PAD
			var waves: bool=not use_crests if sample.input else use_crests
			var points:=_curve(center,sample.span,waves,sample.input) if beyond.x<=0 and beyond.y<=0 and _velocity(center,sample.input).length()>=.05 else PackedVector2Array()
			if not points.is_empty() and not sample.points.is_empty():
				var old: PackedVector2Array=sample.points
				var shift:=Medium.offset(sample.baseline,center)
				var blend:=1-exp(-shape_dt/.25)
				var wrap_shift:=old[0]+Medium.offset(old[0],points[0])-points[0]
				for i in points.size():points[i]=(old[i]+shift).lerp(points[i]+wrap_shift,blend)
			if not points.is_empty() and layout.accept(_relative(points,camera),sample.id):
				sample.track=proposal;sample.points=points;sample.baseline=center;sample.blocked=false
			else:
				# A crowded neighborhood can delay a shape refresh. Keep a
				# visible safe path rather than repeatedly retiring/reseeding it.
				sample.track.time=world.time;sample.blocked=true
				if sample.points.is_empty() or _velocity(sample.track.p,sample.input).length()<.05:
					sample.retiring=true;sample.target=0
		if sample.retiring and sample.opacity<=.001:crest_tracks.erase(key)
	drawn_paths.clear();drawn_samples.clear();curve_baselines.clear()
	input_paths.clear();input_samples.clear();input_baselines.clear()
	for sample in crest_tracks.values():
		if sample.points.is_empty():continue
		if sample.input:input_paths.append(sample.points);input_samples.append(sample);input_baselines.append(sample.baseline)
		else:drawn_paths.append(sample.points);drawn_samples.append(sample);curve_baselines.append(sample.baseline)
	publish_paths(drawn_paths,drawn_samples.map(func(sample):return sample.opacity))
	_publish_input()

func _budget_tracks() -> void:
	var limits: Vector2i=curve_budget.limits()
	var retained:=[0,0]
	for sample in crest_tracks.values():
		if sample.retiring:continue
		var group:=1 if sample.input else 0
		if retained[group]>=(limits.y if sample.input else limits.x):sample.retiring=true
		else:retained[group]+=1

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

func _publish_input() -> void:
	if input_image==null:
		input_image=Image.create(STRIP_SEGMENTS+1,MAX_CRESTS,false,Image.FORMAT_RGF)
		input_texture=ImageTexture.create_from_image(input_image)
		for view in [input_streamers,input_crests]:view.material.set_shader_parameter("curve_map",input_texture)
	for row in input_paths.size():
		for column in input_paths[row].size():input_image.set_pixel(column,row,Color(input_paths[row][column].x,input_paths[row][column].y,0))
	input_texture.update(input_image)
	var active:=input_streamers if use_crests else input_crests
	active.multimesh.visible_instance_count=input_paths.size()

func _move_drawn(now: float,camera: Vector2) -> void:
	for input in [false,true]:
		var active: MultiMeshInstance2D
		var samples: Array[Dictionary]=input_samples if input else drawn_samples
		var baselines: Array[Vector2]=input_baselines if input else curve_baselines
		if input:active=input_streamers if use_crests else input_crests
		else:active=crests if use_crests else streamers
		for row in samples.size():
			var sample: Dictionary=samples[row]
			var dt:=maxf(0,now-float(sample.fade_time));sample.fade_time=now
			sample.opacity=move_toward(float(sample.opacity),float(sample.target),dt/(FADE_IN if sample.target>sample.opacity else FADE_OUT))
			if not sample.retiring and not sample.blocked:_move_track(sample.track,now,input)
			var shift:=Medium.offset(baselines[row],sample.track.p)
			active.multimesh.set_instance_custom_data(row,Color(shift.x,shift.y,row,sample.opacity))

func _dense_seeds(events: Array,camera: Vector2,half_view: Vector2,offset: Vector2=Vector2.ZERO) -> Array[Color]:
	var chosen: Dictionary={}
	for source in events:
		if source.envelope<=.001:continue
		var beyond: Vector2=Medium.offset(camera,source.p).abs()-half_view-Vector2.ONE*(source.radius+PAD)
		if beyond.x>0 or beyond.y>0:continue
		var low:=Vector2i(((source.p-Vector2.ONE*source.radius)/64.0).floor())
		var high:=Vector2i(((source.p+Vector2.ONE*source.radius)/64.0).floor())
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var key:=Vector2i(posmod(x,64),posmod(y,40))
				var h:=posmod(key.x*73856093 ^ key.y*19349663,65521)
				var jitter:=Vector2(.25+float(h%97)/194.0,.25+float(h%89)/178.0)
				var at:=Medium.wrap_position((Vector2(key)+jitter)*64.0+offset)
				var weight: float=(1-smoothstep(.3,1.0,Medium.offset(source.p,at).length()/source.radius))*float(source.envelope)
				if weight<=.001:continue
				var sample:=Color(at.x,at.y,float(h%101)/101.0,weight)
				if not chosen.has(key) or sample.a>chosen[key].a:chosen[key]=sample
	var result: Array[Color]=[]
	for sample in chosen.values():result.append(sample)
	result.sort_custom(func(a,b):return a.a>b.a)
	return result

static func _sample_velocity(values: PackedVector2Array,p: Vector2) -> Vector2:
	var q:=Medium.wrap_position(p)/Medium.SIZE-Vector2.ONE*.5
	var x:=floori(q.x);var y:=floori(q.y);var f:=q-q.floor()
	var top:=values[Medium.index(x,y)].lerp(values[Medium.index(x+1,y)],f.x)
	var bottom:=values[Medium.index(x,y+1)].lerp(values[Medium.index(x+1,y+1)],f.x)
	return top.lerp(bottom,f.y)

func _display_flow(p: Vector2) -> Vector2:
	return _sample_velocity(previous_velocity,p).lerp(_sample_velocity(cached_velocity,p),display_mix)
