extends SceneTree
const Notes=preload("res://scripts/network/release_notes.gd")
const NoticePopup=preload("res://scripts/update_popup.gd")
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var stable_current: Dictionary=Notes.pending_all({},"stable")[-1]
	var account: Dictionary={}
	check(not Notes.pending(account).is_empty(),"Unseen update appears for existing and new players")
	check(not Notes.acknowledge(account,"unknown") and not account.has("seen_release"),"Unknown update cannot suppress the notice")
	check(not Notes.acknowledge(account,stable_current.id),"An update cannot be acknowledged out of order")
	var missed:=Notes.pending_all(account)
	check(missed.size()>=2 and missed[0].id==Notes.RELEASES[0].id and missed[-1].id==stable_current.id,"Missed updates are retained from oldest to newest")
	for update in missed:
		check(Notes.pending(account).id==update.id and Notes.acknowledge(account,update.id),"Clearing an update exposes the next oldest")
	check(Notes.pending_all(account).is_empty(),"All cleared updates stay cleared")
	check(Notes.acknowledge(account,missed[0].id) and account.seen_release==stable_current.id,"A duplicate old acknowledgement cannot move progress backwards")
	account.seen_release=Notes.RELEASES[0].id
	check(Notes.pending_all(account).size()==Notes.pending_all({}).size()-1,"Existing seen-release accounts migrate without replaying cleared updates")
	for update in Notes.RELEASES:
		check(update.get("audience","") in ["shared","stable","experimental"],"Every release declares its pond audience")
	var stable_ids:=Notes.pending_all({},"stable").map(func(update):return update.id)
	var experimental_ids:=Notes.pending_all({},"experimental").map(func(update):return update.id)
	check(Notes.CURRENT.id not in stable_ids and Notes.CURRENT.id in experimental_ids,"Consolidated experimental update never enters main")
	for release in Notes.RELEASES:
		if release.audience=="experimental":check(release.id not in stable_ids,"Experimental copy stays outside main")
		if release.audience=="stable":check(release.id not in experimental_ids,"Main copy stays outside experimental")
	check(experimental_ids.filter(func(id):return id==Notes.CURRENT.id).size()==1,"New experimental notice appears once")
	var consolidated:=0
	for i in Notes.RELEASES.size():
		if Notes.RELEASES[i].get("supersedes_experimental",false):consolidated=i
	var expected:=Notes.RELEASES.slice(consolidated).filter(func(update):return update.audience=="experimental").map(func(update):return update.id)
	check(Notes.pending_all({},"experimental").filter(func(update):return update.audience=="experimental").map(func(update):return update.id)==expected,"Consolidation replaces earlier notices while later updates remain in order")
	check(Notes.pending_all({},"experimental").size()==1 and Notes.pending({},"experimental").id==Notes.CURRENT.id,"Experimental starts with one roundup, including missed shared updates")
	for seen in [Notes.RELEASES[0].id,"2026-10-19-experimental-cell-lifecycle","2026-10-21-smoother-swimming-and-surplus-release"]:
		var existing: Dictionary={"seen_release":seen}
		check(Notes.pending_all(existing,"experimental").size()==1 and Notes.pending(existing,"experimental").id==Notes.CURRENT.id,"Existing acknowledgement reaches the same single roundup")
		check(Notes.acknowledge(existing,Notes.CURRENT.id,"experimental") and Notes.pending_all(existing,"experimental").is_empty(),"Clearing the roundup clears its covered experimental history")
	check(not Notes.acknowledge({},"unknown","experimental"),"Unrecognized notice cannot skip the queue")
	for instance in ["stable","experimental"]:
		var migrated: Dictionary={}
		for update in Notes.pending_all(migrated,instance):
			check(Notes.acknowledge(migrated,update.id,instance),"Each pond clears every applicable notice oldest first")
		check(Notes.pending_all(migrated,instance).is_empty(),"Hidden notices cannot leave either pond queue stuck")
	var parent:=Control.new();root.add_child(parent);parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var popup=NoticePopup.new();popup.initialize(parent)
	var clicked: Array=[];popup.dismissed.connect(func(id):clicked.append(id))
	for size in [Vector2i(360,640),Vector2i(640,360),Vector2i(1280,720)]:
		root.content_scale_size=Vector2i.ZERO;root.size=size;popup.open(Notes.CURRENT)
		await process_frame;await process_frame
		popup._layout();await process_frame
		var area: Rect2=popup.panel.get_global_rect();var hit: Rect2=popup.button.get_global_rect()
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(area) and area.encloses(hit) and hit.size.y>=48,"Update and dismissal fit portrait, landscape and desktop screens")
		check(popup.body.text.contains(Notes.CURRENT.items[0]) and popup.footer.text==Notes.CURRENT.footer,"Approved player copy is shown without build identifiers")
	popup.button.pressed.emit();popup.button.pressed.emit()
	check(clicked==[Notes.CURRENT.id] and not popup.opened and not popup.visible and popup.pending,"Closing immediately returns to the pond before acknowledgement, once per click")
	popup.result({"id":"stale","ok":true});check(popup.pending,"Stale acknowledgement cannot clear a newer update")
	popup.result({"id":Notes.CURRENT.id,"ok":false})
	check(not popup.opened and popup.pending,"A failed save cannot block the screen")
	popup._process(3.1);popup._process(3.1);popup._process(3.1)
	check(clicked.size()==3 and not popup.pending and not popup.opened,"Retries are bounded and leave the game accessible")
	popup.open(Notes.CURRENT);popup.close_button.pressed.emit()
	check(not popup.opened,"The fixed close button also leaves immediately")
	popup.result({"id":Notes.CURRENT.id,"ok":true})
	check(not popup.pending,"Successful acknowledgement is retained without reopening the reader")
	parent.queue_free();await process_frame
	print("RELEASE NOTES: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
