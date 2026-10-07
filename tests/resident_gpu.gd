extends SceneTree
const GPU = preload("res://scripts/resident_particles.gd")
const Fixture = preload("res://scripts/resident_fixture.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Fixture.load_native()
	var results: Array = []
	for count in [127,128,129,513]:
		var data := Fixture.make(count,"seam")
		var gpu=GPU.new()
		gpu.initialize(data,Fixture.flow())
		var ready_result: Array=await gpu.ready
		if not ready_result[0]:
			push_error(str(ready_result[1]));gpu.close();await gpu.closed;quit(1);return
		var reference := data
		for tick in 12:
			var dt := 0.7 if tick==6 else 1.0/60
			gpu.advance(dt,tick)
			reference=Fixture.advance(reference,Fixture.flow(),dt,tick)
		await process_frame
		await RenderingServer.frame_post_draw
		gpu.snapshot()
		var actual: PackedFloat32Array=await gpu.snapshot_ready
		var result := Fixture.compare(reference,actual)
		result["count"]=count
		result["dispatches"]=gpu.dispatches
		results.append(result)
		gpu.close();await gpu.closed
		if not result.passed:
			push_error("Resident GPU reference mismatch: "+JSON.stringify(result));quit(1);return
	# Native multithreaded counterpart at actual parallel workload, 120 ticks.
	if ClassDB.class_exists("PrimordiaResidentReference"):
		for config in [[5000,120,"clustered"],[50000,360,"uniform"]]:
			if not await dense_check(config,results):
				quit(1);return
	print("RESIDENT_VALIDATION ",JSON.stringify(results))
	quit()
func dense_check(config: Array, results: Array) -> bool:
	var data := Fixture.make(config[0],config[2])
	var cpu=ClassDB.instantiate("PrimordiaResidentReference")
	cpu.configure(data,Fixture.flow(),8)
	var gpu=GPU.new()
	gpu.initialize(data,Fixture.flow())
	var status: Array=await gpu.ready
	if not status[0]:
		push_error(str(status[1]));gpu.close();await gpu.closed;return false
	for tick in int(config[1]):
		gpu.advance(1.0/60,tick);cpu.advance(1.0/60,tick)
		if tick%8==0: await process_frame
	await RenderingServer.frame_post_draw
	gpu.snapshot()
	var actual: PackedFloat32Array=await gpu.snapshot_ready
	var result := Fixture.compare(cpu.snapshot(),actual)
	result["count"]=config[0];result["ticks"]=config[1]
	results.append(result)
	gpu.close();await gpu.closed
	if not result.passed:
		push_error("Dense resident GPU/native mismatch: "+JSON.stringify(result));return false
	return true
