extends Control
var game
var opened:=false
var pending:=false
var elapsed:=0.0
var diagnostic_at:=0.0
var panel:=PanelContainer.new()
var wheel:=preload("res://scripts/lineage_color_wheel.gd").new()
var preview:=ColorRect.new()
var caption:=Label.new()
var status:=Label.new()
var save:=Button.new()
var scroll:=ScrollContainer.new()
var title:=Label.new()
var note:=Label.new()
var close_button:=Button.new()
func initialize(owner_game) -> void:
 game=owner_game;game.ui.add_child(self);z_index=100
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var shade:=ColorRect.new();shade.color=Color(0,0,0,.75);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
 add_child(panel);var outer:=VBoxContainer.new();outer.add_theme_constant_override("separation",8);panel.add_child(outer)
 scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;outer.add_child(scroll)
 var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",10);scroll.add_child(box)
 title.text="Lineage color";box.add_child(title)
 note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.text="Outer ring: hue\nInner disc: saturation ↔ and brightness ↕";box.add_child(note)
 box.add_child(wheel);wheel.changed.connect(_preview)
 preview.custom_minimum_size=Vector2(0,24);box.add_child(preview);box.add_child(caption)
 status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
 save.text="Save color";save.pressed.connect(submit);outer.add_child(save)
 close_button.text="Back";close_button.pressed.connect(close);outer.add_child(close_button)
 get_viewport().size_changed.connect(_layout);hide();set_process(false)
func _layout() -> void:
 var size:=get_viewport_rect().size
 var s: float=game.preferences.hud_scale*game.controls.pixels
 var width:=minf(350*s,size.x-24*s)
 var theme:=Theme.new();theme.default_font=preload("res://assets/fonts/ComicNeue-Regular.ttf");theme.default_font_size=roundi(18*s);panel.theme=theme
 title.add_theme_font_size_override("font_size",roundi(22*s))
 for label in [note,status]:label.add_theme_font_size_override("font_size",roundi(14*s))
 preview.custom_minimum_size.y=24*s
 for button in [save,close_button]:button.custom_minimum_size.y=40*s
 wheel.custom_minimum_size=Vector2.ONE*minf(width-24*s,maxf(90*s,size.y-270*s))
 scroll.custom_minimum_size=Vector2(width-16*s,maxf(90*s,minf(size.y-140*s,wheel.custom_minimum_size.y+130*s)))
 panel.size=Vector2(width,0);panel.reset_size()
 panel.position=Vector2((size.x-panel.size.x)*.5,maxf(8*s,(size.y-panel.size.y)*.5))

func _preview(color: Color) -> void:preview.color=color;caption.text="#"+color.to_html(false).to_upper()
func open() -> void:
 # Canvas z order does not change GUI picking order. Raise the modal in its tree.
 get_parent().move_child(self,get_parent().get_child_count()-1)
 opened=true;pending=false;status.text="";save.disabled=false
 var saved: String=game.lineage_color(game.world.player.lineage_id())
 var color: Color=Color(saved) if saved!="" else preload("res://scripts/cell_art.gd").make(game.world.seed_value,game.world.player.lineage_id()).colors[1]
 wheel.set_color(color);_preview(color);show();_layout();set_process(true)
func close() -> void:
 opened=false;hide();set_process(false)
 if OS.has_feature("web"):JavaScriptBridge.eval("if(window.primordiaPalette)window.primordiaPalette.opened=false")
func submit() -> void:
 if pending:return
 pending=true;elapsed=0;save.disabled=true;status.text="Saving color…"
 var error: String=game._submit_lineage_color("#"+wheel.color().to_html(false))
 if error!="":result({"ok":false,"message":error})
func result(receipt: Dictionary) -> void:
 pending=false;save.disabled=false
 status.text=receipt.get("message","Could not save your color. Try again.")
 if receipt.get("ok",false):
  game.player_color=receipt.color
  for row in game.lineage_names:
   if row.root==game.world.player.lineage_id():row.color=receipt.color
func _process(dt: float) -> void:
 if OS.has_feature("web"):
  diagnostic_at-=dt
  if diagnostic_at<=0:
   diagnostic_at=.25
   var conversion:=Vector2(float(JavaScriptBridge.eval("innerWidth")),float(JavaScriptBridge.eval("innerHeight")))/get_viewport_rect().size
   var bounds: Dictionary={}
   for pair in [["panel",panel],["wheel",wheel],["save",save],["back",close_button]]:
    var rect: Rect2=pair[1].get_global_rect()
    bounds[pair[0]]=[rect.position.x*conversion.x,rect.position.y*conversion.y,rect.size.x*conversion.x,rect.size.y*conversion.y]
   JavaScriptBridge.eval("window.primordiaPalette="+JSON.stringify({"opened":opened,"pending":pending,"status":status.text,"color":"#"+wheel.color().to_html(false),"bounds":bounds}))
 if pending:
  elapsed+=dt
  if elapsed>15:result({"ok":false,"message":"No confirmation yet. Your color is kept; retry when connected."})
