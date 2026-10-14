extends Node
## Persistent authority. Camera union selects detail; sessions never pause the world.
const Sim = preload("res://scripts/simulation.gd")
const Codec = preload("res://scripts/network/state_codec.gd")
const Store = preload("res://scripts/network/world_store.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
const GPU = preload("res://scripts/resident_ecology.gd")
const Population = preload("res://scripts/network/pond_population.gd")
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
var access_hashes: Dictionary = {}
var cpu := false
var running := false
var port := 9001
var bind_address := "127.0.0.1"
var last_publication_usec := 0
var checkpoint_clock := 0.0
var last_metrics_usec := 0
var pending_frame: Dictionary = {}
var started_usec := 0
var tick_samples: Array = []
var tick_phase_peak_usec: Dictionary = {}
var snapshots_sent := 0
var particle_resolution: Dictionary = {}
var skipped_frames := 0
var sent_bytes := 0
var restored_gpu_tick := 0
var restored_stream_rng := PackedInt64Array()
var shutdown_after := 0.0
var controller
var startup_error := ""
var save_interval := 30.0
var last_checkpoint_usec := 0
var start_simulation_seconds := 0.0
var checkpoint_total_ms := 0.0
var pond_restarts := 0
var previous_world_id := ""
var pond_archive := ""
var introduced_cells := 0
var lineage_restarts := 0
var population_retry_at := 0.0

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
	var key_path:=OS.get_environment("PRIMORDIA_ACCESS_KEYS_FILE")
	if key_path!="":
		var key_file:=FileAccess.open(key_path,FileAccess.READ)
		if key_file==null or key_file.get_length()>131072: _fatal("Access key registry is unavailable"); return
		var registry=JSON.parse_string(key_file.get_as_text())
		if not registry is Dictionary or not registry.get("hashes") is Array: _fatal("Invalid access key registry"); return
		var pattern:=RegEx.new();pattern.compile("^[a-f0-9]{64}$")
		for value in registry.hashes:
			if not value is String or pattern.search(value)==null: _fatal("Invalid access key hash"); return
			access_hashes[value]=true
		if access_hashes.is_empty() or access_hashes.size()>1024: _fatal("Unsupported access key count"); return
	elif invite.length()<16: _fatal("PRIMORDIA_INVITE must contain at least 16 characters"); return
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
		restored_stream_rng = saved.get("stream_rng",PackedInt64Array())
		pond_restarts=int(saved.get("pond_restarts",0));previous_world_id=saved.get("previous_world_id","");pond_archive=saved.get("pond_archive","")
		introduced_cells=int(saved.get("introduced_cells",0));lineage_restarts=int(saved.get("lineage_restarts",0))
		particle_resolution=saved.get("particle_resolution",{})
		var resolution=preload("res://scripts/network/particle_resolution.gd")
		if saved.get("particle_resolution_version",0)<resolution.VERSION:
			if not store.retain_latest(resolution.VERSION): _fatal(store.last_error);return
			world.disable_particle_pool()
			particle_resolution=resolution.apply(world,int(saved.get("particle_resolution_version",0)))
		if Population.living(world).is_empty():
			pond_archive=store.archive_pond(saved)
			if pond_archive=="":_fatal(store.last_error);return
			var replacement:=Population.fresh(accounts)
			if replacement.has("error"):_fatal(replacement.error);return
			previous_world_id=world_id;world_id=Crypto.new().generate_random_bytes(16).hex_encode()
			world=replacement.world;pond_restarts+=1;introduced_cells=0;lineage_restarts=0
			restored_gpu_tick=0;restored_stream_rng=PackedInt64Array();particle_resolution={}
			print("POND_RESTART previous=%s current=%s archive=%s" % [previous_world_id,world_id,pond_archive])
	epoch += 1
	world.pending_replacements.clear()
	introduced_cells+=Population.replenish(world)
	world.server_mode = true; world.camera_views.clear();world.enable_perception_domains();world.external_offscreen=false;world.interoceptive_cells.clear()
	world.evolution.sandbox = true
	world.grid.rebuild(world.particles)
	world.pheromones = world.particles.filter(func(p): return p.alive and p.kind==3)
	if world.kernels != null: world.kernels.set_activity_views([],true)
	if cpu:
		world.enable_particle_pool(); _started()
	else:
		# Authority time must not be paced by an occluded/idle desktop display.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps=120
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
	if controller.streaming!=null and restored_stream_rng.size()==2:
		controller.streaming.random.seed=restored_stream_rng[0];controller.streaming.random.state=restored_stream_rng[1]
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

func _process(_dt: float) -> void:
	if not running: return
	if FileAccess.file_exists(store.directory.path_join("stop.request")):
		DirAccess.remove_absolute(store.directory.path_join("stop.request"));stop();return
	_poll()
	var now:=Time.get_ticks_usec()
	if now-last_publication_usec>=100000:
		last_publication_usec=now;_publish()
	if now-last_metrics_usec>=5000000:
		_write_metrics()
	if shutdown_after>0 and (Time.get_ticks_usec()-started_usec)/1000000.0>=shutdown_after:
		stop()

func _physics_process(dt: float) -> void:
	if not running: return
	var start := Time.get_ticks_usec()
	for request in queued: _apply(request.peer,request.message)
	queued.clear()
	_set_views()
	world.step(dt)
	if world.resident!=null:
		if not world.resident.gpu.cytoplasm_error.is_empty():_fatal(world.resident.gpu.cytoplasm_error);return
		for cell in world.cells:
			if cell.chemistry.accelerator!=null and not cell.chemistry.accelerator.error.is_empty():_fatal(cell.chemistry.accelerator.error);return
	if Population.living(world).is_empty():
		print("POND_EXTINCT restarting after durable checkpoint")
		stop(Population.RESTART_EXIT);return
	_recover_families(dt)
	if world.time>=population_retry_at:
		introduced_cells+=Population.replenish(world)
		population_retry_at=world.time+.5 if Population.living(world).size()<Population.MIN_LIVING else world.time
	world.events = world.events.slice(maxi(0,world.events.size()-128))
	for phase in world.profile_usec: tick_phase_peak_usec[phase]=maxi(tick_phase_peak_usec.get(phase,0),int(world.profile_usec[phase]))
	tick_samples.append((Time.get_ticks_usec()-start)/1000.0)
	if tick_samples.size()>600: tick_samples.pop_front()
	if (Time.get_ticks_usec()-last_checkpoint_usec)/1000000.0>=save_interval: checkpoint()

func _set_views() -> void:
	world.camera_views.clear();world.interoceptive_cells.clear()
	var now := Time.get_ticks_msec()
	for peer in peers.values():
		if peer.account=="" or peer.view==null or now-peer.seen>10000: continue
		var v: Vector4=peer.view
		if peer.get("perception","exteroception")=="interoception":
			var focus=_focus(peer)
			if focus!=null and Sim.Medium.visibility(focus.position,Vector2(v.x,v.y),Vector2(v.z,v.w)+Vector2.ONE*focus.extent())>0:world.interoceptive_cells[focus.id]=true
		else:world.camera_views.append(Vector4(v.x,v.y,peer.detail.x,peer.detail.y))
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
			elif message.get("op","")=="ping": pass
			elif message.get("op","")=="snapshot_ack":
				if message.get("serial") is float or message.get("serial") is int:
					if message.serial==peer.get("awaiting_snapshot",0) and message.get("epoch",-1)==epoch:peer.awaiting_snapshot=0
			elif message.get("op","")=="view": _view(peer,message)
			elif message.get("op","")=="command" and queued.size()<128:
				var valid:=message.get("action") is String and message.get("args",{}) is Dictionary and _safe_args(message.get("args",{}))
				for field in ["sequence","epoch","cell","edit"]:
					var value=message.get(field)
					valid=valid and (value is float or value is int)
					if value is float: valid=valid and is_finite(value) and value==floor(value) and absf(value)<9007199254740992.0
				if valid: queued.append({"peer":id,"message":message})
				else: socket.close(1008,"Invalid command")


func _close_sessions(key: String,except_id: int) -> void:
	for other_id in peers:
		if other_id!=except_id and peers[other_id].account==key:
			peers[other_id].socket.close(1000,"Session resumed elsewhere")
			peers[other_id].account="";peers[other_id].view=null

func _hello(id: int,message: Dictionary) -> void:
	var peer: Dictionary=peers[id]
	if peer.account!="": return
	var token: String=str(message.get("token",""))
	var key:=token.sha256_text() if token.length()==64 else ""
	var supplied:=str(message.get("invite","")).strip_edges()
	var grant:=supplied.sha256_text()
	var dirty:=false
	if not access_hashes.is_empty():
		if supplied!="" and not access_hashes.has(grant): peer.socket.close(1008,"Invalid access key");return
		if access_hashes.has(grant):
			var prior:=""
			for candidate in accounts:
				if accounts[candidate].get("access_hash","")==grant: prior=candidate;break
			if prior!="" and prior!=key:
				# A key resumes its existing account on a new browser, never a second lineage.
				_close_sessions(prior,id)
				var existing: Dictionary=accounts[prior];accounts.erase(prior)
				token=Crypto.new().generate_random_bytes(32).hex_encode();key=token.sha256_text()
				accounts[key]=existing;dirty=true
			elif prior=="" and accounts.has(key) and not accounts[key].has("access_hash"):
				accounts[key].access_hash=grant;dirty=true
			elif prior=="" and accounts.has(key): key="";token=""
		elif not accounts.has(key) or not access_hashes.has(accounts[key].get("access_hash","")):
			peer.socket.close(1008,"Access key required");return
	elif not accounts.has(key) and supplied!=invite:
		peer.socket.close(1008,"Invalid invitation");return
	var connected_accounts: Dictionary={}
	for other in peers.values():
		if other.account!="": connected_accounts[other.account]=true
	if not connected_accounts.has(key) and connected_accounts.size()>=MAX_PLAYERS:
		peer.socket.close(1008,"Pond connection limit");return
	if not accounts.has(key):
		var owned: Dictionary={}
		for account in accounts.values(): owned[account.root]=true
		var founder
		for cell in world.cells:
			if not cell.dead and not owned.has(cell.lineage_id()): founder=cell;break
		if founder==null: peer.socket.close(1008,"No unclaimed living cell");return
		token=Crypto.new().generate_random_bytes(32).hex_encode();key=token.sha256_text()
		var ledger=world._family_ledger(founder)
		ledger.root_id=founder.lineage_id()
		if ledger.record_for(founder.id).is_empty(): ledger.register(founder,-1,founder.generation,"active",world.time)
		else:ledger.record_for(founder.id).state="active"
		var evolution=Sim.Evolution.new(world.seed_value^founder.id)
		evolution.sandbox=true
		accounts[key]={"root":founder.lineage_id(),"selected":founder.id,"lineage":ledger,"evolution":evolution,"edit":0,"sequence":0,"receipts":{},"current":founder}
		if not world.family_ledgers.has(ledger):world.family_ledgers.append(ledger)
		founder.role="player"
		if not access_hashes.is_empty(): accounts[key].access_hash=grant
		dirty=true
	if dirty and not checkpoint(): peer.socket.close(1011,"Cannot retain account");_fatal("Cannot retain account");return
	_close_sessions(key,id)
	peer.account=key
	peer.snapshot_ack=message.get("snapshot_ack",false)==true;peer.compact_cytoplasm=message.get("compact_cytoplasm",false)==true
	peer.frame_serial=0;peer.awaiting_snapshot=0
	var account: Dictionary=accounts[key]
	var cell=_selected(account)
	var focus=_focus(peer)
	var center: Vector2=focus.position if focus!=null else cell.position
	peer.view=Vector4(center.x,center.y,Sim.VIEW.x/.8/2,Sim.VIEW.y/.8/2)
	peer.view_tick=world.revision
	_send(peer,{"kind":"welcome","token":token,"world_id":world_id,"epoch":epoch,"sequence":account.sequence,"edit":account.edit,"seed":world.seed_value,"habitat":Codec.new().capture(world.habitat_geometry),"cell":cell.id})
	var initial:=_frame(peer)
	initial.warming=true
	_send(peer,initial)

func _view(peer: Dictionary,message: Dictionary) -> void:
	var mode=message.get("perception","exteroception")
	if mode not in ["exteroception","interoception"]:return
	var old_mode: String=peer.get("perception","exteroception")
	var v=message.get("rect")
	if not v is Array or v.size()!=4: return
	for item in v:
		if not item is float and not item is int or not is_finite(float(item)): return
	if v[2]<=0 or v[3]<=0 or v[2]>2048 or v[3]>1280: return
	var at:=Sim.Medium.wrap_position(Vector2(v[0],v[1]))
	var next_view:=Vector4(at.x,at.y,v[2],v[3])
	var changed: bool=peer.view!=next_view
	var prior_detail: Vector2=peer.detail
	peer.view=next_view;peer.perception=mode
	var detail=message.get("detail",[Sim.VIEW.x/.8/2,Sim.VIEW.y/.8/2])
	if detail is Array and detail.size()==2 and (detail[0] is float or detail[0] is int) and (detail[1] is float or detail[1] is int):
		if is_finite(float(detail[0])) and is_finite(float(detail[1])):
			peer.detail=Vector2(maxf(v[2],clampf(detail[0],Sim.VIEW.x/.8/2,2048)),maxf(v[3],clampf(detail[1],Sim.VIEW.y/.8/2,1280)))
	# A repeated camera heartbeat must not restart the warm-up gate.
	if changed or peer.detail!=prior_detail or old_mode!=mode: peer.view_tick=world.revision

func _selected(account: Dictionary):
	for cell in world.cells:
		if cell.id==account.selected: account.current=cell;return cell
	for cell in account.lineage.dormant:
		if cell.id==account.selected: account.current=cell;return cell
	if account.has("current") and account.current.id==account.selected: return account.current
	var ghost=Sim.Cell.new(account.selected)
	ghost.lineage=account.root;ghost.dead=true;ghost.health=0
	return ghost

func _focus(peer: Dictionary):
	var selected=_selected(accounts[peer.account])
	if not selected.dead:return selected
	for cell in world.cells:
		if cell.id==peer.get("focus_id",-1) and not cell.dead:return cell
	var nearest=null;var distance:=INF
	for cell in world.cells:
		if cell.dead:continue
		var d: float=Sim.Medium.offset(selected.position,cell.position).length_squared()
		if d<distance:nearest=cell;distance=d
	if nearest!=null:peer.focus_id=nearest.id
	return nearest

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
		if account.lineage.recover(world,dt): account.selected=world.player.id;account.current=world.player;account.edit+=1
		elif account.lineage.dormant.is_empty() and account.lineage.active_family(world).is_empty() and world.time>=float(account.get("restart_at",0)):
			var founder=Population.introduce(world,true)
			account.restart_at=world.time+.5
			if founder!=null:
				Population.enroll(world,account,founder);introduced_cells+=1;lineage_restarts+=1
	world.player=prior_player;world.lineage=prior_lineage;world.evolution=prior_evolution
	# The shared managed reference must not retain an exhausted body forever.
	if world.player.dead:
		for account in accounts.values():
			if not account.current.dead:
				world.player=account.current;world.lineage=account.lineage;world.evolution=account.evolution;break
	if prior_player.dead and world.player!=prior_player:world.cells.erase(prior_player)
	if world.player.dead:
		var candidates:=Population.living(world)
		if not candidates.is_empty():
			world.cells.erase(world.player);world.player=candidates[0]
			world.lineage=world._family_ledger(world.player)
	# Histories retained by accounts remain serialized through previous_lineages.
	world.family_ledgers=world.family_ledgers.filter(func(ledger):return not ledger.dormant.is_empty() or not ledger.active_family(world).is_empty())

func checkpoint() -> bool:
	if world==null: return false
	var checkpoint_start:=Time.get_ticks_usec()
	var gpu_tick:=0
	var stream_rng:=PackedInt64Array()
	if world.resident!=null:
		if world.resident.streaming!=null: stream_rng=PackedInt64Array([world.resident.streaming.random.seed,world.resident.streaming.random.state])
		var completion: Dictionary=world.resident.gpu.exchange_sync([],[],[],[],{"feeding":false,"projection":false,"chemistry":false})
		if completion.has("error"): store.last_error=completion.error;return false
		if completion.has("chemistry"): world.resident._account_chemistry(completion.chemistry)
		gpu_tick=world.resident.gpu.reaction_tick
	var overrides: Dictionary={world.get_instance_id():{"particles":world.particle_snapshots(),"pheromones":[],"particle_pool":false}}
	var graph:=Codec.new().capture({"world":world,"accounts":accounts},overrides)
	var result: bool=store.save({"world_id":world_id,"epoch":epoch,"tick":world.revision,"gpu_tick":gpu_tick,"stream_rng":stream_rng,"particle_resolution_version":preload("res://scripts/network/particle_resolution.gd").VERSION,"particle_resolution":particle_resolution,"build":OS.get_environment("PRIMORDIA_BUILD_SHA"),"pond_restarts":pond_restarts,"previous_world_id":previous_world_id,"pond_archive":pond_archive,"introduced_cells":introduced_cells,"lineage_restarts":lineage_restarts,"graph":graph})
	checkpoint_total_ms=(Time.get_ticks_usec()-checkpoint_start)/1000.0
	if result: last_checkpoint_usec=Time.get_ticks_usec()
	return result

func _publish() -> void:
	# Inside views need current intracellular graphs, not an external pose gather.
	for peer in peers.values():
		if peer.account!="" and peer.view!=null and peer.get("perception","exteroception")=="interoception" and peer.view_tick<world.revision and peer.get("awaiting_snapshot",0)==0:
			_send_snapshot(peer,PackedByteArray())
	if world.camera_views.is_empty() or not pending_frame.is_empty(): return
	if world.resident!=null:
		if world.resident.streaming.queue_depth>0 or world.resident.streaming.eviction_deferred>0: return
		pending_frame={"frames":{}}
		var regions: Array=[]
		for id in peers:
			var peer: Dictionary=peers[id]
			if peer.account=="" or peer.view==null or peer.view_tick>=world.revision or peer.get("perception","exteroception")!="exteroception" or peer.get("awaiting_snapshot",0)>0: continue
			pending_frame.frames[id]={"view":peer.view,"frame":_frame(peer)}
			regions.append(peer.view)
		if regions.is_empty() or not world.resident.gpu.publish_views(regions): pending_frame.clear()
	else:
		for peer in peers.values():
			if peer.account=="" or peer.get("perception","exteroception")!="exteroception" or peer.get("awaiting_snapshot",0)>0: continue
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
			if peers.has(id) and peers[id].get("perception","exteroception")=="exteroception" and _view_covered(pending_frame.frames[id].view,peers[id].view):
				_send_snapshot(peers[id],data.bytes,pending_frame.frames[id].frame)
	else: skipped_frames+=1
	pending_frame.clear()

func _frame(peer: Dictionary) -> Dictionary:
	var account: Dictionary=accounts[peer.account]
	var cells: Array=[]
	var view: Vector4=peer.view
	for cell in world.cells:
		if Sim.Medium.visibility(cell.position,Vector2(view.x,view.y),Vector2(view.z,view.w)+Vector2.ONE*cell.extent())>0: cells.append(cell)
	var internal_overrides: Dictionary={}
	var focus=_focus(peer)
	for cell in world.cells:
		if peer.get("perception","exteroception")!="interoception" or cell!=focus:internal_overrides[cell.chemistry.get_instance_id()]={"particles":[],"presentation_totals":{"material":cell.chemistry.material(),"storage":cell.chemistry.storage_used(),"potential":cell.chemistry.potential(),"raw_fuel":cell.chemistry.raw_fuel(),"packets":cell.chemistry.particle_count()}}
	return {"kind":"snapshot","world_id":world_id,"epoch":epoch,"tick":world.revision,"time":world.time,"edit":account.edit,"sequence":account.sequence,
		"family_recovery":_family_recovery(account),"graph":Codec.new().capture({"cells":cells,"player":_selected(account),"focus":_focus(peer),"lineage":account.lineage,"evolution":account.evolution},internal_overrides,peer.get("compact_cytoplasm",false)),
		"particles":PackedByteArray(),"flow":world.fluid.velocity.duplicate(),"acid":world.acidity.values.duplicate(),
		"sounds":world.sound_events.duplicate(true),"sound_sequence":world.sound_sequence,"sparks":world.reaction_sparks.duplicate(true),"perception":peer.get("perception","exteroception"),"warming":false}

func _send_snapshot(peer: Dictionary,records: PackedByteArray,frame: Dictionary={}) -> void:
	if peer.view==null or peer.socket.get_ready_state()!=WebSocketPeer.STATE_OPEN or peer.get("awaiting_snapshot",0)>0: return
	if frame.is_empty(): frame=_frame(peer)
	var bytes:=PackedByteArray()
	var view: Vector4=peer.view
	for offset in range(0,records.size(),32):
		var d:=Sim.Medium.offset(Vector2(view.x,view.y),Vector2(records.decode_float(offset),records.decode_float(offset+4))).abs()
		if d.x<=view.z+32 and d.y<=view.w+32: bytes.append_array(records.slice(offset,offset+32))
	frame.particles=bytes
	var serial: int=peer.get("frame_serial",0)+1
	frame.serial=serial
	if _send(peer,frame):
		peer.frame_serial=serial
		if peer.get("snapshot_ack",false):peer.awaiting_snapshot=serial

func _send(peer: Dictionary,value: Dictionary) -> bool:
	if peer.socket.get_current_outbound_buffered_amount()>1048576: skipped_frames+=1;return false
	value.protocol=Protocol.VERSION
	var bytes:=Protocol.pack(value)
	if bytes.is_empty() or bytes.size()>Protocol.MAX_FRAME:
		skipped_frames+=1
		if value.get("kind","")=="snapshot":_send(peer,{"kind":"snapshot_error","message":"The world view could not be loaded. Your sign-in is saved."})
		return false
	if peer.socket.put_packet(bytes)==OK:
		sent_bytes+=bytes.size()
		if value.get("kind","")=="snapshot" and not value.get("warming",false): snapshots_sent+=1
		return true
	return false

func _write_metrics() -> void:
	last_metrics_usec=Time.get_ticks_usec()
	var samples:=tick_samples.duplicate();samples.sort()
	var wall: float=(Time.get_ticks_usec()-started_usec)/1000000.0
	var claimed: Dictionary={};var joinable: Dictionary={};var living:=0
	for account in accounts.values(): claimed[account.root]=true
	for cell in world.cells:
		if not cell.dead:
			living+=1
			if not claimed.has(cell.lineage_id()): joinable[cell.lineage_id()]=true
	var metrics={"living_cells":living,"joinable_lineages":joinable.size(),"access_keys":access_hashes.size(),"world_id":world_id,"epoch":epoch,"tick":world.revision,"simulation_seconds":world.time,"uptime_seconds":wall,"simulation_wall_ratio":(world.time-start_simulation_seconds)/maxf(wall,.000001),"checkpoint_age_seconds":(Time.get_ticks_usec()-last_checkpoint_usec)/1000000.0,"updated_unix":Time.get_unix_time_from_system(),
		"backend":"gpu" if world.resident!=null else "cpu","gpu":RenderingServer.get_video_adapter_name(),"build":OS.get_environment("PRIMORDIA_BUILD_SHA"),
		"views":world.camera_views.size(),"peers":peers.size(),"packets":world.particle_count(),"cold_packets":world.resident.stored_count() if world.resident!=null else 0,"accounts":accounts.size(),"stored_packets":world.particle_count()+world.resident.stored_count() if world.resident!=null else world.particle_count(),
		"sent_bytes":sent_bytes,"skipped_frames":skipped_frames,"publication_readback_bytes":world.resident.gpu._publication.bytes_read if world.resident!=null and world.resident.gpu._publication!=null else 0,"checkpoint_tick":store.last_saved_tick,"checkpoint_ms":checkpoint_total_ms,"checkpoint_write_ms":store.latency_ms,"checkpoint_error":store.last_error,"backend_error":startup_error}
	metrics["automatic_reproduction"]=world.automatic_reproduction
	metrics["minimum_living_cells"]=Population.MIN_LIVING
	metrics["automatic_lineage_restart"]=true;metrics["automatic_pond_restart"]=true
	metrics["pond_restarts"]=pond_restarts;metrics["previous_world_id"]=previous_world_id;metrics["pond_archive"]=pond_archive
	metrics["introduced_cells"]=introduced_cells;metrics["lineage_restarts"]=lineage_restarts
	metrics["internal_packets"]=world.cells.reduce(func(total,cell):return total+cell.chemistry.particle_count(),0)
	metrics["resident_internal_cells"]=world.cells.filter(func(cell):return cell.chemistry.accelerator!=null).size()
	metrics["internal_parcel_scale"]=world.Catalog.data().ecology.get("internal_parcel_scale",1)
	metrics["particle_resolution"]=particle_resolution
	metrics["particle_parcel_scale"]=world.Catalog.data().ecology.get("parcel_scale",1)
	metrics["visible_particle_target"]=world.Catalog.data().ecology.visible_target
	metrics["snapshots_sent"]=snapshots_sent
	metrics["ready_views"]=peers.values().filter(func(peer):return peer.account!="" and peer.view!=null and peer.view_tick<world.revision).size()
	metrics["interoceptive_cells"]=world.interoceptive_cells.size()
	metrics["interoception_peers"]=peers.values().filter(func(peer):return peer.account!="" and peer.get("perception","exteroception")=="interoception").size()
	metrics["internal_pending_seconds"]=world.cells.filter(func(cell):return not cell.dead).map(func(cell):return cell.chemistry.pending_time).reduce(func(total,value):return total+value,0.0)
	metrics["publication_pending"]=not pending_frame.is_empty()
	metrics["snapshots_awaiting_ack"]=peers.values().filter(func(peer):return peer.get("awaiting_snapshot",0)>0).size()
	metrics["tick_phase_peak_ms"]={}
	for phase in tick_phase_peak_usec: metrics.tick_phase_peak_ms[phase]=tick_phase_peak_usec[phase]/1000.0
	tick_phase_peak_usec.clear()
	if world.resident!=null and world.resident.streaming!=null:
		metrics["stream_queue"]=world.resident.streaming.queue_depth
		metrics["eviction_deferred"]=world.resident.streaming.eviction_deferred
	if not samples.is_empty():
		for pair in [["p50",.5],["p95",.95],["p99",.99]]: metrics["tick_ms_"+pair[0]]=samples[mini(samples.size()-1,int(samples.size()*pair[1]))]
	var file:=FileAccess.open(store.directory.path_join("health.json.tmp"),FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(metrics));file.close()
		DirAccess.rename_absolute(store.directory.path_join("health.json.tmp"),store.directory.path_join("health.json"))

func stop(exit_status: int=0) -> void:
	if not running: return
	running=false
	if not checkpoint():_fatal(store.last_error);return
	listener.stop()
	for peer in peers.values(): peer.socket.close(1001,"World service restarting")
	if world.resident!=null:
		var gpu=world.resident.gpu
		gpu.closed.connect(func():get_tree().quit(exit_status),CONNECT_ONE_SHOT);gpu.close()
	else: get_tree().quit(exit_status)

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

func _family_recovery(account: Dictionary) -> Dictionary:
	var living: int=account.lineage.active_family(world).size()
	var stored: int=account.lineage.dormant.size()
	var selected=_selected(account)
	return {"living":living,"stored":stored,"state":"active" if not selected.dead else "recovering" if living>0 else "waiting_for_space" if stored>0 else "restarting_lineage"}
