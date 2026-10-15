extends Control
var game
var panel:=PanelContainer.new()
var category:=OptionButton.new()
var title:=LineEdit.new()
var details:=TextEdit.new()
var status:=Label.new()
var send_button:=Button.new()
var opened:=false
var pending:=false
var pending_seconds:=0.0
var report_id:=""
var content_hash:=""
func initialize(owner_game) -> void:
	game=owner_game;game.ui.add_child(self);z_index=100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.7);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	add_child(panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);panel.add_child(box)
	var heading:=Label.new();heading.text="Feedback";box.add_child(heading)
	category.add_item("Bug report");category.add_item("Feature request");box.add_child(category)
	title.placeholder_text="Short title";title.max_length=120;box.add_child(title)
	details.placeholder_text="What happened, or what would you like to add?";details.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;details.custom_minimum_size=Vector2(0,150);box.add_child(details)
	var note:=Label.new();note.text="Game version and simulation tick are included automatically.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(note)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
	send_button.text="Submit";send_button.pressed.connect(_submit_native);box.add_child(send_button)
	var close_button:=Button.new();close_button.text="Back";close_button.pressed.connect(close);box.add_child(close_button)
	get_viewport().size_changed.connect(_layout)
	if OS.has_feature("web"):JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/feedback.js"),true)
	hide();set_process(false)
func _layout() -> void:
	if not opened:return
	var size:=get_viewport_rect().size
	panel.size=Vector2(minf(520,size.x-32),0);panel.position=Vector2((size.x-panel.size.x)*.5,maxf(16,(size.y-panel.size.y)*.5))
func open() -> void:
	opened=true;pending=false;_display("",false,false)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.primordiaFeedback.open()")
	else:show();_layout();title.grab_focus()
	set_process(true)
func close() -> void:
	opened=false;hide();set_process(false)
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaFeedback.close()")
func _submit_native() -> void:
	submit({"category":"bug" if category.selected==0 else "feature","title":title.text,"description":details.text})
func submit(content: Dictionary) -> void:
	if pending:return
	content=content.duplicate()
	var browser_id: String=str(content.get("id",""));content.erase("id")
	var signature:=JSON.stringify(content).sha256_text()
	if browser_id!="":report_id=browser_id;content_hash=signature
	elif report_id=="" or signature!=content_hash:
		report_id=Crypto.new().generate_random_bytes(16).hex_encode();content_hash=signature
	var report: Dictionary=content.duplicate();report.id=report_id
	if str(report.title).strip_edges()=="" or str(report.description).strip_edges()=="":
		_display("Please enter a title and details.",false,false);return
	pending=true;pending_seconds=0;_display("Saving report…",true,false)
	var error: String=game._submit_feedback(report)
	if error!="":result({"id":report_id,"ok":false,"message":error})
func result(receipt: Dictionary) -> void:
	if receipt.get("id","")!=report_id:return
	pending=false
	var ok: bool=receipt.get("ok",false)
	_display(str(receipt.get("message","Cannot confirm submission. Please retry.")),false,ok)
	if ok:
		var current: Dictionary={"category":"bug" if category.selected==0 else "feature","title":title.text,"description":details.text}
		if JSON.stringify(current).sha256_text()==content_hash:title.clear();details.clear()
		report_id="";content_hash=""
func _display(text: String,busy: bool,saved: bool) -> void:
	status.text=text;send_button.disabled=busy
	title.editable=not busy;details.editable=not busy;category.disabled=busy
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaFeedback.result("+JSON.stringify({"message":text,"busy":busy,"saved":saved})+")")
func _process(dt: float) -> void:
	if OS.has_feature("web"):
		var action=JSON.parse_string(str(JavaScriptBridge.eval("window.primordiaFeedback.take()")))
		if action is Dictionary:
			if action.get("close",false):close()
			elif action.has("category"):submit(action)
	if pending:
		pending_seconds+=dt
		if pending_seconds>15:
			pending=false;_display("No confirmation yet. Retry to check the same report; your draft is kept.",false,false)
