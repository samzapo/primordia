extends Control
const Guide=preload("res://scripts/player_guide.gd")
var game
var opened:=false
var page:=""
var panel:=PanelContainer.new()
var title:=Label.new()
var sections:=OptionButton.new()
var body:=RichTextLabel.new()
var back:=Button.new()
func initialize(owner_game) -> void:
	game=owner_game;game.ui.add_child(self);z_index=110
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if OS.has_feature("web"):JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/player_readers.js"),true)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.7);add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin:=MarginContainer.new();panel.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);margin.add_child(box)
	box.add_child(title);box.add_child(sections)
	sections.add_item("All mechanics")
	for section in Guide.data().mechanics:sections.add_item(section.title)
	sections.item_selected.connect(func(_index):_content())
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(scroll)
	body.bbcode_enabled=true;body.mouse_filter=Control.MOUSE_FILTER_PASS;body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.fit_content=true;body.scroll_active=false;body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.meta_clicked.connect(_source);scroll.add_child(body)
	back.text="Back to Pause";back.pressed.connect(close);box.add_child(back)
	get_viewport().size_changed.connect(_layout);hide();set_process(false)
func open(which: String) -> void:
	page=which;opened=true;title.text="Gameplay" if page=="gameplay" else "Mechanics"
	sections.visible=page=="mechanics";sections.select(0);game.touch_zoom.cancel()
	_content()
	if OS.has_feature("web"):
		var guide: Dictionary=Guide.data()
		var groups: Array=guide.mechanics if page=="mechanics" else [{"title":"Your controls","items":guide.gameplay.touch if game.touch_zoom.enabled else guide.gameplay.desktop},{"title":"Shape your cell","items":guide.gameplay.common}]
		JavaScriptBridge.eval("window.primordiaReaders.openHelp("+JSON.stringify({"title":title.text,"science":page=="mechanics","groups":groups})+")")
		hide();set_process(true)
	else:show();_layout();back.grab_focus()
func close() -> void:
	opened=false;hide();set_process(false)
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaReaders?.close('help')")
func _process(_dt: float) -> void:
	if not OS.has_feature("web") or not opened:return
	var action=JSON.parse_string(str(JavaScriptBridge.eval("window.primordiaReaders.take('help')")))
	if action is Dictionary and action.get("close",false):close()
func _content() -> void:
	body.text=Guide.gameplay(game.touch_zoom.enabled) if page=="gameplay" else Guide.mechanics(sections.selected-1)
	var scroll: ScrollContainer=body.get_parent();scroll.scroll_vertical=0
func _layout() -> void:
	if not opened or OS.has_feature("web"):return
	var available:=get_viewport_rect().size
	var density: float=game.touch_zoom.pixels if game.touch_zoom.enabled else 1.0
	var fonts:=Theme.new();fonts.default_font_size=roundi(18*game.preferences.hud_scale*density);theme=fonts
	title.add_theme_font_size_override("font_size",roundi(24*density))
	back.custom_minimum_size=Vector2(0,48*density);sections.custom_minimum_size=Vector2(0,44*density)
	panel.size=Vector2(minf(720*density,available.x-24*density),available.y-24*density);panel.position=(available-panel.size)*.5
func _source(url) -> void:
	if not Guide.allowed_url(url):return
	if OS.has_feature("web"):JavaScriptBridge.eval("window.open("+JSON.stringify(url)+",'_blank','noopener,noreferrer')")
	else:OS.shell_open(url)
