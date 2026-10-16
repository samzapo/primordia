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
	var account: Dictionary={}
	check(not Notes.pending(account).is_empty(),"Unseen update appears for existing and new players")
	check(not Notes.acknowledge(account,"unknown") and not account.has("seen_release"),"Unknown update cannot suppress the notice")
	check(Notes.acknowledge(account,Notes.CURRENT.id) and Notes.pending(account).is_empty(),"Dismissal suppresses only the current update")
	account.seen_release="previous-release"
	check(not Notes.pending(account).is_empty(),"A later public update appears again")
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
	check(clicked==[Notes.CURRENT.id] and popup.opened and popup.button.disabled,"A double tap sends one acknowledgement and waits for confirmation")
	popup.result({"id":"stale","ok":true});check(popup.opened,"Stale acknowledgement cannot dismiss a newer update")
	popup.result({"id":Notes.CURRENT.id,"ok":false})
	check(popup.opened and not popup.button.disabled,"A failed save keeps the notice retryable")
	popup.button.pressed.emit();popup.result({"id":Notes.CURRENT.id,"ok":true})
	check(not popup.opened and not popup.visible,"Successful dismissal returns to the live pond")
	parent.queue_free();await process_frame
	print("RELEASE NOTES: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
