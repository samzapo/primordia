extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Host=preload("res://scripts/network/world_host.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Protocol=preload("res://scripts/network/protocol.gd")
var failures:=0
var assertions:=0
var socket:=WebSocketPeer.new()
var host
var messages: Array=[]
var last_ping:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func until(predicate: Callable) -> bool:
	var end:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<end:
		socket.poll()
		if socket.get_ready_state()==WebSocketPeer.STATE_OPEN and messages.any(func(m):return m.get("kind","")=="welcome") and Time.get_ticks_msec()-last_ping>200:
			last_ping=Time.get_ticks_msec();socket.send_text(JSON.stringify({"op":"ping"}))
		while socket.get_available_packet_count()>0:
			var message:=Protocol.unpack(socket.get_packet());messages.append(message)
			if message.get("kind","")=="snapshot" and message.get("serial",0)>0:socket.send_text(JSON.stringify({"op":"snapshot_ack","serial":message.serial,"epoch":message.epoch}))
		if predicate.call():return true
		await process_frame
	return false
func result(sequence: int) -> Dictionary:
	for message in messages:
		if message.get("kind","")=="result" and message.get("sequence",-1)==sequence:return message
	return {}
func run() -> void:
	host=Host.new();host.cpu=not ("--gpu" in OS.get_cmdline_user_args());host.port=19000+OS.get_process_id()%20000
	if not host.cpu:root.size=Vector2i(64,64)
	host.store.directory=ProjectSettings.globalize_path("res://build/lineage-start-"+str(OS.get_process_id()))
	host.world=Sim.new(17,0,false)
	host.world.cells=[host.world.player]
	host.world.habitat_geometry=Sim.Habitat.new(17,host.world.cells)
	root.add_child(host)
	check(await until(func():return host.running),"Fixture authority starts")
	if not host.running:quit(1);return
	socket.inbound_buffer_size=Protocol.MAX_FRAME
	socket.connect_to_url("ws://127.0.0.1:"+str(host.port))
	check(await until(func():return socket.get_ready_state()==WebSocketPeer.STATE_OPEN),"Lineage request uses a real socket")
	socket.send_text(JSON.stringify({"op":"hello","invite":OS.get_environment("PRIMORDIA_INVITE"),"snapshot_ack":true}))
	check(await until(func():return messages.any(func(m):return m.get("kind","")=="welcome")),"Fixture account signs in")
	var welcome: Dictionary=messages.filter(func(m):return m.get("kind","")=="welcome")[0]
	var account: Dictionary=host.accounts[welcome.token.sha256_text()]
	var old=account.current;var old_root: int=account.root
	var pond: String=host.world_id;var epoch: int=host.epoch
	var starting_edit: int=account.edit
	var original_organs: Array=old.organs.map(func(o):return o.id)
	var command={"op":"command","epoch":epoch,"cell":old.id,"edit":starting_edit,"sequence":1,"action":"start_lineage","args":{"confirmed":false}}
	socket.send_text(JSON.stringify(command))
	check(await until(func():return not result(1).is_empty()),"Unconfirmed lineage request returns a receipt")
	check(not result(1).ok and account.root==old_root and account.edit==starting_edit,"Confirmation is required without changing ownership")
	command.sequence=2;command.args.confirmed=true
	socket.send_text(JSON.stringify(command))
	check(await until(func():return not result(2).is_empty()),"Confirmed lineage request returns a durable receipt")
	check(result(2).ok and account.root!=old_root and account.selected!=old.id,"Existing account receives a new lineage")
	check(host.world_id==pond and host.epoch==epoch and host.accounts.size()==1,"Lineage handoff preserves the pond, epoch and account")
	check(host.world.cells.has(old) and not old.dead and old.role=="grazer" and old.organs.map(func(o):return o.id)==original_organs,"Former cell survives with its existing anatomy under computer control")
	check(account.previous_lineages[-1].root==old_root and account.edit==starting_edit+1,"Former family history is retained and edit advances once")
	var selected: int=account.selected;var next_id: int=host.world.next_id
	socket.send_text(JSON.stringify(command))
	check(await until(func():return messages.filter(func(m):return m.get("kind","")=="result" and m.get("sequence",-1)==2).size()==2),"A retried handoff receives the retained receipt")
	check(account.selected==selected and host.world.next_id==next_id,"A duplicate request creates no second founder")
	var saved=Codec.new().restore(host.store.load_latest().graph)
	var retained: Dictionary=saved.accounts[welcome.token.sha256_text()]
	check(retained.selected==selected and retained.root==account.root and saved.world.cells.any(func(c):return c.id==old.id and not c.dead),"Checkpoint retains new ownership and the surviving former family")
	command.sequence=3;command.cell=selected;command.edit=account.edit
	socket.send_text(JSON.stringify(command))
	check(await until(func():return not result(3).is_empty()),"Repeated new-lineage attempt returns a receipt")
	check(not result(3).ok and account.selected==selected,"Cooldown prevents rapid lineage/founder spam")
	var directory: String=host.store.directory
	socket.close();host.running=false;host.listener.stop()
	if host.world.resident!=null:
		check(host.world.resident.gpu!=null,"Resident GPU remains active through lineage handoff and its checkpoint")
		host.world.resident.gpu.close();await host.world.resident.gpu.closed
	host.queue_free();await process_frame
	for name in ["world-0.pworld","world-1.pworld","health.json"]:DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("LINEAGE START NETWORK: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
