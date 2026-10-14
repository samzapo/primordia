extends SceneTree
## Real token-only reconnect across an archived empty-world startup.
const Sim=preload("res://scripts/simulation.gd")
const Host=preload("res://scripts/network/world_host.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Protocol=preload("res://scripts/network/protocol.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var host=Host.new();host.cpu=true;host.port=20000+OS.get_process_id()%20000
	host.store.directory=OS.get_environment("PRIMORDIA_RESTART_TEST_STATE")
	if host.store.directory=="":quit(1);return
	DirAccess.make_dir_recursive_absolute(host.store.directory)
	var key_path: String=host.store.directory.path_join("fixture-keys.json")
	var registry:=FileAccess.open(key_path,FileAccess.WRITE)
	registry.store_string(JSON.stringify({"hashes":["private-key-fixture".sha256_text()]}));registry.close()
	var checksum:=FileAccess.get_sha256(key_path);OS.set_environment("PRIMORDIA_ACCESS_KEYS_FILE",key_path)
	var old=Sim.new(17,0,false);old.player.id=999;old.player.dead=true;old.player.health=0
	old.cells=[];old.habitat_geometry=Sim.Habitat.new(17,[]);old.revision=500;old.time=42
	var token: String="1".repeat(64)
	var account={"root":999,"selected":999,"current":old.player,"lineage":old.lineage,"evolution":old.evolution,"edit":3,"sequence":11,"receipts":{},"access_hash":"private-key-fixture".sha256_text()}
	check(host.store.save({"world_id":"b".repeat(32),"epoch":12,"tick":500,"graph":Codec.new().capture({"world":old,"accounts":{token.sha256_text():account}}),"particle_resolution_version":3}),"Prepare a checksummed empty predecessor with a retained login")
	root.add_child(host)
	check(host.running and host.world_id!="b".repeat(32) and host.epoch==13,"Startup replaces only the empty world and increases its epoch")
	check(FileAccess.get_sha256(key_path)==checksum and host.accounts.has(token.sha256_text()),"Registry bytes and the saved session grant survive reseeding")
	var retained=preload("res://scripts/network/world_store.gd").new();retained.directory=host.store.directory.path_join(host.pond_archive)
	var archived: Dictionary=retained.load_latest()
	check(archived.get("world_id","")=="b".repeat(32) and archived.get("tick",0)==500 and archived.graph.root.accounts.has(token.sha256_text()),"The independent predecessor archive retains its original time and private account mapping")
	var socket:=WebSocketPeer.new();socket.inbound_buffer_size=Protocol.MAX_FRAME
	socket.connect_to_url("ws://127.0.0.1:"+str(host.port))
	var end:=Time.get_ticks_msec()+30000
	while socket.get_ready_state()!=WebSocketPeer.STATE_OPEN and Time.get_ticks_msec()<end:
		socket.poll();await process_frame
	check(socket.get_ready_state()==WebSocketPeer.STATE_OPEN,"Actual reconnect reaches the restarted authority")
	socket.send_text(JSON.stringify({"op":"hello","token":token,"snapshot_ack":true}))
	var welcome: Dictionary={};var snapshot: Dictionary={}
	while (welcome.is_empty() or snapshot.is_empty()) and Time.get_ticks_msec()<end:
		socket.poll()
		while socket.get_available_packet_count()>0:
			var message:=Protocol.unpack(socket.get_packet())
			if message.get("kind","")=="welcome":welcome=message
			if message.get("kind","")=="snapshot":snapshot=message
		await process_frame
	check(welcome.get("token","")==token and welcome.get("sequence",-1)==11 and welcome.get("cell",999)!=999,"Token-only sign-in needs no key re-entry and selects a new-world cell")
	if not snapshot.is_empty():
		var state=Codec.new().restore(snapshot.graph)
		check(not state.player.dead and state.player.lineage_id()==host.accounts[token.sha256_text()].root,"The real client snapshot includes the account's new living lineage")
	else:check(false,"New-world snapshot was not delivered")
	socket.close();host.running=false;host.listener.stop();host.queue_free();await process_frame
	OS.set_environment("PRIMORDIA_ACCESS_KEYS_FILE","")
	print("POND RESTART NETWORK: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
