extends SceneTree
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func run() -> void:
	preload("res://scripts/resident_fixture.gd").load_native()
	var scene=load("res://scenes/pond.tscn").instantiate()
	scene.use_particle_pool=false
	root.add_child(scene);scene.set_physics_process(false)
	scene._start_resident()
	while scene.resident_starting: await process_frame
	check(scene.world.resident!=null,"Playable GPU initialized")
	scene.manual_zoom=.8
	for i in 90: scene._physics_process(1.0/60)
	for i in 6: await process_frame
	check(scene.resident_view.visible and not scene.batches[0].visible,"GPU artwork replaces CPU pose packing")
	check(scene.world.resident.gpu.readbacks==0,"Full game presentation does not mirror the pool")
	var before: int=scene.world.revision
	scene._toggle_build()
	check(scene.build_open and scene.is_paused(),"Tab enters paused anatomical editor")
	var editor=scene.cell_ui.pathways
	editor.open_cell()
	var packets: Array=scene.world.player.chemistry.particles.duplicate(true)
	editor._process(1)
	scene._physics_process(1.0/60)
	check(editor.visible and packets==scene.world.player.chemistry.particles,"Resident paused pathway editor retains authoritative intracellular particles")
	editor.hide()
	check(scene.world.install("cilia",PI),"Editor installs paid cilia")
	scene._update_world(1)
	check(scene.views[scene.world.player.id].cell==scene.world.player,"Editor clone is the visible cell")
	scene._physics_process(1.0/60)
	check(scene.world.revision==before,"Build pauses both particle and cell backends")
	for i in 8: await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--image-output="): root.get_texture().get_image().save_png(arg.trim_prefix("--image-output="))
	scene._toggle_build()
	check(not scene.build_open,"Tab commits and resumes")
	scene._physics_process(1.0/60)
	check(scene.world.revision==before+1,"First resumed frame advances exactly once")
	scene._toggle_settings()
	check(scene.is_paused(),"Settings menu pauses GPU biology")
	scene._toggle_settings()
	var old=scene.world.resident.gpu
	scene._restart()
	await old.closed
	scene._start_resident()
	var abandoned=scene.resident_controller
	scene._restart() # Cancel an initialization before its ready callback arrives.
	scene._start_resident()
	while scene.resident_starting: await process_frame
	for i in 3: await process_frame
	check(abandoned.closing and abandoned.gpu.rd==null,"Cancelled startup cannot replace the new world or leak its device resources")
	check(scene.world.resident!=null and scene.world.time==0,"Restart creates a fresh resident habitat")
	scene._physics_process(1.0/60)
	check(scene.world.resident.gpu.readbacks==0,"Restart keeps authoritative residency")
	scene.world.resident.close()
	await scene.world.resident.gpu.closed
	scene.music.enabled=false;scene.music.player.stop()
	scene.queue_free()
	await process_frame
	print("RESIDENT_UI_VALIDATION ",checks," checks")
	quit()
