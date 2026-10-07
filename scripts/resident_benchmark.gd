extends Node2D
## Standalone particle/rendering experiments; does not run game ecology.
signal finished(report: Dictionary)
const GPU = preload("res://scripts/resident_particles.gd")
const Fixture = preload("res://scripts/resident_fixture.gd")
const Art = preload("res://scripts/particle_art.gd")
var backend := "gpu"
var interactions := "off"
var grid_backend := "radix"
var warmup_alive := 0
var count := 50000
var threads := 1
var distribution := "uniform"
var frames := 300
var seconds := 0.0
var fps_limit := 0
var output := "user://resident-report.json"
var image_output := ""
var rows: Array[Dictionary] = []
var gpu
var cpu
var batch: MultiMeshInstance2D
var tick := 0
var warmup := 60
var running := false
var previous := 0
var started := 0
var main_usec := 0
var old_fps := 0
var initial := PackedFloat32Array()
var camera := Vector2(2048,1280)
var _ending := false
var warmup_complete := false
func begin() -> void:
	Fixture.load_native()
	old_fps=Engine.max_fps
	if interactions not in ["off","contacts","collisions","chemistry"] or grid_backend not in ["bitonic","radix"] or (interactions!="off" and backend!="gpu") or backend not in ["gpu","cpu-texture","cpu-multimesh"] or count<1 or count>100000 or threads<1 or threads>8 or frames<2 or frames>10000 or seconds<0 or seconds>1800 or not is_finite(seconds) or fps_limit not in [0,30,60] or distribution not in ["uniform","clustered","seam"]:
		_fail("Invalid benchmark options")
		return
	if seconds>0 and fps_limit==0:
		_fail("Sustained runs require a 30 or 60 FPS cap for bounded, comparable work")
		return
	if backend!="gpu" and not ClassDB.class_exists("PrimordiaResidentReference"):
		_fail("Native CPU reference unavailable on this build; no script-speed substitution")
		return
	initial=Fixture.make(count,distribution)
	if distribution=="seam": camera=Vector2.ZERO
	gpu=GPU.new()
	gpu.configure_grid(grid_backend);gpu.configure_interactions(interactions)
	gpu.ready.connect(_on_ready,CONNECT_ONE_SHOT)
	gpu.initialize(initial,Fixture.flow())
func _on_ready(ok: bool, reason: String) -> void:
	if _ending: return
	if not ok:
		await _cleanup()
		_fail(reason)
		return
	if backend!="gpu":
		cpu=ClassDB.instantiate("PrimordiaResidentReference")
		if not cpu.configure(initial,Fixture.flow(),threads):
			await _cleanup()
			_fail("Invalid CPU fixture")
			return
	_build_view()
	old_fps=Engine.max_fps
	Engine.max_fps=fps_limit
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	RenderingServer.frame_post_draw.connect(_post)
	running=true
	previous=Time.get_ticks_usec()
func _build_view() -> void:
	batch=MultiMeshInstance2D.new()
	var mesh := QuadMesh.new()
	mesh.size=Vector2.ONE
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_2D
	multi.use_colors=true
	multi.mesh=mesh
	multi.instance_count=count
	var transforms := PackedFloat32Array()
	transforms.resize(count*12)
	for i in count:
		transforms[i*12]=1;transforms[i*12+5]=1
		for j in range(8,12): transforms[i*12+j]=1
	multi.buffer=transforms
	multi.custom_aabb=AABB(Vector3(-4096,-2560,-1),Vector3(8192,5120,2))
	batch.multimesh=multi
	var atlas := Image.create(96*11,96,false,Image.FORMAT_RGBA8)
	for i in 11:
		var image: Image=Art.texture(i).get_image()
		image.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(image,Rect2i(0,0,96,96),Vector2i(i*96,0))
	atlas.generate_mipmaps()
	batch.texture=ImageTexture.create_from_image(atlas)
	batch.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/resident_particles.gdshader")
	material.set_shader_parameter("state_texture",gpu.texture)
	material.set_shader_parameter("camera",camera)
	material.set_shader_parameter("cpu_instances",backend=="cpu-multimesh")
	batch.material=material
	batch.position=get_viewport_rect().size*0.5
	batch.scale=Vector2.ONE*0.8
	add_child(batch)
