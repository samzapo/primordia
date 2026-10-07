extends RefCounted
## Opt-in fluid comparison. Resident solvent state; synchronous small field bridge.
## Never selected by normal gameplay. Chemistry and pheromones retain their rules.
const Medium = preload("res://scripts/medium.gd")
const MAX_BODIES := 32
const MAX_SHAPE_WORDS := 32768
const BIN_COUNT := 128*80
const DENSITY := Medium.NODE_MASS/(Medium.SIZE*Medium.SIZE)
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var uniform_set := RID()
var buffers: Array[RID] = []
var model := "grid"
var dx := 16.0
var spacing := 16.0
var viscosity := 40.0
var iterations := 80
var cols := 256
var rows := 160
var count := 0
var rest_density := 0.0
var driven := true
# Diagnostic pressure/contact feedback ablation; never an eligible production mode.
var body_feedback_enabled := true
var body_count := 0
var bodies: Array = []
var cached := PackedVector2Array()
var metrics: Dictionary = {}
var shape_values := PackedFloat32Array()
var ready := false

static func valid_options(kind: String, resolution: float, solve_iterations: int) -> bool:
	return kind in ["grid","pbf"] and resolution in [16.0,32.0] and solve_iterations >= 2 and solve_iterations <= 256 and solve_iterations%2 == 0

func initialize(kind: String, velocity: PackedVector2Array, cells: Array = [], habitat = null, resolution: float = 16.0, solve_iterations: int = 0) -> bool:
	var chosen := solve_iterations if solve_iterations > 0 else (80 if kind == "grid" else 8)
	if not valid_options(kind,resolution,chosen) or velocity.size() != 2560:
		push_error("Invalid fluid comparison options or input field")
		return false
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" or DisplayServer.get_name() == "headless":
		push_error("Fluid comparison requires a RenderingDevice renderer and GPU display")
		return false
	model = kind; dx = resolution; iterations = chosen
	cols = int(Medium.WORLD.x/dx); rows = int(Medium.WORLD.y/dx)
	rd = RenderingServer.create_local_rendering_device()
	if rd == null: return false
	var source := RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string("res://shaders/compute/fluid_compare.glsl").replace("#[compute]","")
	var spirv := rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "":
		push_error(spirv.compile_error_compute)
		close()
		return false
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	if not rd.compute_pipeline_is_valid(pipeline):
		close()
		return false
	var capacity := maxi(cols*rows,40960)
	for bytes in [capacity*16,capacity*16,cols*rows*16,(BIN_COUNT+capacity)*4,capacity*16,2560*16,MAX_SHAPE_WORDS*16,MAX_BODIES*16,capacity*16,MAX_BODIES*ceili(capacity/128.0)*16]:
		buffers.append(rd.storage_buffer_create(bytes))
	var uniforms: Array[RDUniform] = []
	for binding in buffers.size():
		var item := RDUniform.new()
		item.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		item.binding = binding
		item.add_id(buffers[binding])
		uniforms.append(item)
	uniform_set = rd.uniform_set_create(uniforms,shader,0)
	if not pack_geometry(cells,habitat):
		close()
		return false
	var list := begin()
	dispatch(list,0,cols*rows,1.0/60)
	finish(list)
	var wall_data := rd.buffer_get_data(buffers[2]).to_float32_array()
	var values := PackedFloat32Array()
	if model == "grid":
		count = cols*rows
		values.resize(count*4)
		for i in count:
			var at := Vector2(i%cols+0.5,int(i/cols)+0.5)*dx
			# MAC x/right and y/top faces, not center samples.
			values[i*4] = sample_array(velocity,at+Vector2(dx*0.5,0)).x
			values[i*4+1] = sample_array(velocity,at+Vector2(0,dx*0.5)).y
	else:
		for y in int(Medium.WORLD.y/spacing):
			for x in int(Medium.WORLD.x/spacing):
				var at := Vector2(x+0.5,y+0.5)*spacing
				var index := int(at.y/dx)*cols+int(at.x/dx)
				if wall_data[index*4] < 0: continue
				var v := sample_array(velocity,at)
				values.append_array(PackedFloat32Array([at.x,at.y,v.x,v.y]))
		count = values.size()/4
		var sum := 0.0
		for y in range(-2,3):
			for x in range(-2,3):
				var r := Vector2(x,y).length()*spacing
				if r < 32.0: sum += 4.0/(PI*pow(32.0,8))*pow(32*32-r*r,3)
		rest_density = DENSITY*spacing*spacing*sum
	update(0,values)
	cached = velocity.duplicate()
	ready = true
	return true

