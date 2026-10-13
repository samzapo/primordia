extends Node
## Persistent authority. Camera union selects detail; sessions never pause the world.
const Sim = preload("res://scripts/simulation.gd")
const Codec = preload("res://scripts/network/state_codec.gd")
const Store = preload("res://scripts/network/world_store.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
const GPU = preload("res://scripts/resident_ecology.gd")
const MAX_PLAYERS := 8
var world
var accounts: Dictionary = {}
var peers: Dictionary = {}
var queued: Array = []
var listener := TCPServer.new()
var store = Store.new()
var world_id := ""
var epoch := 0
var invite := ""
var cpu := false
var running := false
var port := 9001
var bind_address := "127.0.0.1"
var publication_clock := 0.0
var checkpoint_clock := 0.0
var metrics_clock := 0.0
var pending_frame: Dictionary = {}
var started_usec := 0
var tick_samples: Array = []
var skipped_frames := 0
var sent_bytes := 0
var restored_gpu_tick := 0
var shutdown_after := 0.0
var controller
var startup_error := ""
var save_interval := 30.0
var last_checkpoint_usec := 0
var start_simulation_seconds := 0.0

func _ready() -> void:
	get_tree().auto_accept_quit = false
	Engine.max_physics_steps_per_frame = 2
	if store.directory=="": store.directory = ProjectSettings.globalize_path("user://world")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--state-dir="): store.directory = arg.trim_prefix("--state-dir=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--bind="): bind_address = arg.trim_prefix("--bind=")
		elif arg == "--cpu": cpu = true
		elif arg.begins_with("--shutdown-after="): shutdown_after = float(arg.trim_prefix("--shutdown-after="))
	invite = OS.get_environment("PRIMORDIA_INVITE")
	if invite.length()<16: _fatal("PRIMORDIA_INVITE must contain at least 16 characters"); return
	var saved: Dictionary = store.load_latest()
	if not store.last_error.is_empty(): _fatal(store.last_error); return
	if saved.is_empty():
		if world==null: world = Sim.new()
		world_id = Crypto.new().generate_random_bytes(16).hex_encode()
	else:
		var graph = Codec.new().restore(saved.get("graph",{}))
		if not graph is Dictionary or not graph.get("world") is Sim: _fatal("Invalid checkpoint graph"); return
		world = graph.world; accounts = graph.accounts
		world_id = saved.world_id; epoch = int(saved.epoch)
		restored_gpu_tick = saved.get("gpu_tick",0)
	epoch += 1
	world.server_mode = true; world.camera_views.clear()
	world.evolution.sandbox = true
	world.grid.rebuild(world.particles)
	world.pheromones = world.particles.filter(func(p): return p.alive and p.kind==3)
	if world.kernels != null: world.kernels.set_activity_views([],true)
	if cpu:
		world.enable_particle_pool(); _started()
	else:
		# Main-device compute needs a continuously submitted render frame even
		# when the authority has no cameras or visible world geometry.
		var beacon:=ColorRect.new();beacon.size=Vector2(2,2)
		var material:=ShaderMaterial.new();var shader:=Shader.new()
		shader.code="shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR=vec4(vec3(0.01+0.005*sin(TIME)),1.0); }"
		material.shader=shader;beacon.material=material;add_child(beacon)
		controller = GPU.new(); controller.coarse_period = world.offscreen_ecology.period
		controller.initialized.connect(_gpu_started,CONNECT_ONE_SHOT)
		controller.returned_to_cpu.connect(func(reason): startup_error = reason)
		controller.start(world,100000)

func _gpu_started(ok: bool,reason: String) -> void:
	if not ok: _fatal(reason); return
	controller.gpu.reaction_tick = restored_gpu_tick
	if controller.gpu._chemistry != null: controller.gpu._chemistry.last_tick = world.revision
	controller.gpu.publication_ready.connect(_publication_done)
	_started()

func _started() -> void:
	if listener.listen(port,bind_address) != OK: _fatal("Cannot bind world socket"); return
	running = true
	if not checkpoint(): _fatal(store.last_error); return
	started_usec=Time.get_ticks_usec();start_simulation_seconds=world.time
	print("WORLD_READY id=%s epoch=%d tick=%d backend=%s port=%d" % [world_id,epoch,world.revision,"cpu" if world.resident==null else "gpu",port])
	_write_metrics()

func _process(dt: float) -> void:
	if not running: return
	if FileAccess.file_exists(store.directory.path_join("stop.request")):
		DirAccess.remove_absolute(store.directory.path_join("stop.request"));stop();return
	_poll()
	publication_clock += dt; metrics_clock += dt
	if publication_clock >= .1:
		publication_clock = 0; _publish()
	if metrics_clock >= 5:
		metrics_clock = 0; _write_metrics()
	if shutdown_after>0 and (Time.get_ticks_usec()-started_usec)/1000000.0>=shutdown_after:
		stop()

func _physics_process(dt: float) -> void:
	if not running: return
	var start := Time.get_ticks_usec()
	for request in queued: _apply(request.peer,request.message)
	queued.clear()
	_set_views()
	world.step(dt)
	_recover_families(dt)
	world.events = world.events.slice(maxi(0,world.events.size()-128))
	tick_samples.append((Time.get_ticks_usec()-start)/1000.0)
	if tick_samples.size()>600: tick_samples.pop_front()
	if (Time.get_ticks_usec()-last_checkpoint_usec)/1000000.0>=save_interval: checkpoint()

func _set_views() -> void:
	world.camera_views.clear()
	var now := Time.get_ticks_msec()
	for peer in peers.values():
		if peer.account=="" or peer.view==null or now-peer.seen>10000: continue
		var v: Vector4=peer.view
		world.camera_views.append(Vector4(v.x,v.y,peer.detail.x,peer.detail.y))
	if world.kernels!=null: world.kernels.set_activity_views(world.camera_views,true)
	if world.resident!=null: world.resident.gpu.set_activity_views(world.camera_views,true)

func _poll() -> void:
	while listener.is_connection_available():
		var stream := listener.take_connection()
		if peers.size()>=MAX_PLAYERS+4: stream.disconnect_from_host(); continue
		var socket := WebSocketPeer.new()
		socket.inbound_buffer_size=65536;socket.outbound_buffer_size=Protocol.MAX_FRAME
		socket.max_queued_packets=16;socket.heartbeat_interval=5
		if socket.accept_stream(stream)!=OK: continue
		peers[socket.get_instance_id()]={"socket":socket,"account":"","view":null,"seen":Time.get_ticks_msec(),"budget":32.0,"budget_at":Time.get_ticks_msec(),"joined":Time.get_ticks_msec(),"detail":Sim.VIEW*.5/.8,"view_tick":-1}
	for id in peers.keys():
		var peer: Dictionary=peers[id];var socket: WebSocketPeer=peer.socket
		socket.poll()
		if socket.get_ready_state()==WebSocketPeer.STATE_CLOSED:
			peers.erase(id);continue
		var now:=Time.get_ticks_msec()
		peer.budget=minf(32,peer.budget+(now-peer.budget_at)*.016);peer.budget_at=now
		if peer.account=="" and now-peer.joined>10000: socket.close(1008,"Authentication timeout")
		var count:=0
		while socket.get_available_packet_count()>0 and count<16:
			var bytes:=socket.get_packet();count+=1
			if bytes.size()>32768 or not socket.was_string_packet() or peer.budget<1: socket.close(1008,"Request limit");break
			peer.budget-=1
			var message=JSON.parse_string(bytes.get_string_from_utf8())
			if not message is Dictionary: socket.close(1008,"Invalid request");break
			peer.seen=now
			if message.get("op","")=="hello": _hello(id,message)
			elif peer.account=="" : socket.close(1008,"Authenticate first")
			elif message.get("op","")=="view": _view(peer,message)
			elif message.get("op","")=="command" and queued.size()<128:
				var valid:=message.get("action") is String and message.get("args",{}) is Dictionary and _safe_args(message.get("args",{}))
				for field in ["sequence","epoch","cell","edit"]:
					var value=message.get(field)
					valid=valid and (value is float or value is int)
					if value is float: valid=valid and is_finite(value) and value==floor(value) and absf(value)<9007199254740992.0
				if valid: queued.append({"peer":id,"message":message})
				else: socket.close(1008,"Invalid command")

func _hello(id: int,message: Dictionary) -> void:
	var peer: Dictionary=peers[id]
	if peer.account!="": return
	var connected_accounts: Dictionary={}
	for other in peers.values():
		if other.account!="": connected_accounts[other.account]=true
	var token: String=str(message.get("token",""))
	var key:=token.sha256_text() if token.length()==64 else ""
	if not connected_accounts.has(key) and connected_accounts.size()>=MAX_PLAYERS: peer.socket.close(1008,"Pond connection limit");return
	if not accounts.has(key):
		if str(message.get("invite",""))!=invite: peer.socket.close(1008,"Invalid invitation");return
		var owned: Dictionary={}
		for account in accounts.values(): owned[account.root]=true
		var founder
		for cell in world.cells:
			if not cell.dead and not owned.has(cell.lineage_id()): founder=cell;break
		if founder==null: peer.socket.close(1008,"No unclaimed living cell");return
		token=Crypto.new().generate_random_bytes(32).hex_encode();key=token.sha256_text()
		var ledger=world.lineage if founder.lineage_id()==0 else Sim.Lineage.new()
		ledger.root_id=founder.lineage_id()
		if ledger.record_for(founder.id).is_empty(): ledger.register(founder,-1,founder.generation,"active",world.time)
		var evolution=Sim.Evolution.new(world.seed_value^founder.id)
		evolution.sandbox=true
		accounts[key]={"root":founder.lineage_id(),"selected":founder.id,"lineage":ledger,"evolution":evolution,"edit":0,"sequence":0,"receipts":{},"current":founder}
		world.family_ledgers.append(ledger)
		founder.role="player"
		if not checkpoint(): peer.socket.close(1011,"Cannot retain account");return
	for other_id in peers:
		if other_id!=id and peers[other_id].account==key: peers[other_id].socket.close(1000,"Session resumed elsewhere");peers[other_id].view=null
	peer.account=key
	var account: Dictionary=accounts[key]
	var cell=_selected(account)
	peer.view=Vector4(cell.position.x,cell.position.y,Sim.VIEW.x/.8/2,Sim.VIEW.y/.8/2)
	peer.view_tick=world.revision
	_send(peer,{"kind":"welcome","token":token,"world_id":world_id,"epoch":epoch,"sequence":account.sequence,"edit":account.edit,"seed":world.seed_value,"habitat":Codec.new().capture(world.habitat_geometry),"cell":cell.id})
	var initial:=_frame(peer)
	initial.warming=true
	_send(peer,initial)

func _view(peer: Dictionary,message: Dictionary) -> void:
	var v=message.get("rect")
	if not v is Array or v.size()!=4: return
	for item in v:
		if not item is float and not item is int or not is_finite(float(item)): return
	if v[2]<=0 or v[3]<=0 or v[2]>2048 or v[3]>1280: return
	var at:=Sim.Medium.wrap_position(Vector2(v[0],v[1]))
	peer.view=Vector4(at.x,at.y,v[2],v[3])
	peer.view_tick=world.revision
	var detail=message.get("detail",[Sim.VIEW.x/.8/2,Sim.VIEW.y/.8/2])
	if detail is Array and detail.size()==2 and (detail[0] is float or detail[0] is int) and (detail[1] is float or detail[1] is int):
		if is_finite(float(detail[0])) and is_finite(float(detail[1])):
			peer.detail=Vector2(maxf(v[2],clampf(detail[0],Sim.VIEW.x/.8/2,2048)),maxf(v[3],clampf(detail[1],Sim.VIEW.y/.8/2,1280)))

func _selected(account: Dictionary):
	for cell in world.cells:
		if cell.id==account.selected: account.current=cell;return cell
	for cell in account.lineage.dormant:
		if cell.id==account.selected: account.current=cell;return cell
	if account.has("current") and account.current.id==account.selected: return account.current
	var ghost=Sim.Cell.new(account.selected)
	ghost.lineage=account.root;ghost.dead=true;ghost.health=0
	return ghost

func _apply(id: int,message: Dictionary) -> void:
	if not peers.has(id) or peers[id].account=="": return
	var peer: Dictionary=peers[id];var account: Dictionary=accounts[peer.account]
	var seq:=int(message.get("sequence",-1))
	if seq<=account.sequence:
		if account.receipts.has(seq): _send(peer,account.receipts[seq])
		else: _send(peer,{"kind":"result","sequence":seq,"ok":false,"message":"Expired command"})
		return
	var result={"kind":"result","sequence":seq,"server_sequence":account.sequence,"edit":account.edit,"ok":false,"message":"Stale cell or edit; refresh and retry"}
	if seq!=account.sequence+1:
		_send(peer,result);return
	if int(message.get("epoch",-1))!=epoch or int(message.get("cell",-1))!=account.selected or int(message.get("edit",-1))!=account.edit:
		account.sequence=seq;result.server_sequence=seq;_retain_receipt(account,seq,result)
		_send(peer,result);return
	var cell=_selected(account)
	if cell.dead or cell.lineage_id()!=account.root:
		account.sequence=seq;result.server_sequence=seq;_retain_receipt(account,seq,result);_send(peer,result);return
	if not message.get("args",{}) is Dictionary: _send(peer,result);return
	var prior_player=world.player;var prior_lineage=world.lineage;var prior_evolution=world.evolution
	world.player=cell;world.lineage=account.lineage;world.evolution=account.evolution
	var outcome=world.edit(str(message.get("action","")),message.get("args",{}))
	account.selected=world.player.id;account.current=world.player
	world.player=prior_player;world.lineage=prior_lineage;world.evolution=prior_evolution
	var ok: bool=outcome=="" if outcome is String else outcome>=0 if outcome is int else outcome==true
	result.ok=ok;result.message="Applied" if ok else str(outcome) if outcome is String else "Cannot apply: check tissue, AP, placement and template"
	account.sequence=seq
	if ok: account.edit+=1
	result.edit=account.edit;result.server_sequence=seq
	_retain_receipt(account,seq,result)
	# A successful edit and its deduplication receipt become durable together.
	if ok and not checkpoint(): _fatal(store.last_error); return
	_send(peer,result)

func _retain_receipt(account: Dictionary,seq: int,result: Dictionary) -> void:
	account.receipts[seq]=result
	while account.receipts.size()>64: account.receipts.erase(account.receipts.keys()[0])

func _recover_families(dt: float) -> void:
	var prior_player=world.player;var prior_lineage=world.lineage;var prior_evolution=world.evolution
	for account in accounts.values():
		var selected=_selected(account)
		account.evolution.clock=world.time
		if not selected.dead: continue
		world.player=selected;world.lineage=account.lineage;world.evolution=account.evolution
		if account.lineage.recover(world,dt): account.selected=world.player.id;account.edit+=1
	world.player=prior_player;world.lineage=prior_lineage;world.evolution=prior_evolution

func checkpoint() -> bool:
	if world==null: return false
	var gpu_tick:=0
	if world.resident!=null:
		var completion: Dictionary=world.resident.gpu.exchange_sync([],[],[],[],{"feeding":false,"projection":false,"chemistry":false})
		if completion.has("error"): store.last_error=completion.error;return false
		if completion.has("chemistry"): world.resident._account_chemistry(completion.chemistry)
		gpu_tick=world.resident.gpu.reaction_tick
	var overrides: Dictionary={world.get_instance_id():{"particles":world.particle_snapshots(),"pheromones":[],"particle_pool":false}}
	var graph:=Codec.new().capture({"world":world,"accounts":accounts},overrides)
	var result: bool=store.save({"world_id":world_id,"epoch":epoch,"tick":world.revision,"gpu_tick":gpu_tick,"build":OS.get_environment("PRIMORDIA_BUILD_SHA"),"graph":graph})
	if result: last_checkpoint_usec=Time.get_ticks_usec()
	return result

func _publish() -> void:
	if world.camera_views.is_empty() or not pending_frame.is_empty(): return
	if world.resident!=null:
		if world.resident.streaming.queue_depth>0 or world.resident.streaming.eviction_deferred>0: return
		pending_frame={"frames":{}}
		var regions: Array=[]
		for id in peers:
			var peer: Dictionary=peers[id]
			if peer.account=="" or peer.view==null or peer.view_tick>=world.revision: continue
			pending_frame.frames[id]={"view":peer.view,"frame":_frame(peer)}
			regions.append(peer.view)
		if regions.is_empty() or not world.resident.gpu.publish_views(regions): pending_frame.clear()
	else:
		for peer in peers.values():
			if peer.account=="": continue
			var bytes:=PackedByteArray()
			var view: Vector4=peer.view
			for index in world.grid.query_rect(Vector2(view.x,view.y),Vector2(view.z,view.w)+Vector2.ONE*32):
				var packet: Dictionary=world.particle_snapshot(index)
				if not packet.get("alive",false): continue
				var record:=PackedByteArray();record.resize(32)
				for i in 6: record.encode_float(i*4,[packet.p.x,packet.p.y,packet.angle,packet.kind,packet.amount,2*world.particle_radius(packet.kind)*world.particle_scale(packet.amount)][i])
				record.encode_u32(24,index);record.encode_u32(28,0)
				bytes.append_array(record)
			_send_snapshot(peer,bytes)

func _publication_done(data: Dictionary) -> void:
	if not data.has("error") and not data.get("overflow",false):
		for id in pending_frame.get("frames",{}):
			if peers.has(id) and _view_covered(pending_frame.frames[id].view,peers[id].view):
				_send_snapshot(peers[id],data.bytes,pending_frame.frames[id].frame)
	else: skipped_frames+=1
	pending_frame.clear()

func _frame(peer: Dictionary) -> Dictionary:
	var account: Dictionary=accounts[peer.account]
	var cells: Array=[]
	var view: Vector4=peer.view
	for cell in world.cells:
		if Sim.Medium.visibility(cell.position,Vector2(view.x,view.y),Vector2(view.z,view.w)+Vector2.ONE*cell.extent())>0: cells.append(cell)
	return {"kind":"snapshot","world_id":world_id,"epoch":epoch,"tick":world.revision,"time":world.time,"edit":account.edit,"sequence":account.sequence,
		"graph":Codec.new().capture({"cells":cells,"player":_selected(account),"lineage":account.lineage,"evolution":account.evolution}),
		"particles":PackedByteArray(),"flow":world.fluid.velocity.duplicate(),"acid":world.acidity.values.duplicate(),
		"sounds":world.sound_events.duplicate(true),"sound_sequence":world.sound_sequence,"sparks":world.reaction_sparks.duplicate(true),"warming":false}

func _send_snapshot(peer: Dictionary,records: PackedByteArray,frame: Dictionary={}) -> void:
	if peer.view==null or peer.socket.get_ready_state()!=WebSocketPeer.STATE_OPEN: return
	if frame.is_empty(): frame=_frame(peer)
	var bytes:=PackedByteArray()
	var view: Vector4=peer.view
	for offset in range(0,records.size(),32):
		var d:=Sim.Medium.offset(Vector2(view.x,view.y),Vector2(records.decode_float(offset),records.decode_float(offset+4))).abs()
		if d.x<=view.z+32 and d.y<=view.w+32: bytes.append_array(records.slice(offset,offset+32))
	frame.particles=bytes
	_send(peer,frame)

func _send(peer: Dictionary,value: Dictionary) -> void:
	if peer.socket.get_current_outbound_buffered_amount()>1048576: skipped_frames+=1;return
	value.protocol=Protocol.VERSION
	var bytes:=Protocol.pack(value)
	if bytes.size()>Protocol.MAX_FRAME: skipped_frames+=1;return
	if peer.socket.put_packet(bytes)==OK: sent_bytes+=bytes.size()

func _write_metrics() -> void:
	var samples:=tick_samples.duplicate();samples.sort()
	var wall: float=(Time.get_ticks_usec()-started_usec)/1000000.0
	var metrics={"world_id":world_id,"epoch":epoch,"tick":world.revision,"simulation_seconds":world.time,"uptime_seconds":wall,"simulation_wall_ratio":(world.time-start_simulation_seconds)/maxf(wall,.000001),"checkpoint_age_seconds":(Time.get_ticks_usec()-last_checkpoint_usec)/1000000.0,"updated_unix":Time.get_unix_time_from_system(),
		"backend":"gpu" if world.resident!=null else "cpu","gpu":RenderingServer.get_video_adapter_name(),"build":OS.get_environment("PRIMORDIA_BUILD_SHA"),
		"views":world.camera_views.size(),"peers":peers.size(),"packets":world.particle_count(),"cold_packets":world.resident.stored_count() if world.resident!=null else 0,
		"sent_bytes":sent_bytes,"skipped_frames":skipped_frames,"publication_readback_bytes":world.resident.gpu._publication.bytes_read if world.resident!=null and world.resident.gpu._publication!=null else 0,"checkpoint_tick":store.last_saved_tick,"checkpoint_ms":store.latency_ms,"checkpoint_error":store.last_error,"backend_error":startup_error}
	if not samples.is_empty():
		for pair in [["p50",.5],["p95",.95],["p99",.99]]: metrics["tick_ms_"+pair[0]]=samples[mini(samples.size()-1,int(samples.size()*pair[1]))]
	var file:=FileAccess.open(store.directory.path_join("health.json.tmp"),FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(metrics));file.close()
		DirAccess.rename_absolute(store.directory.path_join("health.json.tmp"),store.directory.path_join("health.json"))

func stop() -> void:
	if not running: return
	running=false;checkpoint();listener.stop()
	for peer in peers.values(): peer.socket.close(1001,"World service restarting")
	if world.resident!=null:
		var gpu=world.resident.gpu
		gpu.closed.connect(func():get_tree().quit(),CONNECT_ONE_SHOT);gpu.close()
	else: get_tree().quit()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST: stop()

func _fatal(reason: String) -> void:
	startup_error=reason;push_error(reason);get_tree().quit(1)

func _safe_args(value,depth: int=0) -> bool:
	if depth>6: return false
	if value is float: return is_finite(value)
	if value is String: return value.length()<=128
	if value is Array:
		if value.size()>64: return false
		for item in value:
			if not _safe_args(item,depth+1): return false
		return true
	if value is Dictionary:
		if value.size()>32: return false
		for key in value:
			if not key is String or key.length()>40 or not _safe_args(value[key],depth+1): return false
		return true
	return value==null or value is int or value is bool

func _view_covered(old: Vector4,current: Vector4) -> bool:
	var d:=Sim.Medium.offset(Vector2(old.x,old.y),Vector2(current.x,current.y)).abs()
	return d.x+current.z<=old.z+32 and d.y+current.w<=old.w+32