func _process(_delta: float) -> void:
	if not running: return
	var begin_usec := Time.get_ticks_usec()
	if backend=="gpu": gpu.advance(1.0/60,tick)
	else:
		cpu.advance(1.0/60,tick)
		if backend=="cpu-texture": gpu.upload(cpu.snapshot())
		else: batch.multimesh.buffer=cpu.instances(camera)
	main_usec=Time.get_ticks_usec()-begin_usec
	tick+=1
func _post() -> void:
	if not running: return
	var now := Time.get_ticks_usec()
	if not warmup_complete:
		previous=now
		if tick>=warmup:
			running=false
			_start_measurement.call_deferred()
		return
	if started==0: started=previous
	var viewport := get_viewport().get_viewport_rid()
	rows.append({"wall_ms":(now-previous)/1000.0,"main_work_ms":main_usec/1000.0,"elapsed_s":(now-started)/1000000.0,
		"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),
		"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"tick":tick})
	previous=now
	if (seconds>0 and (now-started)/1000000.0>=seconds) or (seconds==0 and rows.size()>=frames):
		running=false
		_finish.call_deferred()
func _start_measurement() -> void:
	gpu.snapshot()
	var warm: PackedFloat32Array=await gpu.snapshot_ready
	for k in range(0,warm.size(),12):
		if warm[k+7]>=0: warmup_alive+=1
	# Fence warmup before starting the measured window; no readback inside it.
	get_viewport().get_texture().get_image()
	if _ending: return
	warmup_complete=true
	previous=Time.get_ticks_usec()
	started=previous
	running=true
func _finish() -> void:
	_ending=true
	RenderingServer.frame_post_draw.disconnect(_post)
	var drain_start := Time.get_ticks_usec()
	var tail: PackedFloat32Array
	if backend=="cpu-multimesh": tail=cpu.snapshot()
	else:
		gpu.snapshot()
		tail=await gpu.snapshot_ready
	var final_image := get_viewport().get_texture().get_image()
	var drain_ms := (Time.get_ticks_usec()-drain_start)/1000.0
	var valid := Fixture.compare(tail,tail)
	var material := 0.0
	var alive := 0
	for k in range(0,tail.size(),12):
		material+=tail[k+9]
		if tail[k+7]>=0: alive+=1
	var material_before := 0.0
	for k in range(0,initial.size(),12): material_before+=initial[k+9]
	var compared := {}
	if backend=="cpu-texture": compared=Fixture.compare(cpu.snapshot(),tail)
	# No timing claims for correctness readback or screenshot.
	if image_output!="": final_image.save_png(image_output)
	var report := {"backend":backend,"interactions":interactions,"grid_backend":grid_backend,"grid_builds":gpu.grid_builds,"grid_dispatches":gpu.grid_dispatches,
		"particles":count,"warmup_alive":warmup_alive,"final_alive":alive,"threads":threads,"distribution":distribution,"zoom":0.8,
		"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),
		"os":OS.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":str(get_viewport_rect().size),
		"fps_limit":fps_limit,"fixed_dt":1.0/60,"warmup_ticks":warmup,"measured_ticks":rows.size(),"total_ticks":tick,"measured_simulation_seconds":rows.size()/60.0,
		"rows":rows,"finite":valid.finite,"material_before":material_before,"material_after":material,"upload_bytes":gpu.upload_bytes,
		"dispatches":gpu.dispatches,"state_readbacks":gpu.readbacks,"viewport_readbacks":2,"timed_window_readbacks":0,"final_drain_and_readback_ms":drain_ms,"texture_roundtrip":compared,
		"scope":"Synthetic GPU transport/drawing with explicitly selected contact/reaction mode. No cells, feeding, physiology, music or live catch-up. Not game FPS. Chemistry may shrink the population; counter-based diagnostic noise is not gameplay RNG.",
		"thermal":"External device telemetry required; no thermal or energy claim from frame timings alone."}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: report["error"]="Cannot write "+output
	else: file.store_string(JSON.stringify(report))
	await _cleanup()
	print("RESIDENT_REPORT ",output)
	finished.emit(report)
func _cleanup() -> void:
	if batch!=null:
		batch.material=null
		batch.queue_free()
	if gpu!=null:
		gpu.close()
		await gpu.closed
	Engine.max_fps=old_fps
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),false)
func cancel() -> void:
	if _ending: return
	_ending=true
	running=false
	if RenderingServer.frame_post_draw.is_connected(_post): RenderingServer.frame_post_draw.disconnect(_post)
	await _cleanup()
	finished.emit({"error":"Cancelled; partial run excluded"})
func _fail(reason: String) -> void:
	finished.emit({"error":reason})
