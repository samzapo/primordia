extends SceneTree
class Client:
 extends "res://scripts/network/network_client.gd"
 func _load_identity() -> void:pass
 func _save_identity() -> void:pass
 func _poll_network() -> void:pass
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(412,915)
 var game=Client.new();root.add_child(game);game.set_process(false);game.set_physics_process(false);game.music.enabled=false;game.music.player.stop()
 var cell=game.world.Cell.new(12,Vector2(900,900));cell.lineage=3
 var sibling=game.world.Cell.new(13,Vector2(1050,900));sibling.lineage=3
 var unowned=game.world.Cell.new(14,Vector2(900,1100));unowned.lineage=4
 game.world.cells=[cell,sibling,unowned];game.world.player=cell
 game.lineage_names=[{"root":3,"name":"Sam 🌱","online":true}]
 game.camera_initialized=true;game.camera_locked=true;game.camera_offset=Vector2.ZERO
 # This fixture replaces the unseen login scene, as the first ready snapshot does.
 game.camera_has_pose=false;game.camera_followed_id=-1;game.camera_motion.cancel()
 game._update_world(1)
 check(game.nameplates.items.size()==2 and game.nameplates.items.all(func(item):return item.name=="Sam 🌱" and item.online),"Every visible owned sibling carries the owner's highlighted name")
 check(game.nameplates.items.all(func(item):return item.bounds.end.y<game.camera_screen.y),"Nameplates sit above cells at constant readable size")
 if game.nameplates.items.is_empty():game.queue_free();quit(1);return
 var font_size: int=game.nameplates.items[0].font_size
 game.manual_zoom=2;game._update_world(1)
 check(game.nameplates.items[0].font_size==font_size,"Camera zoom changes cell size without shrinking the nameplate")
 game.render_rotation=.6;game.camera_rotation=1.2;game.nameplates.sync(1)
 var sibling_label: Dictionary=game.nameplates.items.filter(func(item):return item.cell==sibling.id)[0]
 check(absf(sibling_label.bounds.get_center().x-game._world_screen(sibling.position).x)<.01,"Nameplates follow the displayed camera during a rotation transition")
 game.render_rotation=0;game.camera_rotation=0
 game.lineage_names[0].online=false;game._update_world(1)
 check(game.nameplates.items.all(func(item):return not item.online),"Offline owners retain their name with dim styling")
 game.perception="interoception";game._update_world(1)
 check(game.nameplates.items.size()<=1 and game.nameplates.items.all(func(item):return item.cell==cell.id),"Other cells cannot overlay labels on the interoception view")
 game.player_name="Sam 🌱";game.profile.open()
 check(game.profile.opened and game.profile.name_input.text=="Sam 🌱","Pause profile opens with the saved name")
 game.profile.result({"ok":true,"name":"New name","message":"Name saved."})
 check(game.player_name=="New name","Durable profile receipt updates the client")
 game.profile.close();check(not game.profile.opened,"Back closes the profile")
 game.queue_free();await process_frame
 print("NAMEPLATES: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