static func sample_array(values: PackedVector2Array, at: Vector2) -> Vector2:
	var q := Medium.wrap_position(at)/64.0-Vector2.ONE*0.5
	var c := Vector2i(q.floor())
	var f := q-Vector2(c)
	return values[Medium.index(c.x,c.y)].lerp(values[Medium.index(c.x+1,c.y)],f.x).lerp(
		values[Medium.index(c.x,c.y+1)].lerp(values[Medium.index(c.x+1,c.y+1)],f.x),f.y)

func pack_geometry(cells: Array, habitat) -> bool:
	bodies.clear()
	for cell in cells:
		if not cell.dead: bodies.append(cell)
	body_count = bodies.size()
	if body_count > MAX_BODIES:
		push_error("Fluid comparison body capacity exceeded; no bodies silently omitted")
		return false
	shape_values.resize((1+body_count*3)*4)
	shape_values.fill(0)
	shape_values[0] = body_count
	for k in body_count:
		var cell = bodies[k]
		var at := (1+k*3)*4
		shape_values[at] = cell.position.x; shape_values[at+1] = cell.position.y
		shape_values[at+2] = cell.extent(); shape_values[at+3] = cell.mass
		shape_values[at+4] = cell.velocity.x; shape_values[at+5] = cell.velocity.y
		shape_values[at+6] = cell.angular_velocity; shape_values[at+7] = cell.inertia
		shape_values[at+8] = shape_values.size()/4
		shape_values[at+9] = cell.membrane.points.size()
		var points: PackedVector2Array = cell.membrane.points
		for j in points.size():
			var a: Vector2 = points[j].rotated(cell.angle)
			var b: Vector2 = points[(j+1)%points.size()].rotated(cell.angle)
			shape_values.append_array(PackedFloat32Array([a.x,a.y,b.x,b.y]))
	shape_values[2] = shape_values.size()/4
	if habitat != null and habitat.enabled:
		shape_values[1] = habitat.segments.size()
		for segment in habitat.segments:
			shape_values.append_array(PackedFloat32Array([segment.a.x,segment.a.y,segment.b.x,segment.b.y,segment.r,0,0,0]))
	if shape_values.size()/4 > MAX_SHAPE_WORDS:
		push_error("Fluid comparison geometry capacity exceeded")
		return false
	update(6,shape_values)
	return true

func update(binding: int, values: PackedFloat32Array) -> void:
	var bytes := values.to_byte_array()
	rd.buffer_update(buffers[binding],0,bytes.size(),bytes)

func begin() -> int:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,uniform_set,0)
	return list

func dispatch(list: int, operation: int, amount: int, dt: float, ping: int = 0) -> void:
	var params := PackedByteArray()
	params.resize(64)
	for item in [[0,operation],[4,count],[8,cols],[12,rows],[32,ping],[36,body_count],[40,int(driven)],[44,int(model == "pbf")]]:
		params.encode_u32(item[0],item[1])
	for item in [[16,dx],[20,dt],[24,viscosity],[28,DENSITY],[48,spacing],[52,rest_density],[56,0.8]]:
		params.encode_float(item[0],item[1])
	rd.compute_list_set_push_constant(list,params,64)
	rd.compute_list_dispatch(list,maxi(1,ceili(amount/128.0)),1,1)
	rd.compute_list_add_barrier(list)

