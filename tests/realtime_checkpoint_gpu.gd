extends "res://tests/network_live.gd"
## Read a committed world into isolated test storage. Never write the source save.
func _initialize() -> void:run.call_deferred()
func run() -> void:
	root.size=Vector2i(64,64)
	var directory:=OS.get_environment("PRIMORDIA_VERIFY_CHECKPOINT_DIR")
	var store=preload("res://scripts/network/world_store.gd").new();store.directory=directory
	var saved: Dictionary=store.load_latest()
	check(not saved.is_empty() and store.last_error=="","Existing checkpoint is readable for an isolated performance check")
	if saved.is_empty():quit(1);return
	var codec=preload("res://scripts/network/state_codec.gd").new()
	var data=codec.restore(saved.graph)
	check(data is Dictionary and data.get("world") is Sim,"Existing graph migrates in memory without touching the source")
	if not data is Dictionary:quit(1);return
	for audit in codec.migration_audit:
		check(absf(audit.before_material-audit.after_material)<.000001*maxf(1,audit.before_material),"Legacy body conversion preserves represented organic material")
	host=Host.new();host.cpu=false;host.port=18000+OS.get_process_id()%20000
	host.store.directory=ProjectSettings.globalize_path("res://build/aged-network-"+str(OS.get_process_id()))
	# Exercise the real restore/startup boundary and the complete account graph,
	# not just a detached simulation with a new world identity.
	check(host.store.save(saved),"Isolated copy retains the complete saved world and accounts")
	OS.set_environment("PRIMORDIA_ACCESS_KEYS_FILE","");OS.set_environment("PRIMORDIA_INVITE","bounded-aged-checkpoint-fixture")
	root.add_child(host)
	check(await until(func():return host.running),"Saved-world GPU authority starts in isolated storage")
	if not host.running:quit(1);return
	if saved.get("food_vacuole_version",0)>=1 and saved.get("biochemistry_version",0)>=1:
		check(host.cell_retention.get("ok",false),"Resident startup retains every original saved cell before its first tick")
	host.world.profiling=true
	for i in 2:
		var socket:=WebSocketPeer.new();socket.inbound_buffer_size=Protocol.MAX_FRAME;socket.outbound_buffer_size=65536
		sockets.append(socket);socket.connect_to_url("ws://127.0.0.1:"+str(host.port))
	check(await until(func():return sockets.all(func(socket):return socket.get_ready_state()==WebSocketPeer.STATE_OPEN)),"Two isolated saved-world observers connect")
	for socket in sockets:socket.send_text(JSON.stringify({"op":"hello","invite":"bounded-aged-checkpoint-fixture","snapshot_ack":true,"compact_cytoplasm":true,"cytoplasm_version":2}))
	check(await until(func():return not find_message(0,"welcome").is_empty() and not find_message(1,"welcome").is_empty()),"Saved-world test observers authenticate with fixture credentials")
	for i in 2:
		var welcome:=find_message(i,"welcome")
		var cell=host._selected(host.accounts[welcome.token.sha256_text()])
		camera_reports[i]={"op":"view","rect":[cell.position.x,cell.position.y,Sim.VIEW.x/.8/2,Sim.VIEW.y/.8/2],"perception":"exteroception" if i==0 else "interoception"}
	check(await until(func():return host.world.camera_views.size()==1 and not host.world.interoceptive_cells.is_empty()),"Saved world prepares full exterior and interior camera interests")
	var wall_start:=Time.get_ticks_usec();var sim_start: float=host.world.time
	while Time.get_ticks_usec()-wall_start<12000000:poll();await process_frame
	var ratio: float=(host.world.time-sim_start)/((Time.get_ticks_usec()-wall_start)/1000000.0)
	var timings: Array=host.tick_samples.duplicate();timings.sort()
	var p95: float=timings[mini(timings.size()-1,int(timings.size()*.95))]
	check(ratio>=.98 and ratio<=1.02 and p95<=1000.0/host.physics_hz,"Existing saved pond meets the real-time tick budget under full client cameras")
	check(host.world.cells.all(func(cell):return cell.chemistry.particle_count()<=cell.chemistry.MAX_PACKETS),"Every migrated interior retains its bounded finite carrier population")
	host._write_metrics()
	var phases=JSON.parse_string(FileAccess.get_file_as_string(host.store.directory.path_join("health.json")))
	print("AGED_AUTHORITY ",JSON.stringify({"simulation_hz":Engine.physics_ticks_per_second,"tick_budget_ms":1000.0/host.physics_hz,"source_world":saved.world_id,"simulation_wall_ratio":ratio,"tick_p95_ms":p95,"cells":host.world.cells.filter(func(cell):return not cell.dead).size(),"phase_mean_ms":phases.get("tick_phase_mean_ms",{}),"gpu":RenderingServer.get_video_adapter_name()}))
	for socket in sockets:socket.close(-1)
	host.running=false;host.listener.stop()
	var gpu=host.world.resident.gpu;gpu.close();await gpu.closed
	var output: String=host.store.directory
	root.remove_child(host);host.free()
	for name in ["world-0.pworld","world-1.pworld","health.json"]:DirAccess.remove_absolute(output.path_join(name))
	DirAccess.remove_absolute(output)
	print("AGED CHECKPOINT GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
