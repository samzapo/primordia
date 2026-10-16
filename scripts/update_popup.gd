extends Control
## A modal notice over the live world; dismissal is retained on the player account.
signal dismissed(id: String)
signal unconfirmed(id: String)
var opened:=false
var release_id:=""
var panel:=PanelContainer.new()
var box:=VBoxContainer.new()
var heading:=Label.new()
var body:=Label.new()
var footer:=Label.new()
var status:=Label.new()
var button:=Button.new()
var pending:=false
var elapsed:=0.0
var density:=1.0
var attempts:=0
var close_button:=Button.new()
func initialize(parent: Control) -> void:
	parent.add_child(self);z_index=120
	if OS.has_feature("web"):JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/player_readers.js"),true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.68);add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin:=MarginContainer.new();panel.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,20)
	margin.add_child(box)
	var header:=HBoxContainer.new();box.add_child(header)
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
	close_button.text="×";close_button.pressed.connect(_dismiss);header.add_child(close_button)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(scroll)
	body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
	footer.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(footer)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
	button.pressed.connect(_dismiss);box.add_child(button)
	get_viewport().size_changed.connect(_layout)
	close()
func open(notes: Dictionary) -> void:
	if notes.is_empty():return
	release_id=str(notes.id);heading.text=str(notes.title)
	var lines:=PackedStringArray()
	for item in notes.items:lines.append("• "+str(item))
	body.text="\n\n".join(lines);footer.text=str(notes.footer);button.text=str(notes.button)
	status.text="";status.hide();pending=false;button.disabled=false
	opened=true;attempts=0;set_process(true)
	if OS.has_feature("web"):
		hide();JavaScriptBridge.eval("window.primordiaReaders.openUpdate("+JSON.stringify(notes)+")")
	else:show();_layout();button.grab_focus()
func close() -> void:
	opened=false;pending=false;hide();set_process(false)
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaReaders?.close('update')")
func _layout() -> void:
	if not opened or OS.has_feature("web"):return
	var available:=get_viewport_rect().size
	density=available.x/maxf(1,float(JavaScriptBridge.eval("window.innerWidth"))) if OS.has_feature("web") else 1.0
	var theme_copy:=Theme.new();theme_copy.default_font_size=roundi(18*density);theme=theme_copy
	heading.add_theme_font_size_override("font_size",roundi(23*density))
	box.add_theme_constant_override("separation",roundi(14*density))
	button.custom_minimum_size=Vector2(0,48*density)
	close_button.custom_minimum_size=Vector2(48,48)*density
	panel.size=Vector2(minf(520*density,available.x-32*density),minf(540*density,available.y-32*density))
	panel.position=(available-panel.size)*.5
func _dismiss() -> void:
	if not opened:return
	opened=false;hide()
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaReaders.close('update')")
	pending=true;elapsed=0;attempts=1;set_process(true);dismissed.emit(release_id)
func result(message: Dictionary) -> void:
	if message.get("id","")!=release_id:return
	if message.get("ok",false):pending=false;set_process(opened)
	# Failed saves retry in the background; they never trap the player.
func _process(dt: float) -> void:
	if OS.has_feature("web") and opened:
		var action=JSON.parse_string(str(JavaScriptBridge.eval("window.primordiaReaders.take('update')")))
		if action is Dictionary and action.get("close",false) and action.get("id","")==release_id:_dismiss()
	if not pending:return
	elapsed+=dt
	if elapsed<3:return
	if attempts>=3:pending=false;set_process(opened);unconfirmed.emit(release_id);return
	elapsed=0;attempts+=1;dismissed.emit(release_id)
