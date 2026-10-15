extends SceneTree
const Host=preload("res://scripts/network/world_host.gd")
const Store=preload("res://scripts/network/feedback_store.gd")
const Sim=preload("res://scripts/simulation.gd")
class Client:
	extends "res://scripts/network/network_client.gd"
	func _load_identity() -> void:pass
	func _save_identity() -> void:pass
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
