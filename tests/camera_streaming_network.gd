extends SceneTree
const Host=preload("res://scripts/network/world_host.gd")
const Sim=preload("res://scripts/simulation.gd")
const Protocol=preload("res://scripts/network/protocol.gd")
const Delivery=preload("res://scripts/network/camera_delivery.gd")
var host
var sockets: Array=[]
var messages: Array=[[],[]]
var cameras: Array=[Vector4(1000,1280,200,200),Vector4(3000,1280,200,200)]
var last_view:=0
var assertions:=0
var failures:=0
var ready_while_loading:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func poll() -> void:
	if Time.get_ticks_msec()-last_view>=200:
		last_view=Time.get_ticks_msec()
		for i in sockets.size():
			if sockets[i].get_ready_state()==WebSocketPeer.STATE_OPEN and messages[i].any(func(m):return m.get("kind","")=="welcome"):
				var v: Vector4=cameras[i]
				sockets[i].send_text(JSON.stringify({"op":"view","rect":[v.x,v.y,v.z,v.w]}))
	for i in sockets.size():
		sockets[i].poll()
		while sockets[i].get_available_packet_count()>0:
			var message:=Protocol.unpack(sockets[i].get_packet())
			messages[i].append(message)
			if message.get("kind","")=="snapshot" and message.get("serial",0)>0:
				sockets[i].send_text(JSON.stringify({"op":"snapshot_ack","serial":message.serial,"epoch":message.epoch}))
				if i==0 and host.world.resident!=null and host.world.resident.streaming.queue_depth>0:ready_while_loading+=1
func until(predicate: Callable,seconds: float=15) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		poll()
		if predicate.call():return true
		await process_frame
	return false
func connect_client(index: int) -> void:
	var socket:=WebSocketPeer.new();sockets.append(socket)
	socket.connect_to_url("ws://127.0.0.1:"+str(host.port))
	check(await until(func():return socket.get_ready_state()==WebSocketPeer.STATE_OPEN),"Fixture socket opens")
	socket.send_text(JSON.stringify({"op":"hello","invite":OS.get_environment("PRIMORDIA_INVITE"),"protocol":Protocol.VERSION,"snapshot_ack":true,"death_events":true,"cytoplasm_version":2}))
	check(await until(func():return messages[index].any(func(m):return m.get("kind","")=="welcome")),"Fixture authenticates without production accounts")
func latest(index: int) -> Dictionary:
	var frames: Array=messages[index].filter(func(m):return m.get("kind","")=="snapshot" and m.get("serial",0)>0)
	return frames[-1] if not frames.is_empty() else {}
func has_marker(frame: Dictionary) -> bool:
	var records: PackedByteArray=frame.get("particles",PackedByteArray())
	for at in range(0,records.size(),32):
		var p:=Vector2(records.decode_float(at),records.decode_float(at+4))
		if Sim.Medium.offset(Vector2(1420,1280),p).length()<70:return true
	return false
func run() -> void:
	root.size=Vector2i(64,64)
	var beacon:=ColorRect.new();beacon.size=Vector2(8,8);root.add_child(beacon);await process_frame;await process_frame
	host=Host.new();host.cpu=not ("--gpu" in OS.get_cmdline_user_args())
	host.port=18000+OS.get_process_id()%20000
	host.store.directory=ProjectSettings.globalize_path("res://build/camera-network-"+str(OS.get_process_id()))
	var sim=Sim.new(81,0,false);sim.cells=[sim.player]
	sim.player.position=Vector2(1000,1280);sim.player.previous_position=sim.player.position
	var other=Sim.Cell.new(1,Vector2(3000,1280));sim.cells.append(other);sim.next_id=2
	sim.habitat_geometry=Sim.Habitat.new(81,sim.cells)
	for i in 12:sim.spawn_particle(1,Vector2(1420+i%4*3,1275+i/4*3),Vector2.ZERO,.02)
	for i in 4800:sim.spawn_particle(1,Vector2(2760+i%120*4,1200+i/120*4),Vector2.ZERO,.02)
	sim.grid.rebuild(sim.particles);host.world=sim;root.add_child(host)
	check(await until(func():return host.running,30),"Isolated authority starts")
	if not host.running:quit(1);return
	await connect_client(0)
	check(await until(func():return not latest(0).is_empty() and latest(0).get("camera",Vector4.ZERO)==cameras[0] and has_marker(latest(0))),"The real socket receives particles beyond the current screen before panning")
	var frame:=latest(0)
	check(frame.has("coverage") and Delivery.covers(frame.coverage,cameras[0]),"Snapshot declares its captured prepared coverage")
	check(frame.census.buffered_particles==frame.particles.size()/32 and frame.census.camera_particles<frame.census.buffered_particles,"Visible camera count stays distinct from prefetched particles")
	var handles: Dictionary={}
	for at in range(0,frame.particles.size(),32):
		var handle:=Vector2i(frame.particles.decode_u32(at+24),frame.particles.decode_u32(at+28))
		handles[handle]=true
	check(handles.size()==frame.particles.size()/32,"Prefetched regions contain each actual particle identity once")
	var pan:=Vector4(1240,1280,200,200)
	check(Delivery.covers(frame.coverage,pan) and has_marker(frame),"A240-unit pan can show the real marker immediately from the already-received frame")
	cameras[0]=pan
	var tick: int=frame.tick
	check(await until(func():return latest(0).get("tick",0)>tick and has_marker(latest(0))),"Panning continues receiving current resident endpoints")
	await connect_client(1)
	if not host.cpu:
		check(await until(func():return ready_while_loading>0),"A ready GPU observer keeps receiving snapshots while another observer's admission queue warms")
		check(host.world.resident!=null and host.world.resident.fallback_reason=="","Every visible/prefetched exterior packet retains resident GPU authority")
	check(await until(func():return not latest(1).is_empty()),"The second camera finishes loading its own view")
	check(host.accounts.size()==2,"Camera preparation preserves both fixture account identities")
	for socket in sockets:socket.close()
	host.running=false;host.listener.stop();host._finish_snapshots()
	if host.world.resident!=null:
		var gpu=host.world.resident.gpu
		gpu.close();await gpu.closed
	var directory: String=host.store.directory
	root.remove_child(host);host.free()
	for filename in DirAccess.get_files_at(directory):DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("CAMERA STREAMING NETWORK: %d assertions, %d failures; ready_frames_during_other_warmup=%d" % [assertions,failures,ready_while_loading])
	quit(0 if failures==0 else 1)
