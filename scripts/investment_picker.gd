extends PanelContainer
## Direct strategy selection, shared by desktop and touch; the pond stays live.
const SELECTION_MARK=preload("res://assets/ui/selection-mark.svg")
const Choice=preload("res://scripts/investment_choice.gd")
var game
var scope:="lineage"
var box:=VBoxContainer.new()
var title:=Label.new()
var note:=Label.new()
var status:=Label.new()
var family:=Button.new()
var body:=Button.new()
var manual:=Button.new()
var inherit:=Button.new()
var back:=Button.new()
var cards: Array[Button]=[]
var margin:=MarginContainer.new()
var layout_scale:=-1.0
var layout_viewport:=Vector2(-1,-1)
func initialize(owner_game) -> void:
 game=owner_game;z_index=95;add_child(margin);margin.add_child(box)
 title.text="Investment";box.add_child(title)
 var scopes:=HBoxContainer.new();box.add_child(scopes)
 for button in [family,body]:scopes.add_child(button);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 for button in [family,body,manual,inherit]:
  button.expand_icon=true;button.icon_alignment=HORIZONTAL_ALIGNMENT_RIGHT
 family.text="Family";body.text="This cell"
 family.pressed.connect(_scope.bind("lineage"));body.pressed.connect(_scope.bind("cell"))
 var row:=HBoxContainer.new();box.add_child(row)
 for kind in ["hunter","producer","grazer"]:
  var card=Choice.new();card.strategy=kind;card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  row.add_child(card);cards.append(card);card.pressed.connect(choose.bind(kind))
 var controls:=HBoxContainer.new();box.add_child(controls)
 for button in [manual,inherit,back]:controls.add_child(button);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 manual.pressed.connect(choose.bind("manual"));inherit.pressed.connect(choose.bind("inherit"))
 back.text="Back";back.pressed.connect(func():game.cell_ui.open_context({"kind":"nucleus"}))
 status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
 note.text="Only unattended cells spend AP. Selected cells stay manual."
 note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(note)
 hide()
func open() -> void:
 scope="lineage";get_parent().move_child(self,get_parent().get_child_count()-1);show();sync()
func _scope(value: String) -> void:scope=value;sync()
func current() -> String:
 var cell=game.world.player
 return game.world.investment.lineages.get(cell.lineage_id(),"manual") if scope=="lineage" else game.world.investment.cells.get(cell.id,"inherit")
func choose(kind: String) -> void:
 if kind=="inherit" and scope!="cell":return
 if game.world.edit("investment",{"scope":scope,"kind":kind}):
  game._message(("Family" if scope=="lineage" else "This cell")+" investment: "+kind.capitalize()+".")
 sync()
func sync() -> void:
 var viewport: Vector2=game.get_viewport_rect().size
 # Keep the three choices together even with large UI text on a short phone.
 var s: float=minf(game.cell_ui.ui_scale(),minf(viewport.x/330.0,viewport.y/350.0))
 var width:=minf(540*s,viewport.x-16*s)
 family.text="Family";body.text="This cell"
 family.icon=SELECTION_MARK if scope=="lineage" else null
 body.icon=SELECTION_MARK if scope=="cell" else null
 var value:=current()
 for card in cards:
  if card.active!=(card.strategy==value):
   card.active=card.strategy==value;card.queue_redraw()
 manual.text="Manual";manual.icon=SELECTION_MARK if value=="manual" else null
 inherit.visible=scope=="cell";inherit.text="Inherit"
 inherit.icon=SELECTION_MARK if value=="inherit" else null
 var inherited: String=game.world.investment.lineages.get(game.world.player.lineage_id(),"manual")
 status.text=("Family: "+value.capitalize()) if scope=="lineage" else ("This cell: "+value.capitalize()+(" ("+inherited.capitalize()+")" if value=="inherit" else ""))
 if layout_scale!=s or layout_viewport!=viewport:
  layout_scale=s;layout_viewport=viewport
  var style:=StyleBoxFlat.new();style.bg_color=Color("162b49");style.border_color=Color("69a9ab");style.set_border_width_all(roundi(s));style.set_corner_radius_all(roundi(8*s))
  for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,0)
  add_theme_stylebox_override("panel",style)
  var theme:=Theme.new();theme.default_font=preload("res://assets/fonts/ComicNeue-Regular.ttf");theme.default_font_size=roundi(16*s);self.theme=theme
  for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,roundi(8*s))
  box.add_theme_constant_override("separation",roundi(6*s))
  for card in cards:
   card.text_scale=s;card.custom_minimum_size=Vector2(88,126)*s;card.queue_redraw()
  for button in [family,body,manual,inherit,back]:
   button.custom_minimum_size.y=30*s
   button.add_theme_constant_override("icon_max_width",roundi(16*s))
  for label in [note,status]:label.add_theme_font_size_override("font_size",roundi(13*s));label.custom_minimum_size.x=width-20*s
  title.add_theme_font_size_override("font_size",roundi(18*s))
 size=Vector2(width,0);reset_size()
 position=Vector2((viewport.x-size.x)*.5,8*s if game.cell_ui.mobile() else maxf(8*s,(viewport.y-size.y)*.5))

func diagnostics(conversion: Vector2) -> Dictionary:
 var bounds:=func(node: Control) -> Array:
  var rect:=node.get_global_rect();return [rect.position.x*conversion.x,rect.position.y*conversion.y,rect.size.x*conversion.x,rect.size.y*conversion.y]
 return {"visible":is_visible_in_tree(),"scope":scope,"current":current(),"bounds":bounds.call(self),
 "family":bounds.call(family),"cell":bounds.call(body),"manual":bounds.call(manual),"inherit":bounds.call(inherit),
 "cards":cards.map(func(card):return {"kind":card.strategy,"active":card.active,"bounds":bounds.call(card)})}
