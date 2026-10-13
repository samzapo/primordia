extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Host=preload("res://scripts/network/world_host.gd")
const Protocol=preload("res://scripts/network/protocol.gd")
var failures:=0
var assertions:=0
var host
var sockets: Array=[]
var messages: Array=[[],[]]
var deadline:=0
var keepalive_at:=0
func check(value: bool,message: String) -> void:
	assertions+=1
	if not value: failures+=1;push_error("FAIL: "+message)
func _initialize() -> void: run.call_deferred()
func poll() -> void:
	if Time.get_ticks_msec()-keepalive_at>=500:
		keepalive_at=Time.get_ticks_msec()
		for i in sockets.size():
			if sockets[i].get_ready_state()==WebSocketPeer.STATE_OPEN and not find_message(i,"welcome").is_empty(): sockets[i].send_text(JSON.stringify({"op":"ping"}))
	for i in sockets.size():
		sockets[i].poll()
		while sockets[i].get_available_packet_count()>0: messages[i].append(Protocol.unpack(sockets[i].get_packet()))
func until(predicate: Callable) -> bool:
	var end:=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<end:
		poll()
		if predicate.call(): return true
		await process_frame
	return false
func find_message(index: int,kind: String,sequence: int=-1) -> Dictionary:
	for message in messages[index]:
		if message.get("kind","")==kind and (sequence<0 or message.get("sequence",-2)==sequence):return message
	return {}
