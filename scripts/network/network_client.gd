extends "res://scripts/pond.gd"
const Codec = preload("res://scripts/network/state_codec.gd")
const Protocol = preload("res://scripts/network/protocol.gd")
# Godot 4.7.2 EMWSPeer removes IPv6 brackets when reconstructing a web URL.
# Correct only the registered malformed address at the browser constructor.
const BROWSER_SOCKET_ADDRESS := """
((address) => {
    let parsed;
    try { parsed = new URL(address); } catch (_) { return; }
    if (!['ws:', 'wss:'].includes(parsed.protocol) || !parsed.hostname.startsWith('[')) return;
    const start = address.indexOf('://') + 3;
    const end = address.indexOf(']', start);
    const host = address.slice(start + 1, end);
    let tail = address.slice(end + 1).split('#', 1)[0];
    const defaultPort = parsed.protocol === 'wss:' ? ':443' : ':80';
    if (tail === defaultPort || tail.startsWith(defaultPort + '/') || tail.startsWith(defaultPort + '?')) {
        tail = tail.slice(defaultPort.length);
    }
    const scheme = address.slice(0, start);
    const broken = scheme + host + tail;
    const corrected = scheme + '[' + host + ']' + tail;
    let fix = window.primordiaSocketAddress;
    if (!fix) {
        fix = { addresses: new Map(), rewrites: 0 };
        window.primordiaSocketAddress = fix;
        window.WebSocket = new Proxy(window.WebSocket, {
            construct(target, args, newTarget) {
                const replacement = fix.addresses.get(String(args[0]));
                if (replacement) {
                    args = [replacement, ...args.slice(1)];
                    fix.rewrites++;
                }
                return Reflect.construct(target, args, newTarget);
            }
        });
    }
    fix.addresses.set(broken, corrected);
})(%s);
"""
var socket := WebSocketPeer.new()
var login := PanelContainer.new()
var url_input := LineEdit.new()
var invite_input := LineEdit.new()
var status := Label.new()
var join_button := Button.new()
var connected := false
var attempted := false
var connecting := false
var retry_enabled := false
var transport_failures := 0
var connection_attempts := 0
var connect_started_usec := 0
var hello_sent := false
var token := ""
var server_url := "ws://127.0.0.1:8766/ws"
var invitation := ""
var epoch := 0
var command_sequence := 0
var edit_revision := 0
var commands: Array = []
var inflight: Dictionary = {}
var received_usec := 0
var interval_usec := 100000.0
var view_clock := 0.0
var keepalive_clock := 0.0
var last_camera: Vector4
var last_detail: Vector2
var last_perception := ""
var view_announced := false
var reconnect_due := 0.0
var packet_ids: Dictionary = {}
var cells_by_id: Dictionary = {}
var network_particles
var network_alpha := 1.0
var paused_snapshot: Dictionary = {}
var camera_initialized := false
var focus_cell
var loading_world := false
var connection_stage := "sign_in"

