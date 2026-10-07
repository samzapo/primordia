extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for repeat in 3:
		for distribution in ["uniform","clustered"]:
			for mode in ["grid","collisions","chemistry"]:
				for backend in (["bitonic","radix"] if repeat%2==0 else ["radix","bitonic"]):
					await measure(backend,distribution,mode,repeat)
	quit()
func measure(backend: String,distribution: String,mode: String,repeat: int) -> void:
	var gpu=GPU.new()
	gpu.configure_grid(backend);gpu.configure_interactions("contacts" if mode=="grid" else mode)
	gpu.initialize(Fixture.make(50000,distribution),Fixture.flow())
	var status: Array=await gpu.ready
	if not status[0]: push_error(str(status[1]));quit(1);return
	gpu.advance(1.0/60,0);gpu.snapshot();await gpu.snapshot_ready
	gpu.upload(Fixture.make(50000,distribution));gpu.reaction_tick=0
	gpu.snapshot();await gpu.snapshot_ready
	var initial_builds: int=gpu.grid_builds
	var initial_dispatches: int=gpu.grid_dispatches
	var start:=Time.get_ticks_usec()
	for tick in 60:
		if mode=="grid": RenderingServer.call_on_render_thread(gpu._prepare_grid_rd)
		else: gpu.advance(1.0/60,tick)
	gpu.snapshot();var output: PackedFloat32Array=await gpu.snapshot_ready
	var ms: float=(Time.get_ticks_usec()-start)/60000.0
	var alive:=0
	for i in 50000:
		if output[i*12+7]>=0: alive+=1
	print("GRID_BENCH ",JSON.stringify({"backend":backend,"distribution":distribution,"mode":mode,"repeat":repeat,
		"slots":50000,"alive":alive,"completed_ms_per_step":ms,"grid_builds":gpu.grid_builds-initial_builds,"grid_dispatches":gpu.grid_dispatches-initial_dispatches}))
	gpu.close();await gpu.closed
