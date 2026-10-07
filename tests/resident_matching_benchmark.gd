extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for distribution in ["uniform","clustered"]:
		for mode in ["contacts","collisions","chemistry"]:
			var gpu=GPU.new()
			gpu.configure_interactions(mode)
			gpu.initialize(Fixture.make(50000,distribution),Fixture.flow())
			var status: Array=await gpu.ready
			if not status[0]: push_error(str(status[1]));quit(1);return
			gpu.interact_only();gpu.snapshot();await gpu.snapshot_ready
			var start:=Time.get_ticks_usec()
			for tick in 30:
				gpu.advance(1.0/60,tick)
			gpu.snapshot()
			var output: PackedFloat32Array=await gpu.snapshot_ready
			var ms: float=(Time.get_ticks_usec()-start)/30000.0
			gpu.contact_snapshot()
			var contacts: Dictionary=await gpu.contacts_ready
			var alive:=0
			for i in 50000:
				if output[i*12+7]>=0: alive+=1
			print("MATCHING_BENCH ",JSON.stringify({"distribution":distribution,"mode":mode,"particles":50000,"alive":alive,"completed_ms_per_tick":ms,"last_tick_stats":Array(contacts.stats)}))
			gpu.close();await gpu.closed
	quit()
