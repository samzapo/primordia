extends SceneTree
const Guide=preload("res://scripts/player_guide.gd")
const Help=preload("res://scripts/player_help.gd")
class TouchStub extends RefCounted:
	var enabled:=false
	var pixels:=1.0
	func cancel() -> void:pass
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var touch: String=Guide.gameplay(true);var desktop: String=Guide.gameplay(false)
	check(touch.contains("Two") or touch.contains("two fingers"),"Touch guide explains combined camera gestures")
	for word in ["Right-click","Double-click","mouse","keyboard","F11","Enter","Alt","Space","M opens"]:
		check(not touch.contains(word),"Touch guide excludes desktop control "+word)
	check(desktop.contains("mouse wheel") and desktop.contains("Double-click") and desktop.contains("F11"),"Desktop guide retains the actual desktop interactions")
	var refs:=FileAccess.get_file_as_string("res://references.md")
	var urls: Dictionary={};var ids: Dictionary={}
	for group in Guide.data().mechanics:
		for item in group.items:
			check(not ids.has(item.id) and item.text.length()>10,"Mechanics entries are unique and explain their rule");ids[item.id]=true
			for source in item.sources:
				check(Guide.allowed_url(source.url) and refs.contains(source.url),"Every clickable science source comes from the retained bibliography");urls[source.url]=true
	check(urls.size()>=20 and ids.has("respiration") and ids.has("pore_assembly") and ids.has("acid_buffer") and ids.has("nutrient_binding"),"Guide covers the active food and external reaction systems")
	for kind in preload("res://scripts/simulation.gd").KINDS:
		check(ids.has("organ_"+kind),"Every available organelle has a current mechanics entry")
	for url in ["javascript:alert(1)","file:///etc/passwd","https://example.com/","https://github.com/Eka-Robotics/eka-robotics"]:
		check(not Guide.allowed_url(url),"Only authored scientific links can open")
	var ui:=Control.new();root.add_child(ui);ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fake: Dictionary={"ui":ui,"preferences":{"hud_scale":1.0},"touch_zoom":TouchStub.new()}
	var help=Help.new();help.initialize(fake)
	for mobile in [true,false]:
		fake.touch_zoom.enabled=mobile
		root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(360,640) if mobile else Vector2i(1280,720)
		help.open("gameplay");await process_frame;await process_frame
		var area: Rect2=help.panel.get_global_rect()
		check(help.body.text==Guide.gameplay(mobile) and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(area),"Help selects only the active platform and fits the view")
		help.open("mechanics");await process_frame;await process_frame
		check(help.sections.visible and help.body.text.contains("Food & energy"),"Mechanics opens with readable groups")
		help.sections.select(1);help.sections.item_selected.emit(1)
		check(help.body.text.contains("Food → ATP") and not help.body.text.contains("Tag + membrane"),"Category selection narrows the list without changing its rules")
		help.back.pressed.emit();check(not help.opened,"Back returns to Pause")
	ui.queue_free();await process_frame
	print("PLAYER HELP: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