func solve(list: int, dt: float, geometry_changed: bool = true) -> void:
	if geometry_changed: dispatch(list,0,cols*rows,dt)
	if model == "grid":
		dispatch(list,1,count,dt)
		dispatch(list,2,count,dt)
		for j in iterations: dispatch(list,3,count,dt,j%2)
		dispatch(list,4,count,dt)
	else:
		dispatch(list,10,count,dt)
		for j in iterations:
			dispatch(list,11,BIN_COUNT,dt)
			dispatch(list,12,count,dt)
			dispatch(list,13,count,dt)
			dispatch(list,14,count,dt)
			dispatch(list,15,count,dt)
		# Neighbor bins must match the final corrected positions.
		dispatch(list,11,BIN_COUNT,dt)
		dispatch(list,12,count,dt)
		dispatch(list,18,count,dt)
		dispatch(list,16,count,dt)
		dispatch(list,17,count,dt)

func finish(list: int) -> void:
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func step(velocity: PackedVector2Array, cells: Array, habitat, dt: float) -> PackedVector2Array:
	if not ready: return velocity
	var started := Time.get_ticks_usec()
	if not pack_geometry(cells,habitat): return velocity
	var field := PackedFloat32Array()
	field.resize(2560*4)
	for i in 2560:
		var change := velocity[i]-cached[i]
		field[i*4]=change.x; field[i*4+1]=change.y
	update(5,field)
	var packed := Time.get_ticks_usec()
	var list := begin()
	solve(list,dt)
	dispatch(list,21,body_count*ceili(count/128.0)*128,dt)
	dispatch(list,22,body_count,dt)
	dispatch(list,20,2560,dt)
	finish(list)
	var waited := Time.get_ticks_usec()
	var result := rd.buffer_get_data(buffers[5]).to_float32_array()
	cached.resize(2560)
	for i in 2560: cached[i] = Vector2(result[i*4],result[i*4+1])
	var forces := rd.buffer_get_data(buffers[7],0,maxi(1,body_count)*16).to_float32_array()
	for k in body_count:
		if not body_feedback_enabled: continue
		var impulse := Vector2(forces[k*4],forces[k*4+1])
		if not impulse.is_finite() or not is_finite(forces[k*4+2]):
			push_error("Non-finite experimental fluid impulse")
			return velocity
		bodies[k].velocity += impulse/bodies[k].mass
		bodies[k].angular_velocity += forces[k*4+2]/bodies[k].inertia
	metrics = {"pack_us":packed-started,"submit_wait_us":waited-packed,
		"readback_apply_us":Time.get_ticks_usec()-waited,"solvent_particles":count if model=="pbf" else 0,
		"grid_nodes":cols*rows,"iterations":iterations,"field_roundtrip_bytes":2560*32+body_count*16+shape_values.size()*4}
	return cached.duplicate()

func resident_batch(dt: float, ticks: int) -> Dictionary:
	# No field upload/readback, chemistry, cell code or drawing in this measurement.
	var zeros := PackedFloat32Array()
	zeros.resize(2560*4)
	update(5,zeros)
	var started := Time.get_ticks_usec()
	var list := begin()
	for j in ticks: solve(list,dt,false)
	finish(list)
	return {"wall_ms":(Time.get_ticks_usec()-started)/1000.0,"ticks":ticks}

func snapshot() -> Dictionary:
	# Untimed quality readback. Diagnostic density is measured on current positions.
	if model == "pbf":
		var list := begin()
		dispatch(list,30,count,1.0/60)
		dispatch(list,11,BIN_COUNT,1.0/60)
		dispatch(list,12,count,1.0/60)
		dispatch(list,13,count,1.0/60)
		finish(list)
	return {"state":rd.buffer_get_data(buffers[0],0,count*16).to_float32_array(),
		"wall":rd.buffer_get_data(buffers[2]).to_float32_array(),"constraints":rd.buffer_get_data(buffers[4],0,count*16).to_float32_array(),"count":count,
		"model":model,"dx":dx,"cols":cols,"rows":rows,"mass_per_sample":DENSITY*(spacing*spacing if model=="pbf" else dx*dx)}

func close() -> void:
	ready = false
	if rd == null: return
	for resource in [uniform_set,pipeline,shader]:
		if resource.is_valid(): rd.free_rid(resource)
	for resource in buffers:
		if resource.is_valid(): rd.free_rid(resource)
	buffers.clear()
	rd.free()
	rd = null
