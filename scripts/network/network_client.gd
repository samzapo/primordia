extends "res://scripts/pond.gd"
var family_recovery: Dictionary={}
var server_census: Dictionary={}
var update_popup=preload("res://scripts/update_popup.gd").new()
var pending_release_updates: Array=[]
var defer_release_updates:=false
var merge_tombstones: Dictionary={}
var presentation_hidden:=false
var last_presence:=""
var visibility_callback: JavaScriptObject
var received_merge_serial:=0
var received_death_serial:=0
var death_tombstones: Dictionary={}
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
var logout_menu_button: Button
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
var playback=preload("res://scripts/network/snapshot_playback.gd").new()
var playback_domain:=""
var playback_after_tick:=-1
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
var camera_seen_world:=false
var focus_cell
var loading_world := false
var connection_stage := "sign_in"

func _ready() -> void:
	tree_exiting.connect(func():
		if visibility_callback!=null:
			JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange",visibility_callback)
			visibility_callback=null)
	if OS.has_feature("web"):
		visibility_callback=JavaScriptBridge.create_callback(_visibility_changed)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange",visibility_callback)
	_empty_remote_world()
	if OS.has_feature("web"):
		server_url = str(JavaScriptBridge.eval("(location.protocol==='https:'?'wss://':'ws://')+location.host+new URL('./ws',location.href).pathname"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--connect="): server_url=arg.trim_prefix("--connect=")
		elif arg.begins_with("--invite="): invitation=arg.trim_prefix("--invite=")
	_load_identity()
	super()
	update_popup.initialize(ui)
	update_popup.dismissed.connect(func(id):_send({"op":"update_seen","id":id}))
	update_popup.unconfirmed.connect(func(_id):defer_release_updates=true)
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

func _empty_remote_world() -> void:
	world = Simulation.new(0,0,false)
	world.server_mode=true;world.remote_client=true;world.evolution.sandbox=true
	world.command_sink=_queue_command
	world.player.dead=true;world.cells=[]
	world.habitat_geometry=Simulation.Habitat.new(0,[])
	world.native_render=false;world.native_particle_render_cache=false

func _build_ui() -> void:
	super()
	logout_menu_button=_button(session_controls,"Log out",_logout)
	session_controls.move_child(logout_menu_button,0)

func _logout() -> void:
	# Only this browser's login is forgotten. The authority keeps the account,
	# its current cell, lineage, reports and access key.
	if connected:_send({"op":"presence","state":"paused"})
	socket.close(1000,"Logged out")
	socket=WebSocketPeer.new() # No old welcome/result can restore the old login.
	token="";invitation="";invite_input.clear();_save_identity()
	connected=false;connecting=false;loading_world=false;attempted=false;retry_enabled=false
	hello_sent=false;transport_failures=0;reconnect_due=0
	commands.clear();inflight.clear();cell_ui.pending_mutation.clear();placement_feedback.clear()
	command_sequence=0;edit_revision=0;epoch=0;view_announced=false;received_usec=0
	update_popup.close();pending_release_updates.clear();defer_release_updates=false
	player_help.close();feedback.close();profile.close();palette.close()
	feedback.pending=false;feedback.title.clear();feedback.details.clear();feedback.report_id="";feedback.content_hash=""
	profile.pending=false;palette.pending=false
	cell_ui.close_context();build_open=false;selected=-1;moving_id=-1;tube_start.clear()
	settings_panel.hide();lineage_confirmation.hide();lineage_confirming=false
	user_paused=false;paused_snapshot={};touch_zoom.cancel()
	playback.reset();playback_domain="";playback_after_tick=-1
	cells_by_id.clear();packet_ids.clear();family_portraits.clear();family_recovery.clear();server_census.clear()
	focus_cell=null;player_name="";favorite_name="";last_presence=""
	camera_initialized=false;camera_seen_world=false
	death_tombstones.clear();merge_tombstones.clear()
	music.reset();_empty_remote_world()
	death_view.reset(world);merge_view.reset(world)
	if network_particles!=null:network_particles.prepare([],[])
	connection_stage="sign_in"
	_show_connection("Logged out. Paste another player’s access key to sign in.",true)

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
	if user_paused:_ease_camera()
	if not connected or world.revision==0:return
	if settings_panel.visible and not user_paused:user_paused=true
	if not user_paused:_freeze_network_pose()
	user_paused=not user_paused
	touch_zoom.cancel()
	if user_paused:
		build_open=false;selected=-1;moving_id=-1;tube_start.clear();cell_ui.close_context()
	else:
		settings_panel.hide()
		merge_view.reset(world,received_merge_serial);world.merge_bursts.clear()
		for view in views.values():view.raster_dirty=true
		playback.reset();playback_domain="";playback_after_tick=-1
		var latest:=paused_snapshot;paused_snapshot={}
		if not latest.is_empty():
			# Resume at the live world; do not replay deaths that happened while paused.
			latest.deaths=[];latest.merges=[]
			_snapshot(latest)
		for cell in world.cells:cell.previous_position=cell.position;cell.previous_angle=cell.angle
		for packet in world.particles:packet.previous=packet.p;packet.previous_angle=packet.angle
		if network_particles!=null:network_particles.prepare(world.particles,world.cells)
		received_usec=0
	touch_zoom.layout()

func _freeze_network_pose() -> void:
	# Pause holds precisely the visible presentation, not the newer buffered target.
	for cell in world.cells:
		cell.position=Simulation.Medium.wrap_position(cell.previous_position+Simulation.Medium.offset(cell.previous_position,cell.position)*network_alpha)
		cell.angle=lerp_angle(cell.previous_angle,cell.angle,network_alpha)
		cell.previous_position=cell.position;cell.previous_angle=cell.angle
		for packet in cell.chemistry.particles:
			var origin: Dictionary=cell.chemistry.render_origins.get(packet.id,{})
			packet.p=origin.get("p",packet.p).lerp(packet.p,network_alpha)
			packet.angle=lerp_angle(origin.get("angle",packet.angle),packet.angle,network_alpha)
		cell.chemistry.render_origins.clear()
	for packet in world.particles:
		packet.p=Simulation.Medium.wrap_position(packet.previous+Simulation.Medium.offset(packet.previous,packet.p)*network_alpha)
		packet.angle=lerp_angle(packet.previous_angle,packet.angle,network_alpha)
		packet.previous=packet.p;packet.previous_angle=packet.angle
	network_alpha=1
	if network_particles!=null:network_particles.prepare(world.particles,world.cells)

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
	if login.visible or update_popup.opened or lineage_confirming: return # Controls receive every key; pond shortcuts cannot consume credentials.
	super(event)
func _unhandled_input(event: InputEvent) -> void:
	if login.visible or update_popup.opened or lineage_confirming: return
	super(event)
func _configure_backend() -> void: pass
func _start_new_lineage() -> void:
	if not connected:_message("Reconnect before starting a new lineage.");return
	if not commands.is_empty() or not inflight.is_empty():_message("Wait for the current edit to finish.");return
	if user_paused:_toggle_user_pause()
	settings_panel.hide()
	_queue_command("start_lineage",{"confirmed":true})

func _restart(_profile: int=-1) -> void:
	_message("The shared world cannot be restarted by a client.")
func is_paused() -> bool: return user_paused
func _physics_process(_dt: float) -> void:
	if music.refill_between_ticks: music.refill()
func _update_world(_alpha: float) -> void:
	var alpha:=1.0
	if not user_paused:
		var sample: Dictionary=playback.sample(Time.get_ticks_usec()/1000000.0)
		if not sample.is_empty():
			var before: Dictionary=sample.before;var after: Dictionary=sample.after
			if playback_after_tick!=int(after.tick):
				# If a suspended/stalled browser skipped an endpoint, restore its actual
				# predecessor before blending. Never restart from a half-drawn pose.
				if playback_after_tick!=int(before.tick):_snapshot(before)
				if int(before.tick)!=int(after.tick):_snapshot(after)
				playback_after_tick=int(after.tick)
			alpha=sample.alpha
			world.time=lerpf(float(before.time),float(after.time),alpha)
	network_alpha=alpha
	super(alpha)
func _visibility_changed(_args: Array) -> void:
	# Browser events still run when rendering is throttled in a background tab.
	var hidden: bool=bool(JavaScriptBridge.eval("document.hidden"))
	if not hidden:
		for view in views.values():view.raster_dirty=true
	_publish_presence(hidden)

func _publish_presence(hidden: bool) -> void:
	var presence: String="hidden" if hidden else "paused" if user_paused or settings_panel.visible else "active"
	if connected and presence!=last_presence:
		_send({"op":"presence","state":presence});last_presence=presence

func _process(dt: float) -> void:
	_poll_network()
	super(dt)
	var hidden: bool=bool(JavaScriptBridge.eval("document.hidden")) if OS.has_feature("web") else DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED
	if presentation_hidden and not hidden:
		merge_view.reset(world,received_merge_serial);world.merge_bursts.clear()
	presentation_hidden=hidden
	_publish_presence(hidden)
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
	hello_sent=false;connected=false;connecting=true;attempted=true;retry_enabled=true;reconnect_due=3;inflight.clear();commands.clear();cell_ui.pending_mutation.clear();placement_feedback.clear()
	view_announced=false;view_clock=0;keepalive_clock=0;received_usec=0
	update_popup.close();pending_release_updates=[]
	playback.reset();playback_domain="";playback_after_tick=-1;user_paused=false;paused_snapshot={};touch_zoom.cancel();camera_initialized=false
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
	update_popup.close();pending_release_updates=[];player_help.close()
	playback.reset();playback_domain="";playback_after_tick=-1
	connecting=false;connected=false;loading_world=false;commands.clear();inflight.clear();cell_ui.pending_mutation.clear();placement_feedback.clear();connection_stage="disconnected"
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
			_send({"op":"hello","token":token,"invite":invitation,"snapshot_ack":true,"compact_cytoplasm":true,"cytoplasm_version":2,"death_events":true});hello_sent=true
		var polled:=0
		while socket.get_available_packet_count()>0 and polled<4:
			polled+=1
			var message:=Protocol.unpack(socket.get_packet())
			match message.get("kind",""):
				"death_events": _receive_deaths(message)
				"profile_result": profile.result(message)
				"lineage_color_result": palette.result(message)
				"feedback_result": feedback.result(message)
				"update_seen_result": _release_result(message)
				"welcome": _welcome(message)
				"snapshot":
					_receive_snapshot(message)
					break # Bound burst decoding to one potentially large snapshot per frame.
				"snapshot_error":
					connection_stage="error";_show_connection(message.message)
				"result":
					if int(message.sequence)==int(inflight.get("sequence",-2)):
						edit_revision=message.get("edit",edit_revision)
						command_sequence=message.get("server_sequence",message.sequence)
						cell_ui.command_result(inflight,message)
						if inflight.has("local_placement"):placement_feedback.result(inflight.local_placement,message.get("ok",false),int(message.get("edit",-1)))
						inflight.clear()
						_message(message.message)
						if cell_ui.pathways.visible: cell_ui.pathways._rebuild()
	else:
		if socket.get_ready_state()==WebSocketPeer.STATE_CLOSED and (connected or connecting):
			_connection_closed(socket.get_close_code(),socket.get_close_reason())

func _welcome(message: Dictionary) -> void:
	defer_release_updates=false;update_popup.close()
	if settings_panel.visible:user_paused=true
	playback.reset();playback_domain="";playback_after_tick=-1
	pending_release_updates=message.get("release_updates",[]).duplicate(true)
	if pending_release_updates.is_empty() and not message.get("release_notes",{}).is_empty():pending_release_updates=[message.release_notes.duplicate(true)]
	camera_initialized=false;cells_by_id.clear();packet_ids.clear();received_usec=0
	world.death_bursts.clear();world.death_serial=message.get("death_serial",0)
	death_world=world;death_seen=world.death_serial;death_focus_age=2.0
	received_death_serial=world.death_serial;death_tombstones.clear()
	death_view.reset(world,world.death_serial)
	received_merge_serial=int(message.get("merge_serial",0));world.merge_serial=received_merge_serial;world.merge_bursts.clear();merge_tombstones.clear();merge_view.reset(world,received_merge_serial)
	player_name=str(message.get("player_name",""));favorite_name=str(message.get("favorite_name",""));last_presence=""
	token=message.token;epoch=message.epoch;command_sequence=message.sequence;edit_revision=maxi(edit_revision,int(message.edit))
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

func _receive_deaths(message: Dictionary) -> void:
	if int(message.get("epoch",-1))!=epoch:return
	for event in message.get("merges",[]):
		var repeated: bool=merge_tombstones.has(int(event.donor))
		merge_tombstones[int(event.donor)]=true
		received_merge_serial=maxi(received_merge_serial,int(event.serial));world.merge_serial=received_merge_serial
		if merge_tombstones.size()>64:merge_tombstones.erase(merge_tombstones.keys()[0])
		if not user_paused:
			if cells_by_id.has(int(event.donor)):cells_by_id[int(event.donor)].dead=true
			world.lineage.records=world.lineage.records.filter(func(record):return record.id!=int(event.donor))
			family_portraits.erase(int(event.donor))
		if repeated or user_paused or presentation_hidden or float(message.get("time",world.time))-float(event.time)>merge_view.LIFETIME:continue
		world.merge_bursts.append(event.duplicate(true))
		if world.merge_bursts.size()>32:world.merge_bursts.pop_front()

	world.death_serial=maxi(world.death_serial,int(message.get("death_serial",world.death_serial)))
	if user_paused:
		received_death_serial=maxi(received_death_serial,world.death_serial);return
	var consumed: int=mini(death_seen,death_view.seen)
	world.death_bursts.assign(world.death_bursts.filter(func(event):return event.serial>consumed and death_view.recent(event,world.time)))
	for event in message.get("deaths",[]):
		if int(event.serial)<=received_death_serial:continue
		received_death_serial=int(event.serial)
		if float(message.get("time",world.time))-float(event.time)>death_view.LIFETIME:continue
		var fact: Dictionary=event.duplicate(true);fact["_arrived_usec"]=Time.get_ticks_usec()
		world.death_bursts.append(fact)
		if world.death_bursts.size()>32:world.death_bursts.pop_front()
		if event.has("id"):
			death_tombstones[event.id]=true
			if cells_by_id.has(event.id):cells_by_id[event.id].dead=true
			if death_tombstones.size()>32:death_tombstones.erase(death_tombstones.keys()[0])

func _receive_snapshot(message: Dictionary) -> void:
	if int(message.epoch)!=epoch:return
	_receive_deaths(message) # Ruptures remain immediate, independent of the view buffer.
	_ack_snapshot(message)
	if user_paused:
		playback.reset()
		if not message.get("warming",false):paused_snapshot=message
		return
	if message.get("perception",perception)!=perception:return
	if message.get("warming",false):
		# A moving camera can warm a new region while the current view is valid.
		# Do not overwrite buffered endpoints or reopen sign-in during that handoff.
		if loading_world:_snapshot(message)
		return
	if playback_domain!=perception:
		playback.reset();playback_domain=perception;playback_after_tick=-1
	playback.push(message,Time.get_ticks_usec()/1000000.0)

func _snapshot(message: Dictionary) -> void:
	if int(message.epoch)!=epoch: return
	_receive_deaths(message)
	lineage_names=message.get("lineage_names",[]);player_name=str(message.get("player_name",player_name));favorite_name=str(message.get("favorite_name",favorite_name))
	if user_paused:
		if not message.get("warming",false):paused_snapshot=message
		_ack_snapshot(message)
		return
	if message.get("warming",false):
		loading_world=true;connection_stage="preparing"
		_show_connection("Signed in. Preparing detailed water for your camera…")
		var initial=Codec.new().restore(message.graph,true)
		if initial is Dictionary:
			world.player=_copy_cell(initial.player)
			world.cells=[];_snapshot_focus(initial)
			if not camera_initialized:
				camera_locked=can_follow();camera_offset=Vector2.ZERO;free_camera=_follow_cell().position;camera_rotation=0
		return
	if login.visible:
		status.text="Connected to the shared pond.";login.hide();loading_world=false;connection_stage="ready"
		_publish_login_geometry.call_deferred()
	var restore_mark:=Time.get_ticks_usec() if frame_trace!=null else 0
	var data=Codec.new().restore(message.graph,true)
	if frame_trace!=null:frame_trace.work("snapshot_restore",Time.get_ticks_usec()-restore_mark)
	if not data is Dictionary: return
	if not camera_initialized:
		if camera_seen_world:_ease_camera()
		else:camera_has_pose=false;camera_followed_id=-1;camera_motion.cancel()
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
	var retained_ids: Dictionary={}
	for cell in world.cells:retained_ids[cell.id]=true
	for identity in cells_by_id.keys():
		if not retained_ids.has(identity):cells_by_id.erase(identity)
	world.lineage=data.lineage;world.evolution=data.evolution
	world.remote_division=message.get("division",{}).duplicate(true)
	merge_available=message.get("merge_available",{}).duplicate(true)
	world.investment=data.get("investment",{"npc":{},"lineages":{},"cells":{}})
	family_portraits=message.get("family_portraits",{}).duplicate()
	world.lineage.records=world.lineage.records.filter(func(record):return not merge_tombstones.has(int(record.id)))
	for retired in merge_tombstones:family_portraits.erase(retired)
	family_recovery=message.get("family_recovery",{})
	if not camera_initialized or previous_player!=world.player.id:
		merge_selection.clear();merge_candidates.clear()
		cell_ui.close_context();build_open=false;moving_id=-1;selected=-1
		touch_zoom.cancel()
		camera_offset=Vector2.ZERO;free_camera=_follow_cell().position;camera_locked=can_follow();camera_rotation=0
		camera_initialized=true;camera_seen_world=true
	elif camera_locked and not can_follow():
		camera_locked=false;free_camera=render_camera
	elif camera_locked and previous_focus!=_follow_cell().id:
		camera_offset=Vector2.ZERO
	if world.player.dead and can_follow():
		notice="Your lineage has ended · following a living cell for observation.";notice_timer=12
	server_census=message.get("census",{}).duplicate()
	world.time=message.time;world.revision=message.tick
	world.death_serial=maxi(world.death_serial,message.get("death_serial",world.death_serial))
	world.environment=message.get("environment",{})
	world.fluid.velocity=message.flow;world.acidity.values=message.acid
	world.sound_events=message.sounds;world.sound_sequence=message.sound_sequence;world.reaction_sparks=message.sparks
	if inflight.is_empty():
		command_sequence=maxi(command_sequence,message.sequence)
		edit_revision=maxi(edit_revision,message.edit)
	received_usec=Time.get_ticks_usec()
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
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.primordiaDiagnostics="+JSON.stringify({"fps":Engine.get_frames_per_second(),"frame_ms":last_frame_ms,"view_sync_ms":render_ms,"current_art":flow_view.curve_budget.diagnostics(),"playback":playback.diagnostics(),"connected":connected,"tick":world.revision,"world_id":message.world_id,"packets":packets.size(),"camera_packets":server_census.get("camera_particles",packets.size()),"buffered_packets":server_census.get("buffered_particles",packets.size()),"coverage":str(message.get("coverage",Vector4.ZERO)),"cells":world.cells.size(),"time":world.time,"player_name":player_name,"nameplates":nameplates.items.map(func(item):return {"cell":item.cell,"name":item.name,"online":item.online})}))

	placement_feedback.reconcile(int(message.get("edit",-1)))
	_show_next_update()

func _show_next_update() -> void:
	if defer_release_updates or not connected or loading_world or login.visible or update_popup.opened or update_popup.pending or pending_release_updates.is_empty():return
	if player_help.opened or feedback.opened or profile.opened or palette.opened or settings_panel.visible:return
	var notes: Dictionary=pending_release_updates[0].duplicate(true)
	if pending_release_updates.size()>1:notes.button="Next update"
	touch_zoom.cancel();update_popup.open(notes)
func _release_result(message: Dictionary) -> void:
	var current: bool=message.get("id","")==update_popup.release_id
	update_popup.result(message)
	if current and message.get("ok",false):
		if not pending_release_updates.is_empty() and pending_release_updates[0].id==message.id:pending_release_updates.pop_front()
		_show_next_update.call_deferred()

func _debug_population_lines() -> String:
	return population_text(server_census,world.particles.size())+"\nState updates: %.2fs apart · buffer %.2fs · underruns %d · resyncs %d" % [playback.period,playback.delay,playback.underruns,playback.resyncs]

static func population_text(server_census: Dictionary,local_count: int) -> String:
	if server_census.is_empty():return "\nCamera region: %d particles\nHabitat total: waiting for server" % local_count
	return "\nCamera region: %d particles\nHabitat total: %d living cells / %d particles\nExterior: %d · Inside cells: %d\nGPU resident: %d · Offscreen: %d · Queued: %d" % [server_census.get("camera_particles",local_count),server_census.get("living_cells",0),server_census.get("total",server_census.get("external",0)),server_census.get("external",0),server_census.get("internal",0),server_census.get("gpu",0),server_census.get("cold",0),server_census.get("pending",0)]

static var cell_copy_fields: Array[String]=[]
static func _cell_copy_fields(incoming) -> Array[String]:
	if cell_copy_fields.is_empty():
		for property in incoming.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name not in Codec.DERIVED_CELL:
				cell_copy_fields.append(property.name)
	return cell_copy_fields

func _copy_cell(incoming):
	var cell=cells_by_id.get(incoming.id)
	if cell==null: cell=incoming;cells_by_id[cell.id]=cell
	else:
		var origins: Dictionary={}
		for packet in cell.chemistry.particles:
			origins[packet.id]={"p":packet.p,"angle":packet.angle}
		var previous: Vector2=cell.position;var heading: float=cell.angle
		for key in _cell_copy_fields(incoming):cell.set(key,incoming.get(key))
		cell.previous_position=previous;cell.previous_angle=heading
		cell.chemistry.owner=weakref(cell)
		cell.chemistry.render_origins=origins
	if death_tombstones.has(cell.id) or merge_tombstones.has(cell.id):cell.dead=true
	return cell

func _submit_lineage_color(value: String) -> String:
	if not connected:return "Reconnect before saving your color."
	_send({"op":"lineage_color","color":value});return ""

func _submit_profile(value: String,favorite: String="") -> String:
	if not connected:return "Reconnect before saving your name. Your text is kept."
	_send({"op":"profile","name":value,"favorite_name":favorite});return ""

func _submit_feedback(report: Dictionary) -> String:
	if not connected:return "Reconnect before submitting. Your draft is kept."
	var message: Dictionary=report.duplicate();message.op="feedback"
	if OS.has_feature("web"):
		message.client_pack=str(JavaScriptBridge.eval("typeof GODOT_CONFIG==='object' ? GODOT_CONFIG.mainPack || '' : ''")).get_file().left(100)
	_send(message)
	return ""

func _queue_command(action: String,args: Dictionary) -> bool:
	if user_paused:_message("Resume the view before editing this cell.");return false
	if not connected or world.player.dead: _message("Reconnect before editing.");return false
	if commands.size()>=16: _message("Waiting for pending edits.");return false
	var command: Dictionary={"action":action,"args":_json_value(args),"cell":world.player.id}
	if action=="install":command.local_placement=placement_feedback.begin(world.player,str(args.kind),float(args.angle))
	commands.append(command)
	_message("Edit queued · the world continues.")
	_send_next() # Send on the input frame; never wait for a physics update.
	return true

func _send_next() -> void:
	if not connected or not inflight.is_empty() or commands.is_empty(): return
	inflight=commands.pop_front()
	command_sequence+=1
	inflight.merge({"op":"command","epoch":epoch,"sequence":command_sequence,"edit":edit_revision})
	var wire:=inflight.duplicate();wire.erase("local_placement")
	_send(wire)

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
