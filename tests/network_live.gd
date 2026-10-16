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
var camera_reports: Dictionary={}
var withheld_acks: Dictionary={}
var deferred_acks: Dictionary={}
func check(value: bool,message: String) -> void:
	assertions+=1
	if not value: failures+=1;push_error("FAIL: "+message)
var performance_warnings:=0
func check_performance(value: bool,message: String) -> void:
	if not value and OS.get_environment("PRIMORDIA_PERFORMANCE_WARNINGS")=="1":
		performance_warnings+=1
		print("::warning::PERFORMANCE_WARNING ",message)
	else:check(value,message)
func _initialize() -> void: run.call_deferred()
func poll() -> void:
	if Time.get_ticks_msec()-keepalive_at>=200:
		keepalive_at=Time.get_ticks_msec()
		for i in sockets.size():
			if sockets[i].get_ready_state()==WebSocketPeer.STATE_OPEN and not find_message(i,"welcome").is_empty():
				if not camera_reports.has(i):
					var initial:=find_message(i,"snapshot")
					if not initial.is_empty():
						var graph=preload("res://scripts/network/state_codec.gd").new().restore(initial.graph)
						camera_reports[i]={"op":"view","rect":[graph.player.position.x,graph.player.position.y,Sim.VIEW.x/.8/2,Sim.VIEW.y/.8/2]}
				sockets[i].send_text(JSON.stringify(camera_reports.get(i,{"op":"ping"})))
	for i in sockets.size():
		sockets[i].poll()
		while sockets[i].get_available_packet_count()>0:
			var message:=Protocol.unpack(sockets[i].get_packet());messages[i].append(message)
			if message.get("kind","")=="snapshot" and message.get("serial",0)>0:
				deferred_acks[i]={"op":"snapshot_ack","serial":message.serial,"epoch":message.epoch}
		if deferred_acks.has(i) and not withheld_acks.has(i):sockets[i].send_text(JSON.stringify(deferred_acks[i]));deferred_acks.erase(i)
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
	if "--slow-observer" in OS.get_cmdline_user_args():host.physics_hz=2
	# Match run_service.py: this window submits compute, while client camera
	# rectangles below still request full widest-view simulation fidelity.
	if not host.cpu:root.size=Vector2i(64,64)
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
	for i in sockets.size():sockets[i].send_text(JSON.stringify({"op":"hello","invite":fixture_keys[i] if personal_keys else OS.get_environment("PRIMORDIA_INVITE"),"snapshot_ack":true,"death_events":true,"compact_cytoplasm":true,"cytoplasm_version":2}))
	check(await until(func():return not find_message(0,"welcome").is_empty() and not find_message(1,"welcome").is_empty()),"distinct lineage accounts authenticated")
	var welcome0:=find_message(0,"welcome")
	var welcome1:=find_message(1,"welcome")
	check(welcome0.has("release_notes") and not welcome0.release_notes.is_empty(),"First sign-in carries the current player-facing release notes")
	sockets[0].send_text(JSON.stringify({"op":"update_seen","id":"unknown-release"}))
	check(await until(func():return not find_message(0,"update_seen_result").is_empty()),"Release acknowledgement returns an explicit receipt")
	check(not find_message(0,"update_seen_result").ok and not host.accounts[welcome0.token.sha256_text()].has("seen_release"),"Unknown release cannot suppress a real update")
	messages[0]=messages[0].filter(func(m):return m.get("kind","")!="update_seen_result")
	sockets[0].send_text(JSON.stringify({"op":"update_seen","id":welcome0.release_notes.id}))
	check(await until(func():return find_message(0,"update_seen_result").get("ok",false)),"Dismissing the update is durably acknowledged")
	check(host.ReleaseNotes.pending_all(host.accounts[welcome0.token.sha256_text()]).size()==welcome0.release_updates.size()-1 and host.ReleaseNotes.pending_all(host.accounts[welcome1.token.sha256_text()]).size()==welcome1.release_updates.size(),"Dismissal is per player and does not suppress other players’ notices")
	for update in welcome0.release_updates.slice(1):
		messages[0]=messages[0].filter(func(m):return m.get("kind","")!="update_seen_result")
		sockets[0].send_text(JSON.stringify({"op":"update_seen","id":update.id}))
		check(await until(func():return find_message(0,"update_seen_result").get("ok",false)),"Each missed update is durably cleared in order over a real socket")
	check(host.ReleaseNotes.pending_all(host.accounts[welcome0.token.sha256_text()]).is_empty(),"The account has no replay after every missed update is cleared")
	check(welcome0.cell!=welcome1.cell,"accounts own distinct cells")
	sockets[0].send_text(JSON.stringify({"op":"profile","name":"  Sam 🌱  "}))
	check(await until(func():return not find_message(0,"profile_result").is_empty()),"Player name can be saved over the authenticated socket")
	check(find_message(0,"profile_result").get("ok",false) and host.accounts[welcome0.token.sha256_text()].display_name=="Sam 🌱","Name is trimmed and saved on the account")
	var public_names: Array=host._lineage_names()
	check(public_names.any(func(row):return row.name=="Sam 🌱" and row.online) and public_names.all(func(row):return row.size()==3 and row.has("root") and row.has("name") and row.has("online")),"Lineage labels expose only names, roots and connected status")
	messages[0]=messages[0].filter(func(m):return m.get("kind","")!="profile_result")
	sockets[0].send_text(JSON.stringify({"op":"profile","name":"bad\nname"}))
	check(await until(func():return not find_message(0,"profile_result").is_empty()),"Invalid name has an explicit receipt")
	check(not find_message(0,"profile_result").get("ok",true) and host.accounts[welcome0.token.sha256_text()].display_name=="Sam 🌱","Control characters cannot change the saved player name")
	check(await until(func():return host.world.camera_views.size()==2),"camera union tracks both clients")
	check(await until(func():return messages[0].any(func(m):return m.get("kind","")=="snapshot" and m.get("particles",PackedByteArray()).size()>0 and not m.get("warming",true))),"bounded particle publication reaches client")
	var census_frame: Dictionary=messages[0].filter(func(message):return message.get("kind","")=="snapshot" and not message.get("warming",true) and message.get("serial",0)>0)[-1]
	check(census_frame.has("census") and census_frame.census.has("external") and census_frame.census.has("living_cells") and census_frame.census.camera_particles==census_frame.particles.size()/32,"Snapshots deliver a distinct authoritative global census and camera-record count")
	withheld_acks[0]=true
	check(await until(func():return deferred_acks.has(0)),"Slow browser leaves one complete snapshot awaiting acknowledgement")
	var slow_peer: Dictionary=host.peers.values().filter(func(peer):return peer.account==welcome0.token.sha256_text())[0]
	var pending_serial: int=slow_peer.awaiting_snapshot
	var received_count: int=messages[0].filter(func(m):return m.get("serial",0)>0).size()
	var flow_time: float=host.world.time
	check(await until(func():return host.world.time>flow_time+.1),"Authority keeps simulating while a browser processes its snapshot")
	check(slow_peer.awaiting_snapshot==pending_serial and messages[0].filter(func(m):return m.get("serial",0)>0).size()==received_count,"An unacknowledged browser cannot accumulate another full snapshot")
	sockets[0].send_text(JSON.stringify({"op":"snapshot_ack","serial":pending_serial+1,"epoch":host.epoch}))
	await process_frame;poll();await process_frame
	check(slow_peer.awaiting_snapshot==pending_serial,"A wrong acknowledgement cannot release the pending frame")
	withheld_acks.erase(0)
	check(await until(func():return messages[0].any(func(m):return m.get("serial",0)>pending_serial)),"Processing acknowledgement automatically resumes advancing world delivery")
	check(await until(func():return camera_reports.has(0) and camera_reports.has(1)),"both fixture cameras are advertised before changing perception")
	camera_reports[0]["perception"]="interoception"
	check(await until(func():return host.world.camera_views.size()==1 and host.world.interoceptive_cells.has(welcome0.cell)),"Inside and outside clients retain independent detail interests")
	var column_peer: Dictionary=host.peers.values().filter(func(peer):return peer.account==welcome0.token.sha256_text())[0]
	var current_columns: Dictionary=host._frame(column_peer)
	column_peer.cytoplasm_version=1
	var legacy_columns: Dictionary=host._frame(column_peer)
	check(current_columns.graph.objects.any(func(record):return record.kind=="chemistry" and record.fields.particles.get("$cytoplasm",0)==2) and legacy_columns.graph.objects.any(func(record):return record.kind=="chemistry" and record.fields.particles.get("$cytoplasm",0)==1),"Current and already-open older browsers receive their negotiated cytoplasm format")
	column_peer.cytoplasm_version=2
	var switch_tick: int=host.world.revision
	check(await until(func():return messages[0].any(func(m):return m.get("kind","")=="snapshot" and m.get("perception","")=="interoception" and m.get("tick",0)>switch_tick and m.get("particles",PackedByteArray()).is_empty())),"Inside snapshots advance without external pose bytes")
	camera_reports[1]["perception"]="interoception"
	check(await until(func():return host.world.camera_views.is_empty() and host.world.interoceptive_cells.size()==2),"All-inside clients release all external fine footprints")
	switch_tick=host.world.revision
	check(await until(func():return messages[1].any(func(m):return m.get("kind","")=="snapshot" and m.get("perception","")=="interoception" and m.get("tick",0)>switch_tick)),"Internal views continue with zero external cameras")
	for report in camera_reports.values():report["perception"]="exteroception"
	check(await until(func():return host.world.camera_views.size()==2 and host.world.interoceptive_cells.is_empty()),"Returning outside restores the external camera union and coarsens hidden interiors")
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
	var clock_before: float=host.world.time;var revision_before: int=host.world.revision
	check(await until(func():return host.world.revision>=revision_before+3),"Authority advances three scheduled physics steps")
	check(absf((host.world.time-clock_before)-(host.world.revision-revision_before)/float(host.physics_hz))<.000001,"Every scheduled authority tick advances exactly its actual fixed interval")
	check(host.checkpoint(),"account and world checkpoint completes")
	var saved: Dictionary=host.store.load_latest()
	if not host.cpu: check(saved.stream_rng==PackedInt64Array([host.world.resident.streaming.random.seed,host.world.resident.streaming.random.state]),"cold transport random stream is checkpointed")
	check(saved.particle_resolution_version==preload("res://scripts/network/particle_resolution.gd").VERSION,"checkpoint records resolution so restarts cannot compact again")
	var restored=preload("res://scripts/network/state_codec.gd").new().restore(saved.graph)
	check(host.ReleaseNotes.pending(restored.accounts[welcome0.token.sha256_text()]).is_empty(),"Update dismissal survives a restored account on another browser")
	check(restored.accounts[welcome0.token.sha256_text()].display_name=="Sam 🌱","Chosen player name survives checkpoint restoration")
	check(restored.accounts[welcome0.token.sha256_text()].sequence==1,"idempotency sequence survives restart")
	var restored_account: Dictionary = restored.accounts[welcome0.token.sha256_text()]
	check(restored.world.family_ledgers.any(func(ledger):return ledger == restored_account.lineage) and restored_account.lineage.root_id == restored_account.root,"ownership ledger references survive checkpoint alongside earlier NPC ledgers")
	if "--recovery" in OS.get_cmdline_user_args():
		var ended: int=account.selected
		check(account.lineage.dormant.is_empty(),"Replacement fixture has no prepaid backup")
		withheld_acks[0]=true
		check(await until(func():return deferred_acks.has(0)),"Death fixture holds the browser snapshot acknowledgement")
		if host.cpu:host.pending_frame={"frames":{}}
		host.world._die(host._selected(account))
		check(await until(func():return messages[0].any(func(frame):return frame.get("kind","")=="death_events" and frame.get("deaths",[]).any(func(event):return event.id==ended and event.player))),"Rupture reaches a real socket while pose publication and acknowledgement are blocked")
		if host.cpu:host.pending_frame.clear()
		withheld_acks.erase(0)
		check(await until(func():return account.selected!=ended and not account.current.dead),"A disconnected-independent replacement reaches the retained live account")
		check(await until(func():return messages[0].any(func(frame):return frame.get("deaths",[]).any(func(event):return event.get("id",-1)==ended and event.player))),"Real WebSocket delivers the selected body's rupture after automatic succession")
		check(host.accounts.has(welcome0.token.sha256_text()) and account.sequence==1 and account.receipts.has(1) and account.root!=ended,"Replacement retains the session and paid receipt while switching lineage")
		camera_reports[0].perception="interoception"
		camera_reports[0].rect=[account.current.position.x,account.current.position.y,Sim.VIEW.x/.8/2,Sim.VIEW.y/.8/2]
		check(await until(func():
			for frame in messages[0]:
				if frame.get("kind","")=="snapshot" and not frame.get("warming",true):
					var data=preload("res://scripts/network/state_codec.gd").new().restore(frame.graph)
					if data.player.id==account.selected and not data.player.dead:return true
			return false),"The existing socket receives the new selected body without another sign-in")
		if not host.cpu:check(await until(func():return account.current.chemistry.accelerator!=null),"The replacement's viewed cytoplasm enters the existing resident GPU backend")
		check(host.checkpoint(),"The new lineage and retained authentication are committed together")
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
	if "--realtime" in OS.get_cmdline_user_args():
		host.world.profiling=true
		camera_reports[1].perception="interoception"
		check(await until(func():return not host.world.interoceptive_cells.is_empty()),"Mixed clients request exterior and resident interior detail together")
		# Finite authored stress input, not a food source in normal gameplay.
		for cell in host.world.cells:
			if cell.dead:continue
			for j in 12:cell.chemistry.emit("food",4,Vector2.from_angle(j*TAU/12)*cell.radius*.65)
		var wall_start:=Time.get_ticks_usec()
		var sim_start: float=host.world.time
		while Time.get_ticks_usec()-wall_start<12000000:
			poll();await process_frame
		var ratio: float=(host.world.time-sim_start)/((Time.get_ticks_usec()-wall_start)/1000000.0)
		var timings: Array=host.tick_samples.duplicate();timings.sort()
		var p95: float=timings[mini(timings.size()-1,int(timings.size()*.95))]
		check_performance(ratio>=.98 and ratio<=1.02,"Shared authority advances at real time with mixed wide cameras")
		check(Engine.physics_ticks_per_second==30 and host.physics_hz==30,"Dedicated authority uses the documented 30 Hz simulation cadence")
		check_performance(p95<=1000.0/host.physics_hz,"Authority p95 tick fits its documented simulation cadence")
		check(host.world.cells.all(func(cell):return cell.chemistry.particle_count()<=cell.chemistry.MAX_PACKETS),"Aged interiors stay bounded under sustained finite digestion")
		host._write_metrics()
		check(host.world.fluid.metrics().nonfinite==0 and host.world.cells.all(func(cell):return cell.velocity.is_finite() and is_finite(cell.angular_velocity)),"Mixed resident/coarse perception transitions retain finite water and body motion")
		var phase_report=JSON.parse_string(FileAccess.get_file_as_string(host.store.directory.path_join("health.json")))
		print("AUTHORITY_PHASES ",JSON.stringify(phase_report.get("tick_phase_mean_ms",{})))
		print("PUBLICATION_ENCODING ",JSON.stringify({"mean_ms":phase_report.get("snapshot_encode_ms_mean",0),"pending":phase_report.get("snapshots_encoding",0)}))
		print("REALTIME_AUTHORITY ",JSON.stringify({"simulation_hz":Engine.physics_ticks_per_second,"tick_budget_ms":1000.0/host.physics_hz,"simulation_wall_ratio":ratio,"tick_p95_ms":p95,"living_cells":host.world.cells.filter(func(cell):return not cell.dead).size(),"interior_packets":host.world.cells.reduce(func(total,cell):return total+cell.chemistry.particle_count(),0),"gpu":RenderingServer.get_video_adapter_name()}))
		if ratio<.98 or ratio>1.02 or p95>1000.0/host.physics_hz:await diagnostic_warm_window()
	for socket in sockets:socket.close(-1)
	check(await until(func():return host.world.camera_views.is_empty()),"disconnect removes every detailed camera")
	check(host._lineage_names().all(func(row):return not row.online),"Disconnected owners retain dim nameplates")

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
	print("PERFORMANCE_WARNINGS ",performance_warnings)
	print("NETWORK LIVE: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
func saved_directory() -> String:
	return ProjectSettings.globalize_path("res://build/network-live-"+str(OS.get_process_id()))

func diagnostic_warm_window() -> void:
	# Diagnostic only: never clears failures or changes the cold acceptance gate.
	var start:=Time.get_ticks_usec();var clock: float=host.world.time;var revision: int=host.world.revision
	while Time.get_ticks_usec()-start<12000000:poll();await process_frame
	var count: int=host.world.revision-revision
	var timings: Array=host.tick_samples.slice(maxi(0,host.tick_samples.size()-count));timings.sort()
	print("WARM_WINDOW_DIAGNOSTIC ",JSON.stringify({"wall":(Time.get_ticks_usec()-start)/1000000.0,"simulation_wall_ratio":(host.world.time-clock)/((Time.get_ticks_usec()-start)/1000000.0),"p95_ms":timings[mini(timings.size()-1,int(timings.size()*.95))] if not timings.is_empty() else -1,"living_cells":host.world.cells.filter(func(cell):return not cell.dead).size(),"active_cells":host.world.active_cells,"packets":host.world.particle_count(),"largest_radius":host.world.cells.map(func(cell):return cell.radius).max(),"most_organs":host.world.cells.map(func(cell):return cell.organs.size()).max()}))
