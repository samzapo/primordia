extends "res://tests/network_live.gd"
## Tick-only diagnostic on an isolated copy. Never mutates the source or joins production.
func _initialize() -> void:run.call_deferred()
func run() -> void:
	root.size=Vector2i(64,64)
	var cap:=-1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--particle-limit="):cap=int(arg.trim_prefix("--particle-limit="))
	var source=preload("res://scripts/network/world_store.gd").new()
	source.directory=OS.get_environment("PRIMORDIA_VERIFY_CHECKPOINT_DIR")
	var saved: Dictionary=source.load_latest()
	check(not saved.is_empty() and source.last_error=="","Readable source checkpoint")
	if saved.is_empty():quit(1);return
	var before:=preload("res://scripts/network/cell_retention.gd").manifest(saved)
	var ref: int=saved.graph.root.world["$ref"]
	var fields: Dictionary=saved.graph.objects[ref].fields
	var packets: Array=fields.particles["$array"].filter(func(packet):return packet.get("alive",false))
	var original:=packets.size()
	for packet in packets:Sim.repair_spent_charge(packet)
	var order: Array=[]
	for i in packets.size():order.append(i)
	var random:=RandomNumberGenerator.new();random.seed=76101016
	for i in range(order.size()-1,0,-1):
		var j:=random.randi_range(0,i);var old=order[i];order[i]=order[j];order[j]=old
	var keep: Dictionary={}
	for i in (mini(cap,order.size()) if cap>=0 else order.size()):keep[order[i]]=true
	var selected: Array=[];var removed:=0.0
	for i in packets.size():
		if keep.has(i):selected.append(packets[i])
		else:removed+=float(packets[i].get("amount",0))*Sim.Catalog.material(int(packets[i].kind))
	fields.particles["$array"]=selected
	fields.respiration_loss=float(fields.get("respiration_loss",0))+removed
	var after:=preload("res://scripts/network/cell_retention.gd").manifest(saved)
	check(preload("res://scripts/network/cell_retention.gd").compare(before,after).ok,"Probe preserves every saved body")
	host=Host.new();host.cpu=false;host.port=18000+OS.get_process_id()%20000
	host.store.directory=OS.get_environment("PRIMORDIA_CAPACITY_PROBE_STATE")
	check(host.store.directory!="" and host.store.directory!=source.directory,"Separate disposable state")
	check(host.store.save(saved),"Saved-world copy")
	OS.set_environment("PRIMORDIA_PARTICLE_LIMIT","0")
	OS.set_environment("PRIMORDIA_ACCESS_KEYS_FILE","");OS.set_environment("PRIMORDIA_INVITE","private-capacity-fixture")
	root.add_child(host)
	check(await until(func():return host.running),"Copied GPU authority starts")
	if not host.running:quit(1);return
	check(host.cell_retention.get("ok",false),"All saved cells survive startup")
	host.world.profiling=true
	for i in 2:
		var socket:=WebSocketPeer.new();socket.inbound_buffer_size=Protocol.MAX_FRAME;socket.outbound_buffer_size=65536
		sockets.append(socket);socket.connect_to_url("ws://127.0.0.1:"+str(host.port))
	check(await until(func():return sockets.all(func(socket):return socket.get_ready_state()==WebSocketPeer.STATE_OPEN)),"Two isolated observers")
	for socket in sockets:socket.send_text(JSON.stringify({"op":"hello","invite":"private-capacity-fixture","snapshot_ack":true,"compact_cytoplasm":true,"cytoplasm_version":2}))
	check(await until(func():return not find_message(0,"welcome").is_empty() and not find_message(1,"welcome").is_empty()),"Fixture-only credentials")
	for i in 2:
		var welcome:=find_message(i,"welcome")
		var cell=host._selected(host.accounts[welcome.token.sha256_text()])
		camera_reports[i]={"op":"view","rect":[cell.position.x,cell.position.y,Sim.VIEW.x/.8/2,Sim.VIEW.y/.8/2],"perception":"exteroception"}
	check(await until(func():return host.world.camera_views.size()==2 and host.world.resident.streaming.queue_depth==0),"Two full-detail exterior cameras")
	var warming:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-warming<4000000:poll();await process_frame
	host.tick_samples.clear()
	var wall_start:=Time.get_ticks_usec();var sim_start: float=host.world.time
	while Time.get_ticks_usec()-wall_start<12000000:poll();await process_frame
	var ratio: float=(host.world.time-sim_start)/((Time.get_ticks_usec()-wall_start)/1000000.0)
	var timings: Array=host.tick_samples.duplicate();timings.sort()
	var p95: float=timings[mini(timings.size()-1,int(timings.size()*.95))]
	check(host.world.resident!=null,"Hardware resident backend stays active")
	host._write_metrics()
	var metrics=JSON.parse_string(FileAccess.get_file_as_string(host.store.directory.path_join("health.json")))
	var actual: int=host.world.particle_snapshots().filter(func(packet):return packet.get("alive",false)).size()
	print("PARTICLE_CAPACITY ",JSON.stringify({"requested_limit":cap,"source_external":original,"starting_external":selected.size(),"ending_external":actual,"cells":host.world.cells.filter(func(cell):return not cell.dead).size(),"views":host.world.camera_views.size(),"simulation_hz":host.physics_hz,"simulation_wall_ratio":ratio,"tick_p95_ms":p95,"target_tick_ms":1000./host.physics_hz,"meets_cadence":ratio>=.98 and ratio<=1.02 and p95<=1000./host.physics_hz,"phase_mean_ms":metrics.get("tick_phase_mean_ms",{}),"snapshot_encode_ms":metrics.get("snapshot_encode_ms_mean",0),"gpu":RenderingServer.get_video_adapter_name()}))
	for socket in sockets:socket.close(-1)
	host.running=false;host.listener.stop()
	var gpu=host.world.resident.gpu;gpu.close();await gpu.closed
	root.remove_child(host);host.free()
	print("PARTICLE CAPACITY: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
