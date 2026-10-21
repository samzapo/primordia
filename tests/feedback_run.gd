extends SceneTree
const Host=preload("res://scripts/network/world_host.gd")
const Store=preload("res://scripts/network/feedback_store.gd")
const Sim=preload("res://scripts/simulation.gd")
class Client:
	extends "res://scripts/network/network_client.gd"
	func _load_identity() -> void:pass
	func _save_identity() -> void:pass
class SwitchClient:
	extends "res://scripts/network/network_client.gd"
	var identity_path: String
	func _identity_path() -> String:return identity_path
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func until(predicate: Callable) -> bool:
	var end:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await process_frame
	return false
func run() -> void:
	if "--logout-only" in OS.get_cmdline_user_args():
		await logout_session()
		print("LOGOUT: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
		return
	var directory: String=ProjectSettings.globalize_path("res://build/feedback-fixture-"+str(OS.get_process_id()))
	var store=Store.new();store.directory=directory.path_join("unit")
	var original={"id":"a".repeat(32),"category":"bug","title":"Keyboard café 🦠","description":"M, I and P should remain typed text."}
	var first: Dictionary=store.submit(original,"private-author",{"tick":7})
	check(first.ok and FileAccess.file_exists(store.directory.path_join(original.id+".json")),"Receipt follows durable creation of a private report")
	var bytes:=FileAccess.get_file_as_bytes(store.directory.path_join(original.id+".json"))
	check(store.submit(original,"private-author",{"tick":8}).ok and bytes==FileAccess.get_file_as_bytes(store.directory.path_join(original.id+".json")),"Retry returns the same receipt without rewriting the saved context")
	check(not store.submit(original,"another-author",{}).ok,"Another account cannot reuse a report ID")
	var changed: Dictionary=original.duplicate();changed.description="changed"
	check(not store.submit(changed,"private-author",{}).ok,"A conflicting retry cannot overwrite feedback")
	changed.id="../access-keys"
	check(not store.submit(changed,"private-author",{}).ok,"A report ID cannot escape its private inbox")
	changed=original.duplicate();changed.id="b".repeat(32);changed.description="x".repeat(6001)
	check(not store.submit(changed,"private-author",{}).ok,"Oversized reports are rejected")
	var recovered=Store.new();recovered.directory=store.directory
	check(recovered.submit(original,"private-author",{}).ok,"Duplicate detection survives store recreation and server restart")
	var old_invite:=OS.get_environment("PRIMORDIA_INVITE");OS.set_environment("PRIMORDIA_INVITE","feedback-authenticated-fixture")
	var host=Host.new();host.cpu=true;host.port=18000+OS.get_process_id()%20000;host.store.directory=directory.path_join("world")
	host.world=Sim.new(82,0,false);host.world.cells=[host.world.player];host.world.next_id=1;host.world.habitat_geometry=Sim.Habitat.new(82,host.world.cells)
	root.add_child(host)
	var rejected:=WebSocketPeer.new();rejected.connect_to_url("ws://127.0.0.1:"+str(host.port))
	check(await until(func():rejected.poll();return rejected.get_ready_state()==WebSocketPeer.STATE_OPEN),"Unauthenticated fixture reaches the real socket")
	rejected.send_text(JSON.stringify({"op":"feedback","id":"f".repeat(32),"category":"bug","title":"untrusted","description":"untrusted"}))
	check(await until(func():rejected.poll();return rejected.get_ready_state()==WebSocketPeer.STATE_CLOSED),"Feedback requires an authenticated player session")
	var client=Client.new();client.server_url="ws://127.0.0.1:"+str(host.port);client.invitation="feedback-authenticated-fixture"
	root.add_child(client);client.music.enabled=false;client.music.player.stop()
	check(await until(func():return client.connected and not client.loading_world and client.world.revision>0),"Real client signs in and receives a complete world")
	client._mobile_pause_menu()
	var entries: Array[Node]=client.settings_panel.find_children("*","Button",true,false)
	var entry=entries.filter(func(button):return button.text=="Feature request / Bug report")
	check(entry.size()==1,"Pause/settings contains the feedback action")
	if not entry.is_empty():entry[0].pressed.emit()
	check(client.user_paused and client.settings_panel.visible and client.feedback.opened,"Pause menu opens feedback while the personal view stays paused")
	client.feedback.title.text="Bug: mobile input"
	client.feedback.details.text="Typing M I P café 🦠; the report must retain this text."
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_M;client._input(key)
	check(client.feedback.opened and client.settings_panel.visible and client.user_paused,"Text-field shortcuts cannot close settings or resume the view")
	var before: float=host.world.time
	client.feedback._submit_native()
	check(await until(func():return not client.feedback.pending and client.feedback.status.text=="Report saved. Thank you!"),"Real authenticated WebSocket submission receives its durable server receipt")
	check(host.world.time>before and client.user_paused and client.feedback.details.text=="","Server keeps evolving while paused-client feedback is saved and confirmed")
	var folder:=DirAccess.open(host.feedback_store.directory);var names:=folder.get_files()
	check(names.size()==1,"One click creates exactly one report outside world checkpoint generations")
	var record=JSON.parse_string(FileAccess.get_file_as_string(host.feedback_store.directory.path_join(names[0])))
	check(record.content.category=="bug" and record.context.cell>=0 and record.context.tick>0 and record.content.description.contains("café 🦠"),"Saved bug has correct Unicode content and server-authored diagnostic facts")
	host.feedback_recent.clear()
	client.feedback.category.select(1);client.feedback.title.text="Feature: extra colours";client.feedback.details.text="Please add a colour choice."
	client.feedback._submit_native()
	check(await until(func():return not client.feedback.pending and client.feedback.status.text=="Report saved. Thank you!"),"The same paused-client flow accepts feature requests")
	check(DirAccess.open(host.feedback_store.directory).get_files().size()==2 and host.accounts.values()[0].sequence==0,"Feedback does not spend resources or alter the gameplay command sequence")
	client.feedback.open();client.feedback.details.text="Unsaved draft";client.feedback.close();client.feedback.open()
	check(client.feedback.details.text=="Unsaved draft" and client.feedback.title.editable,"Back/reopen retains an editable unfinished draft")
	client.feedback.report_id="d".repeat(32);client.feedback.content_hash="older-submitted-content"
	client.feedback.result({"id":"d".repeat(32),"ok":true,"message":"Report saved. Thank you!"})
	check(client.feedback.details.text=="Unsaved draft","A delayed receipt cannot erase text edited after a timeout")
	client.feedback.close();client._toggle_user_pause()
	check(not client.user_paused and not client.feedback.opened,"Closing feedback and Resume returns to normal observation")
	client.socket.close();client.retry_enabled=false;client.queue_free()
	host.running=false;host.listener.stop();host.queue_free();await process_frame
	OS.set_environment("PRIMORDIA_INVITE",old_invite)
	print("FEEDBACK: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)

func logout_session() -> void:
	var directory:=ProjectSettings.globalize_path("res://build/logout-fixture-"+str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(directory)
	check(preload("res://scripts/player_guide.gd").gameplay(true).contains("Log out") and preload("res://scripts/player_guide.gd").gameplay(false).contains("Log out"),"Both platform guides explain switching players")
	var first_key:="logout-first-player-fixture"
	var second_key:="logout-second-player-fixture"
	var registry:=directory.path_join("keys.json")
	var file:=FileAccess.open(registry,FileAccess.WRITE)
	file.store_string(JSON.stringify({"hashes":[first_key.sha256_text(),second_key.sha256_text()]}));file.close()
	var old_keys:=OS.get_environment("PRIMORDIA_ACCESS_KEYS_FILE")
	OS.set_environment("PRIMORDIA_ACCESS_KEYS_FILE",registry)
	var host=Host.new();host.cpu=true;host.port=18000+OS.get_process_id()%20000;host.store.directory=directory.path_join("world")
	host.world=Sim.new(82,0,false)
	host.world.cells=[host.world.player,Sim.Cell.new(1,host.world.player.position+Vector2(300,0))]
	host.world.next_id=2;host.world.habitat_geometry=Sim.Habitat.new(82,host.world.cells)
	for cell in host.world.cells:
		cell.automatic_division=false;cell.automatic_budding=false;cell.investment_retry_at=1e9
	root.add_child(host)
	var client=SwitchClient.new();client.identity_path=directory.path_join("browser.identity")
	client.server_url="ws://127.0.0.1:"+str(host.port);client.invitation=first_key
	root.add_child(client);client.music.enabled=false;client.music.player.stop()
	check(await until(func():return client.connected and not client.loading_world and client.world.revision>0),"First access key signs in to a real local authority")
	var first_token: String=client.token
	var first_cell: int=client.world.player.id
	check(not first_token.is_empty() and FileAccess.get_file_as_string(client.identity_path)==first_token,"Real identity storage remembers this player's login")
	client.update_popup.close();client.pending_release_updates.clear()
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(360,640)
	client._mobile_pause_menu();await process_frame;await process_frame
	check(client.logout_menu_button.text=="Log out" and client.logout_menu_button.is_visible_in_tree(),"Pause exposes Log out on a phone-size viewport")
	client.feedback.details.text="Private unfinished draft"
	client.commands.append({"op":"command","sequence":99})
	client.logout_menu_button.pressed.emit()
	check(not client.connected and not client.connecting and not client.retry_enabled and not client.attempted,"Logout disables automatic reconnection")
	check(client.token=="" and client.invitation=="" and client.invite_input.text=="" and FileAccess.get_file_as_string(client.identity_path)=="","Logout forgets the browser token and clears the access key field")
	check(client.login.visible and client.invite_input.visible and client.join_button.visible and not client.settings_panel.visible,"Logout returns directly to usable sign-in")
	check(client.commands.is_empty() and client.inflight.is_empty() and client.feedback.details.text=="" and client.world.cells.is_empty(),"Old commands, private draft and old world presentation cannot carry into the next player")
	check(await until(func():return host.peers.is_empty()),"Old authenticated socket disconnects")
	check(host.accounts.size()==1 and host.world.cells.any(func(cell):return cell.id==first_cell and not cell.dead),"Logout preserves the original account and its living cell")
	client.invite_input.text=second_key;client._connect()
	check(await until(func():return client.connected and not client.loading_world and client.world.revision>0),"Second access key signs in without reloading")
	check(client.token!=first_token and client.world.player.id!=first_cell and host.accounts.size()==2,"Switching reaches the other player's cell with both accounts retained")
	check(FileAccess.get_file_as_string(client.identity_path)==client.token and host.accounts.values().all(func(account):return account.sequence==0),"Only the new login is remembered and old queued commands are not replayed")
	root.size=Vector2i(1280,720);client.update_popup.close();client.pending_release_updates.clear()
	client._mobile_pause_menu();await process_frame
	check(client.logout_menu_button.is_visible_in_tree(),"Desktop Pause exposes the same Log out action")
	client.logout_menu_button.pressed.emit()
	check(await until(func():return host.peers.is_empty()),"Second logout also disconnects cleanly")
	client.invite_input.text=first_key;client._connect()
	check(await until(func():return client.connected and not client.loading_world and client.world.revision>0),"Original access key can sign back in")
	check(client.world.player.id==first_cell and host.accounts.size()==2,"Returning to the first player resumes the same cell without creating another account")
	client._logout();client.queue_free()
	host.running=false;host.listener.stop();host.queue_free();await process_frame
	OS.set_environment("PRIMORDIA_ACCESS_KEYS_FILE",old_keys)