func run() -> void:
	host=Host.new();host.cpu=not ("--gpu" in OS.get_cmdline_user_args())
	host.port=18000+OS.get_process_id()%20000
	host.store.directory=ProjectSettings.globalize_path("res://build/network-live-"+str(OS.get_process_id()))
	var full_world:= "--full-world" in OS.get_cmdline_user_args()
	var sim=Sim.new(81,0,full_world)
	if not full_world:
		sim.cells=[sim.player]
		sim.player.position=Vector2(2048,1280);sim.player.previous_position=sim.player.position
		var other=Sim.Cell.new(1,Vector2(900,1200));sim.cells.append(other);sim.next_id=2
		sim.habitat_geometry=Sim.Habitat.new(81,sim.cells)
		sim.spawn_particle(0,sim.player.position+Vector2(100,0),Vector2.ZERO,.3)
		sim.spawn_particle(0,other.position+Vector2(100,0),Vector2.ZERO,.3)
		sim.grid.rebuild(sim.particles)
	host.world=sim
	var personal_keys:="--personal-keys" in OS.get_cmdline_user_args()
	var fixture_keys:=["personal-key-fixture-one-256", "personal-key-fixture-two-256"]
	var key_file: String=host.store.directory+"-keys.json"
	if personal_keys:
		DirAccess.make_dir_recursive_absolute(host.store.directory)
		var registry:=FileAccess.open(key_file,FileAccess.WRITE)
		registry.store_string(JSON.stringify({"hashes":[fixture_keys[0].sha256_text(),fixture_keys[1].sha256_text()]}));registry.close()
		OS.set_environment("PRIMORDIA_ACCESS_KEYS_FILE",key_file)
	root.add_child(host)
	check(await until(func():return host.running),"world authority starts")
	if not host.running: quit(1);return
	for i in 2:
		var socket:=WebSocketPeer.new();socket.inbound_buffer_size=Protocol.MAX_FRAME;socket.outbound_buffer_size=65536
		sockets.append(socket);socket.connect_to_url("ws://127.0.0.1:"+str(host.port))
	check(await until(func():return sockets.all(func(s):return s.get_ready_state()==WebSocketPeer.STATE_OPEN)),"two real WebSocket connections")
	for i in sockets.size():sockets[i].send_text(JSON.stringify({"op":"hello","invite":fixture_keys[i] if personal_keys else OS.get_environment("PRIMORDIA_INVITE")}))
	check(await until(func():return not find_message(0,"welcome").is_empty() and not find_message(1,"welcome").is_empty()),"distinct lineage accounts authenticated")
	var welcome0:=find_message(0,"welcome")
	var welcome1:=find_message(1,"welcome")
	check(welcome0.cell!=welcome1.cell,"accounts own distinct cells")
	check(await until(func():return host.world.camera_views.size()==2),"camera union tracks both clients")
	check(await until(func():return messages[0].any(func(m):return m.get("kind","")=="snapshot" and m.get("particles",PackedByteArray()).size()>0 and not m.get("warming",true))),"bounded particle publication reaches client")
	var account: Dictionary=host.accounts[welcome0.token.sha256_text()]
	var before_points: int=account.evolution.points
	var command={"op":"command","epoch":host.epoch,"sequence":1,"edit":0,"cell":welcome0.cell,"action":"install","args":{"kind":"propulsion","angle":2.0}}
	sockets[0].send_text(JSON.stringify(command))
	check(await until(func():return not find_message(0,"result",1).is_empty()),"paid edit acknowledged")
	check(find_message(0,"result",1).ok,"paid anatomy installed")
	check(account.evolution.points==before_points-1,"ordinary AP debit occurs exactly once")
	sockets[0].send_text(JSON.stringify(command))
	check(await until(func():return messages[0].filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==1).size()>=2),"duplicate command receives retained receipt")
	check(account.evolution.points==before_points-1,"retry does not debit AP twice")
	sockets[1].send_text(JSON.stringify({"op":"command","epoch":host.epoch,"sequence":1,"edit":0,"cell":welcome0.cell,"action":"remove","args":{"id":0}}))
	check(await until(func():return not find_message(1,"result",1).is_empty()),"foreign-cell command answered")
	check(not find_message(1,"result",1).ok,"another lineage cannot edit this cell")
	var before: float=host.world.time
	host.world.begin_build()
	check(host.world.build_original==null,"shared editor never clones or pauses authority")
	check(await until(func():return host.world.time>before+.05),"clock advances during editor use")
	check(host.checkpoint(),"account and world checkpoint completes")
	var saved: Dictionary=host.store.load_latest()
	if not host.cpu: check(saved.stream_rng==PackedInt64Array([host.world.resident.streaming.random.seed,host.world.resident.streaming.random.state]),"cold transport random stream is checkpointed")
	var restored=preload("res://scripts/network/state_codec.gd").new().restore(saved.graph)
	check(restored.accounts[welcome0.token.sha256_text()].sequence==1,"idempotency sequence survives restart")
	check(restored.accounts[welcome0.token.sha256_text()].lineage==restored.world.family_ledgers[0],"ownership ledger references survive checkpoint")
	if personal_keys:
		var rejected:=WebSocketPeer.new();rejected.connect_to_url("ws://127.0.0.1:"+str(host.port))
		sockets.append(rejected);messages.append([])
		check(await until(func():return rejected.get_ready_state()==WebSocketPeer.STATE_OPEN),"access-key rejection socket opens")
		rejected.send_text(JSON.stringify({"op":"hello","invite":"wrong-personal-key"}))
		check(await until(func():return rejected.get_ready_state()==WebSocketPeer.STATE_CLOSED),"invalid key is rejected")
		check(rejected.get_close_code()==1008 and rejected.get_close_reason()=="Invalid access key","invalid key has an actionable policy close")
		var count_before: int=host.accounts.size()
		var selected_before: int=account.selected
		var resume:=WebSocketPeer.new();resume.inbound_buffer_size=Protocol.MAX_FRAME;resume.connect_to_url("ws://127.0.0.1:"+str(host.port))
		sockets.append(resume);messages.append([])
		check(await until(func():return resume.get_ready_state()==WebSocketPeer.STATE_OPEN),"key resumes from another browser")
		resume.send_text(JSON.stringify({"op":"hello","invite":fixture_keys[0]}))
		check(await until(func():return not find_message(3,"welcome").is_empty()),"personal key resumes without the old browser token")
		var resumed:=find_message(3,"welcome")
		check(host.accounts.size()==count_before and resumed.cell==selected_before,"a reused key does not claim a second lineage")
		check(resumed.token!=welcome0.token and host.accounts[resumed.token.sha256_text()]==account,"resume rotates the bearer and preserves the account")
		check(account.sequence==1 and account.evolution.points==before_points-1,"resume preserves paid edit receipts and costs")
		var durable=preload("res://scripts/network/state_codec.gd").new().restore(host.store.load_latest().graph)
		check(durable.accounts.has(resumed.token.sha256_text()) and not durable.accounts.has(welcome0.token.sha256_text()) and durable.accounts[resumed.token.sha256_text()].sequence==1,"rotated account and receipts are durable before welcome")
		check(await until(func():return sockets[0].get_ready_state()==WebSocketPeer.STATE_CLOSED),"previous browser is disconnected on key resume")
		check(sockets[0].get_close_reason()=="Session resumed elsewhere","resume tells the old browser why it disconnected")
	for socket in sockets:socket.close(-1)
	check(await until(func():return host.world.camera_views.is_empty()),"disconnect removes every detailed camera")
	before=host.world.time
	check(await until(func():return host.world.time>before+.05),"zero-client world continues")
	if not host.cpu: check(host.world.resident!=null and host.startup_error=="","GPU remains authoritative through live edits, save and every camera disconnect")
	host.running=false;host.listener.stop()
	if host.world.resident!=null:
		var gpu=host.world.resident.gpu
		gpu.close()
		await gpu.closed
	root.remove_child(host);host.free()
	for path in ["world-0.pworld","world-1.pworld","health.json"]:
		DirAccess.remove_absolute(saved_directory().path_join(path))
	DirAccess.remove_absolute(saved_directory())
	if personal_keys:
		DirAccess.remove_absolute(key_file)
		OS.unset_environment("PRIMORDIA_ACCESS_KEYS_FILE")
	print("NETWORK LIVE: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
func saved_directory() -> String:
	return ProjectSettings.globalize_path("res://build/network-live-"+str(OS.get_process_id()))
