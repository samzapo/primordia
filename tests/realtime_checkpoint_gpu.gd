extends "res://tests/network_live.gd"
## Read a committed world into isolated test storage. Never write the source save.
static func observer_credentials(authority,invitation: String) -> Array:
	# Add known bearer aliases only inside the isolated test authority. Preserve
	# every original account/session entry and every cell; a mature pond may
	# have no unclaimed lineage left for a new fixture invitation.
	var retained: Array=[]
	for account in authority.accounts.values():
		if authority.world.cells.any(func(cell):return cell.id==account.selected and not cell.dead):retained.append(account)
	var messages: Array=[]
	for i in 2:
		var message: Dictionary={"op":"hello","snapshot_ack":true,"compact_cytoplasm":true,"cytoplasm_version":2}
		if retained.is_empty():message.invite=invitation
		else:
			var token:=("isolated-aged-observer-"+str(i)).sha256_text()
			authority.accounts[token.sha256_text()]=retained[i%retained.size()]
			message.token=token
		messages.append(message)
	return messages

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
	var connected: bool=await until(func():return sockets.all(func(socket):return socket.get_ready_state()==WebSocketPeer.STATE_OPEN))
	check(connected,"Two isolated saved-world observers connect")
	if not connected:await finish_fixture();return
	var original_accounts: int=host.accounts.size()
	var credentials:=observer_credentials(host,"bounded-aged-checkpoint-fixture")
	print("AGED_OBSERVERS ",JSON.stringify({"original_accounts":original_accounts,"resumed":credentials.filter(func(message):return message.has("token")).size()}))
	for i in sockets.size():sockets[i].send_text(JSON.stringify(credentials[i]))
	var authenticated: bool=await until(func():return not find_message(0,"welcome").is_empty() and not find_message(1,"welcome").is_empty())
	check(authenticated,"Saved-world test observers authenticate with fixture credentials")
	if not authenticated:await finish_fixture();return
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
	check_performance(ratio>=.98 and ratio<=1.02 and p95<=1000.0/host.physics_hz,"Existing saved pond meets the real-time tick budget under full client cameras")
	check(host.world.cells.all(func(cell):return cell.chemistry.particle_count()<=cell.chemistry.MAX_PACKETS),"Every migrated interior retains its bounded finite carrier population")
	host._write_metrics()
	var phases=JSON.parse_string(FileAccess.get_file_as_string(host.store.directory.path_join("health.json")))
	print("AGED_AUTHORITY ",JSON.stringify({"simulation_hz":Engine.physics_ticks_per_second,"tick_budget_ms":1000.0/host.physics_hz,"source_world":saved.world_id,"simulation_wall_ratio":ratio,"tick_p95_ms":p95,"cells":host.world.cells.filter(func(cell):return not cell.dead).size(),"phase_mean_ms":phases.get("tick_phase_mean_ms",{}),"gpu":RenderingServer.get_video_adapter_name()}))
	if ratio<.98 or ratio>1.02 or p95>1000.0/host.physics_hz:await diagnostic_warm_window()
	await finish_fixture()

func finish_fixture() -> void:
	for socket in sockets:socket.close(-1)
	host.running=false;host.listener.stop()
	var gpu=host.world.resident.gpu;gpu.close();await gpu.closed
	var output: String=host.store.directory
	root.remove_child(host);host.free()
	for name in ["world-0.pworld","world-1.pworld","health.json"]:DirAccess.remove_absolute(output.path_join(name))
	DirAccess.remove_absolute(output)
	print("PERFORMANCE_WARNINGS ",performance_warnings)
	print("AGED CHECKPOINT GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