func _ready() -> void:
	world = Simulation.new(0,0,false)
	world.server_mode=true;world.remote_client=true;world.evolution.sandbox=true
	world.command_sink=_queue_command
	world.player.dead=true;world.cells=[]
	world.habitat_geometry=Simulation.Habitat.new(0,[])
	world.native_render=false;world.native_particle_render_cache=false
	if OS.has_feature("web"):
		server_url = str(JavaScriptBridge.eval("(location.protocol==='https:'?'wss://':'ws://')+location.host+'/ws'"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--connect="): server_url=arg.trim_prefix("--connect=")
		elif arg.begins_with("--invite="): invitation=arg.trim_prefix("--invite=")
	_load_identity()
	super()
	network_particles=preload("res://scripts/network/network_particles.gd").new()
	world_layer.add_child(network_particles)
	notice = "Connect to the shared pond. Your lineage and chemistry continue while disconnected."
	var box := VBoxContainer.new()
	login.add_child(box); ui.add_child(login)
	login.position=Vector2(24,24);login.custom_minimum_size=Vector2(420,0)
	status.text="Sign in to the running pond. Paste your personal access key the first time.";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
	url_input.text=server_url;url_input.placeholder_text="Server address";url_input.editable=not OS.has_feature("web");box.add_child(url_input)
	invite_input.secret=true;invite_input.virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_PASSWORD;invite_input.text=invitation;invite_input.placeholder_text="Personal access key (first sign-in)";box.add_child(invite_input)
	join_button.text="Sign in / reconnect";join_button.pressed.connect(_connect);box.add_child(join_button)
	if OS.has_feature("web"):
		url_input.hide()
		get_viewport().size_changed.connect(_layout_login)
		_layout_login()
	if token!="" or invitation!="": _connect()
	_publish_login_geometry.call_deferred()

func _layout_login() -> void:
	if not OS.has_feature("web"): return
	var css_width:=float(JavaScriptBridge.eval("window.innerWidth"))
	var factor:=get_viewport_rect().size.x/maxf(css_width,1.0)
	login.scale=Vector2.ONE*factor
	login.position=Vector2(16,16)*factor
	login.custom_minimum_size=Vector2(clampf(css_width-32,240,420),0)
	_publish_login_geometry.call_deferred()

func _publish_login_geometry() -> void:
	if not OS.has_feature("web"): return
	await get_tree().process_frame
	var css_size:=Vector2(float(JavaScriptBridge.eval("window.innerWidth")),float(JavaScriptBridge.eval("window.innerHeight")))
	var conversion:=css_size/get_viewport_rect().size
	var input:=invite_input.get_global_rect();var button:=join_button.get_global_rect()
	input=Rect2(input.position*conversion,input.size*conversion)
	button=Rect2(button.position*conversion,button.size*conversion)
	JavaScriptBridge.eval("window.primordiaConnectionDiagnostics="+JSON.stringify({"invite_present":invitation!="","status":status.text,"connected":connected,"loading":loading_world,"stage":connection_stage,"key_visible":invite_input.visible,"join_visible":join_button.visible,"retrying":retry_enabled,"transport_failures":transport_failures,"attempts":connection_attempts,"key_characters":invite_input.text.length(),"user_arg_count":OS.get_cmdline_user_args().size(),"invitation_bounds":[input.position.x,input.position.y,input.size.x,input.size.y],"join_bounds":[button.position.x,button.position.y,button.size.x,button.size.y]}))

func _toggle_user_pause() -> void:
	if not connected or world.revision==0:return
	user_paused=not user_paused
	touch_zoom.cancel()
	if user_paused:
		build_open=false;selected=-1;moving_id=-1;tube_start.clear();cell_ui.close_context()
	else:
		var latest:=paused_snapshot;paused_snapshot={}
		if not latest.is_empty():_snapshot(latest)
		for cell in world.cells:cell.previous_position=cell.position;cell.previous_angle=cell.angle
		for packet in world.particles:packet.previous=packet.p;packet.previous_angle=packet.angle
		if network_particles!=null:network_particles.prepare(world.particles,world.cells)
		received_usec=0
	touch_zoom.layout()

func _follow_cell():
	return focus_cell if focus_cell!=null else world.player

func _snapshot_focus(data: Dictionary) -> void:
	var incoming=data.get("focus",data.player if not data.player.dead else null)
	focus_cell=null
	if incoming==null:return
	for cell in world.cells:
		if cell.id==incoming.id:focus_cell=cell;return
	focus_cell=_copy_cell(incoming);world.cells.append(focus_cell)

func touch_controls_available() -> bool:
	return connected and not login.visible and world.revision>0

func _input(event: InputEvent) -> void:
	if login.visible: return # Controls receive every key; pond shortcuts cannot consume credentials.
	super(event)
func _unhandled_input(event: InputEvent) -> void:
	if login.visible: return
	super(event)
func _configure_backend() -> void: pass
func _restart(_profile: int=-1) -> void:
	_message("The shared world cannot be restarted by a client.")
func is_paused() -> bool: return user_paused
func _physics_process(_dt: float) -> void:
	if music.refill_between_ticks: music.refill()
func _update_world(_alpha: float) -> void:
	var alpha:=clampf((Time.get_ticks_usec()-received_usec)/interval_usec,0,1) if received_usec>0 and not user_paused else 1.0
	network_alpha=alpha
	super(alpha)
func _process(dt: float) -> void:
	_poll_network()
	super(dt)
	view_clock+=dt;keepalive_clock+=dt
	if connected and view_clock>=.2:
		view_clock=0
		var view:=Vector4(render_camera.x,render_camera.y,world.view_half.x,world.view_half.y)
		var size:=get_viewport_rect().size
		var base:=minf(size.x/Simulation.VIEW.x,size.y/Simulation.VIEW.y)
		var detail:=_camera_bounds(size/(2*base*MIN_ZOOM))
		detail=Vector2(minf(2048,detail.x),minf(1280,detail.y))
		if not view_announced or view!=last_camera or detail!=last_detail or perception!=last_perception:
			_send({"op":"view","rect":[view.x,view.y,view.z,view.w],"detail":[detail.x,detail.y],"perception":perception})
			last_camera=view;last_detail=detail;last_perception=perception;view_announced=true;keepalive_clock=0
		elif keepalive_clock>=2:
			_send({"op":"ping"});keepalive_clock=0
	if not connected and attempted and retry_enabled and (token!="" or invitation!="") and socket.get_ready_state()==WebSocketPeer.STATE_CLOSED:
		reconnect_due-=dt
		if reconnect_due<=0: reconnect_due=3;_connect(false)
	_send_next()

func _show_connection(text: String,credentials: bool=false,retry: bool=false) -> void:
	status.text=text;login.show()
	invite_input.visible=credentials;url_input.visible=credentials and not OS.has_feature("web")
	join_button.visible=credentials or retry;join_button.disabled=not (credentials or retry)
	join_button.text="Sign in" if credentials else "Reconnect"
	if not credentials:
		invite_input.release_focus();DisplayServer.virtual_keyboard_hide()
	_publish_login_geometry.call_deferred()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.primordiaDiagnostics=Object.assign(window.primordiaDiagnostics||{},"+JSON.stringify({"connected":connected})+")")

func _connect(manual: bool=true) -> void:
	if connected or connecting:return
	connection_attempts+=1
	var address:=url_input.text.strip_edges() if url_input.text!="" else server_url
	if address!=server_url: server_url=address;_load_identity()
	invitation=invite_input.text.strip_edges()
	if manual: transport_failures=0
	if token=="" and invitation=="":
		retry_enabled=false;attempted=false
		connection_stage="sign_in"
		_show_connection("Paste your personal access key, then press Sign in. The shared world is already running.",true)
		return
	if socket.get_ready_state()!=WebSocketPeer.STATE_CLOSED: socket.close(-1)
	socket=WebSocketPeer.new();socket.inbound_buffer_size=Protocol.MAX_FRAME;socket.outbound_buffer_size=65536;socket.max_queued_packets=8
	hello_sent=false;connected=false;connecting=true;attempted=true;retry_enabled=true;reconnect_due=3;inflight.clear();commands.clear()
	view_announced=false;view_clock=0;keepalive_clock=0;received_usec=0
	user_paused=false;paused_snapshot={};touch_zoom.cancel();camera_initialized=false
	connect_started_usec=Time.get_ticks_usec()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(BROWSER_SOCKET_ADDRESS % JSON.stringify(server_url))
	if socket.connect_to_url(server_url)!=OK:
		connecting=false;retry_enabled=false
		connection_stage="error"
		_show_connection("Cannot connect to this server address. Check it and try again.",not OS.has_feature("web"),true)
		return
	connection_stage="connecting"
	_show_connection("Connecting to the shared pond…")

func _connection_closed(code: int,reason: String) -> void:
	connecting=false;connected=false;loading_world=false;commands.clear();inflight.clear();connection_stage="disconnected"
	if code==1008:
		retry_enabled=false
		var explanation:="The server refused this connection. Check your access key and try again."
		match reason:
			"Invalid access key","Invalid invitation","Access key required": explanation="Access key rejected or missing. Paste the key you were given and press Sign in again."
			"No unclaimed living cell": explanation="Your key is valid, but no unclaimed living cell is available in this pond. The world is still running."
			"Pond connection limit": explanation="The pond currently has eight connected players. Try again when a place is free."
			"Authentication timeout": explanation="Sign-in timed out. Press Sign in to retry."
		var needs_key: bool=reason in ["Invalid access key","Invalid invitation","Access key required"]
		if needs_key:token="";connection_stage="sign_in"
		_show_connection(explanation,needs_key,not needs_key)
	elif code==1000 and reason=="Session resumed elsewhere":
		retry_enabled=false
		_show_connection("This identity signed in on another browser. Paste its key and press Sign in to return here.",true)
	else:
		transport_failures+=1;retry_enabled=transport_failures<3
		var text:="Connection lost; the world continues. Reconnecting…" if retry_enabled else "Cannot reach the game server. Check the address and press Sign in to retry."
		if not hello_sent and server_url.begins_with("wss://"):
			text="The game connection could not be opened. Reload this page and press Sign in again."
			if retry_enabled:text+=" Retrying…"
		_show_connection(text,false,not retry_enabled)

func _poll_network() -> void:
	socket.poll()
	if connecting and Time.get_ticks_usec()-connect_started_usec>15000000 and socket.get_ready_state()!=WebSocketPeer.STATE_OPEN:
		socket.close(-1);_connection_closed(-1,"");return
	if socket.get_ready_state()==WebSocketPeer.STATE_OPEN:
		if not hello_sent:
			_send({"op":"hello","token":token,"invite":invitation,"snapshot_ack":true,"compact_cytoplasm":true});hello_sent=true
		var polled:=0
		while socket.get_available_packet_count()>0 and polled<4:
			polled+=1
			var message:=Protocol.unpack(socket.get_packet())
			match message.get("kind",""):
				"welcome": _welcome(message)
				"snapshot": _snapshot(message)
				"snapshot_error":
					connection_stage="error";_show_connection(message.message)
				"result":
					if int(message.sequence)==int(inflight.get("sequence",-2)):
						edit_revision=message.get("edit",edit_revision)
						command_sequence=message.get("server_sequence",message.sequence)
						inflight.clear()
						_message(message.message)
						if cell_ui.pathways.visible: cell_ui.pathways._rebuild()
	else:
		if socket.get_ready_state()==WebSocketPeer.STATE_CLOSED and (connected or connecting):
			_connection_closed(socket.get_close_code(),socket.get_close_reason())

func _welcome(message: Dictionary) -> void:
	token=message.token;epoch=message.epoch;command_sequence=message.sequence;edit_revision=message.edit
	world.seed_value=message.seed;world.habitat_geometry=Codec.new().restore(message.habitat)
	habitat_view.configure(world.habitat_geometry)
	light_layer.material.set_shader_parameter("habitat_seed",float(posmod(world.seed_value,997)))
	connected=true;connecting=false;loading_world=true;retry_enabled=true;transport_failures=0;connection_stage="preparing"
	_save_identity();light_factor_shown=-1
	invitation="";invite_input.text=""
	_show_connection("Signed in. Preparing the world for your camera…")
	music.reset();_message("Connected · editing and chemistry remain live.")

func _ack_snapshot(message: Dictionary) -> void:
	if message.get("serial",0)>0:_send({"op":"snapshot_ack","serial":message.serial,"epoch":epoch})

func _snapshot(message: Dictionary) -> void:
	if int(message.epoch)!=epoch: return
	if user_paused:
		if not message.get("warming",false):paused_snapshot=message
		_ack_snapshot(message)
		return
	if message.get("warming",false):
		loading_world=true;connection_stage="preparing"
		_show_connection("Signed in. Preparing detailed water for your camera…")
		var initial=Codec.new().restore(message.graph)
		if initial is Dictionary:
			world.player=_copy_cell(initial.player)
			world.cells=[];_snapshot_focus(initial)
			if not camera_initialized:
				camera_locked=can_follow();camera_offset=Vector2.ZERO;free_camera=_follow_cell().position;camera_rotation=0
		return
	if login.visible:
		status.text="Connected to the shared pond.";login.hide();loading_world=false;connection_stage="ready"
		_publish_login_geometry.call_deferred()
	var data=Codec.new().restore(message.graph)
	if not data is Dictionary: return
	var previous_player: int=world.player.id
	var previous_focus: int=_follow_cell().id
	var models: Array=[]
	for incoming in data.cells:
		var cell=_copy_cell(incoming);models.append(cell)
	world.cells=models
	var player_visible: bool=models.any(func(c):return c.id==data.player.id)
	world.player=cells_by_id[data.player.id] if player_visible else _copy_cell(data.player)
	# The selected body is already in the snapshot graph; retain it for immediate refocus.
	if not player_visible:world.cells.append(world.player)
	_snapshot_focus(data)
	world.lineage=data.lineage;world.evolution=data.evolution
	if not camera_initialized or previous_player!=world.player.id:
		cell_ui.close_context();build_open=false;moving_id=-1;selected=-1
		touch_zoom.cancel()
		camera_offset=Vector2.ZERO;free_camera=_follow_cell().position;camera_locked=can_follow();camera_rotation=0
		camera_initialized=true
	elif camera_locked and not can_follow():
		camera_locked=false;free_camera=render_camera
	elif camera_locked and previous_focus!=_follow_cell().id:
		camera_offset=Vector2.ZERO
	if world.player.dead and can_follow():
		notice="Your lineage has ended · following a living cell for observation.";notice_timer=12
	world.time=message.time;world.revision=message.tick
	world.fluid.velocity=message.flow;world.acidity.values=message.acid
	world.sound_events=message.sounds;world.sound_sequence=message.sound_sequence;world.reaction_sparks=message.sparks
	if inflight.is_empty():
		command_sequence=maxi(command_sequence,message.sequence)
		edit_revision=maxi(edit_revision,message.edit)
	var now:=Time.get_ticks_usec()
	if received_usec>0: interval_usec=clampf(now-received_usec,50000,1000000)
	received_usec=now
	var bytes: PackedByteArray=message.particles
	var next: Dictionary={};var packets: Array=[]
	for at in range(0,bytes.size(),32):
		var identity:=Vector2i(bytes.decode_u32(at+24),bytes.decode_u32(at+28))
		var packet: Dictionary=packet_ids.get(identity,{})
		var position:=Vector2(bytes.decode_float(at),bytes.decode_float(at+4))
		var angle:=bytes.decode_float(at+8)
		packet.previous=packet.get("p",position);packet.previous_angle=packet.get("angle",angle)
		packet.p=position;packet.angle=angle;packet.kind=int(bytes.decode_float(at+12));packet.amount=bytes.decode_float(at+16)
		packet.alive=true;packet.updated=world.revision;packet.owner=-1;packet.v=Vector2.ZERO
		packet._handle=(int(identity.y)&0xffffffff)*4294967296+(int(identity.x)&0xffffffff);packet._index=packets.size()
		next[identity]=packet;packets.append(packet)
	packet_ids=next;world.particles=packets;world.grid.rebuild(packets)
	world.pheromones=packets.filter(func(p):return p.kind==3)
	world.active_particles=packets.size()
	if network_particles!=null: network_particles.prepare(packets,world.cells)
	_update_hud()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.primordiaDiagnostics="+JSON.stringify({"connected":connected,"tick":world.revision,"world_id":message.world_id,"packets":packets.size(),"cells":world.cells.size(),"time":world.time}))

	_ack_snapshot(message)

func _copy_cell(incoming):
	var cell=cells_by_id.get(incoming.id)
	if cell==null: cell=incoming;cells_by_id[cell.id]=cell
	else:
		var origins: Dictionary={}
		for packet in cell.chemistry.particles:origins[packet.id]={"p":packet.p,"angle":packet.angle}
		var previous: Vector2=cell.position;var heading: float=cell.angle
		for property in incoming.get_property_list():
			if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or property.name in Codec.DERIVED_CELL: continue
			cell.set(property.name,incoming.get(property.name))
		cell.previous_position=previous;cell.previous_angle=heading
		cell.chemistry.owner=weakref(cell)
		cell.chemistry.render_origins=origins
	return cell

func _queue_command(action: String,args: Dictionary) -> void:
	if user_paused:_message("Resume the view before editing this cell.");return
	if not connected or world.player.dead: _message("Reconnect before editing.");return
	if commands.size()>=16: _message("Waiting for pending edits.");return
	commands.append({"action":action,"args":_json_value(args),"cell":world.player.id})
	_message("Edit queued · the world continues.")

func _send_next() -> void:
	if not connected or not inflight.is_empty() or commands.is_empty(): return
	inflight=commands.pop_front()
	command_sequence+=1
	inflight.merge({"op":"command","epoch":epoch,"sequence":command_sequence,"edit":edit_revision})
	_send(inflight)

func _json_value(value):
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key in value: result[key]=_json_value(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(_json_value(item))
		return result
	return value

func _send(value: Dictionary) -> void:
	if socket.get_ready_state()==WebSocketPeer.STATE_OPEN: socket.send_text(JSON.stringify(value))

func _identity_path() -> String: return "user://primordia-"+server_url.sha256_text().left(16)+".identity"
func _load_identity() -> void:
	token=""
	if FileAccess.file_exists(_identity_path()):
		var file:=FileAccess.open(_identity_path(),FileAccess.READ)
		if file!=null: token=file.get_as_text().strip_edges()
func _save_identity() -> void:
	var file:=FileAccess.open(_identity_path(),FileAccess.WRITE)
	if file!=null: file.store_string(token)

func _sync_particles(_alpha: float=1.0) -> void:
	for item in batches: item.visible=false
	if network_particles!=null:
		network_particles.visible=perception=="exteroception"
		if network_particles.visible:network_particles.draw_camera(render_camera,network_alpha)
