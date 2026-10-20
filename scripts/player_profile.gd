extends Control
var game
var panel:=PanelContainer.new()
var name_input:=LineEdit.new()
var favorite_input:=LineEdit.new()
var status:=Label.new()
var save_button:=Button.new()
var opened:=false
var pending:=false
var elapsed:=0.0
func initialize(owner_game) -> void:
	game=owner_game;game.ui.add_child(self);z_index=100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.7);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	add_child(panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);panel.add_child(box)
	var title:=Label.new();title.text="Family and favorite cell";box.add_child(title)
	name_input.placeholder_text="Family name";name_input.max_length=24;box.add_child(name_input)
	favorite_input.placeholder_text="Favorite cell first name (optional)";favorite_input.max_length=24;box.add_child(favorite_input)
	var note:=Label.new();note.text="Shown above cells in your lineage.";box.add_child(note)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
	save_button.text="Save name";save_button.pressed.connect(func():submit(name_input.text,favorite_input.text));box.add_child(save_button)
	var back:=Button.new();back.text="Back";back.pressed.connect(close);box.add_child(back)
	get_viewport().size_changed.connect(_layout)
	if OS.has_feature("web"):JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/profile.js"),true)
	hide();set_process(false)
func _layout() -> void:
	var size:=get_viewport_rect().size
	panel.size=Vector2(minf(520,size.x-32),0);panel.position=Vector2((size.x-panel.size.x)*.5,maxf(16,(size.y-panel.size.y)*.5))
func open() -> void:
	opened=true;pending=false;name_input.text=game.player_name;favorite_input.text=game.favorite_name;_display("",false)
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaProfile.open("+JSON.stringify(game.player_name)+","+JSON.stringify(game.favorite_name)+")")
	else:show();_layout();name_input.grab_focus()
	set_process(true)
func close() -> void:
	opened=false;hide();set_process(false)
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaProfile.close()")
func submit(value: String,favorite: String="") -> void:
	if pending:return
	pending=true;elapsed=0;_display("Saving name…",true)
	var error: String=game._submit_profile(value,favorite)
	if error!="":result({"ok":false,"message":error})
func result(receipt: Dictionary) -> void:
	pending=false
	if receipt.get("ok",false):
		game.player_name=receipt.name;name_input.text=receipt.name
		game.favorite_name=str(receipt.get("favorite_name",game.favorite_name));favorite_input.text=game.favorite_name
	_display(str(receipt.get("message","Could not save the name. Your text is kept.")),false)
func _display(message: String,busy: bool) -> void:
	status.text=message;save_button.disabled=busy;name_input.editable=not busy
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaProfile.result("+JSON.stringify({"message":message,"busy":busy})+")")
func _process(dt: float) -> void:
	if OS.has_feature("web"):
		var action=JSON.parse_string(str(JavaScriptBridge.eval("window.primordiaProfile.take()")))
		if action is Dictionary:
			if action.get("close",false):close()
			elif action.get("name") is String:submit(action.name,str(action.get("favorite_name","")))
	if pending:
		elapsed+=dt
		if elapsed>15:pending=false;_display("No confirmation yet. Your text is kept; please retry.",false)
