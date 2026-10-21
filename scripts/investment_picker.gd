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
var adopt:=Button.new()
var exemplar:=Button.new()
var auto_mitosis:=Button.new()
var auto_bud:=Button.new()
var pending_auto: Dictionary={}
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
 var row:=GridContainer.new();row.columns=2;box.add_child(row)
 for kind in ["hunter","producer","grazer","parasite","balanced"]:
  var card=Choice.new();card.strategy=kind;card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  if kind=="balanced":box.add_child(card)
  else:row.add_child(card)
  cards.append(card);card.pressed.connect(choose.bind(kind))
 var controls:=HBoxContainer.new();box.add_child(controls)
 for button in [manual,inherit,back]:controls.add_child(button);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 manual.pressed.connect(choose.bind("manual"));inherit.pressed.connect(choose.bind("inherit"))
 box.add_child(adopt);adopt.text="Use family for all relatives"
 adopt.pressed.connect(func():
  game.world.edit("investment",{"scope":"family_adopt","kind":"inherit"})
  game._message("Family settings requested." if game.world.remote_client else "All relatives now use the family strategy.")
  sync())
 back.text="Back";back.pressed.connect(func():game.cell_ui.open_context({"kind":"nucleus"}))
 status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
 note.text="Balanced by default. Unattended: one action/min; save for reproduction."
 note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(note)
 box.add_child(exemplar);exemplar.text="Copy a relative’s build"
 exemplar.pressed.connect(func():
  hide();game.cell_ui.open_context({"kind":"lineage","choose_template":true,"template_scope":scope}))
 var auto_row:=HBoxContainer.new();box.add_child(auto_row)
 for entry in [{"button":auto_mitosis,"mode":"mitosis"},{"button":auto_bud,"mode":"budding"}]:
  var button: Button=entry.button;var mode: String=entry.mode
  auto_row.add_child(button);button.expand_icon=true;button.icon_alignment=HORIZONTAL_ALIGNMENT_RIGHT;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  button.pressed.connect(_set_auto.bind(mode,button))

 hide()
func _auto_active(mode: String) -> bool:
 return game.world.player.automatic_division if mode=="mitosis" else game.world.player.automatic_budding

func _set_auto(mode: String,_button: Button) -> void:
 if pending_auto.has(mode):return
 if game.world.remote_client and (not game.connected or game.user_paused):return
 var desired:=not _auto_active(mode)
 if game.world.edit("division_policy",{"mode":mode,"scope":scope,"automatic":desired}) and game.world.remote_client:
  pending_auto[mode]={"cell":game.world.player.id,"scope":scope,"value":desired,"at":Time.get_ticks_msec()}
 sync()

func command_result(command: Dictionary,result: Dictionary) -> void:
 if command.get("action","")!="division_policy":return
 var mode: String=command.get("args",{}).get("mode","mitosis")
 if not result.get("ok",false):pending_auto.erase(mode)
 sync()

func open() -> void:
 scope="lineage";get_parent().move_child(self,get_parent().get_child_count()-1);show();sync()
func _scope(value: String) -> void:scope=value;sync()
func current() -> String:
 var cell=game.world.player
 return game.world.investment.lineages.get(cell.lineage_id(),game.world.Investment.DEFAULT) if scope=="lineage" else game.world.investment.cells.get(cell.id,"inherit")
func choose(kind: String) -> void:
 if kind=="inherit" and scope!="cell":return
 if game.world.edit("investment",{"scope":scope,"kind":kind}):
  game._message(("Family" if scope=="lineage" else "This cell")+" investment: "+kind.capitalize()+".")
 sync()
func sync() -> void:
 var viewport: Vector2=game.get_viewport_rect().size
 # Keep every illustrated path visible on a short phone.
 var s: float=minf(game.cell_ui.ui_scale(),minf(viewport.x/330.0,viewport.y/740.0))
 var width:=minf(540*s,viewport.x-16*s)
 family.text="Family";body.text="This cell"
 family.icon=SELECTION_MARK if scope=="lineage" else null
 body.icon=SELECTION_MARK if scope=="cell" else null
 for entry in [{"button":auto_mitosis,"mode":"mitosis","label":"Auto mitosis"},{"button":auto_bud,"mode":"budding","label":"Auto budding"}]:
  var mode: String=entry.mode;var button: Button=entry.button
  var active:=_auto_active(mode)
  if pending_auto.has(mode):
   var request: Dictionary=pending_auto[mode]
   if request.cell!=game.world.player.id or active==request.value or Time.get_ticks_msec()-request.at>15000:pending_auto.erase(mode)
  var waiting: bool=pending_auto.has(mode)
  button.text=entry.label+": "+("On" if active else "Off")+(" …" if waiting else "")
  button.icon=SELECTION_MARK if active else null
  button.disabled=waiting
  # A check records the mode; only an actual press uses the lit style.
  button.add_theme_stylebox_override("hover",button.get_theme_stylebox("normal"))
  button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
 var value:=current()
 var inherited: String=game.world.investment.lineages.get(game.world.player.lineage_id(),game.world.Investment.DEFAULT)
 var effective: String=inherited if value=="inherit" else value
 for card in cards:
  if card.active!=(card.strategy==effective):
   card.active=card.strategy==effective;card.queue_redraw()
 manual.text="Manual";manual.icon=SELECTION_MARK if value=="manual" else null
 inherit.visible=scope=="cell";inherit.text="Use family: "+inherited.capitalize()
 adopt.visible=scope=="lineage"
 inherit.icon=SELECTION_MARK if value=="inherit" else null
 var settings: Dictionary=game.world.investment.cells
 var overrides:=0;var relatives:=0
 for record in game.world.lineage.records:
  if record.state not in ["living","active"]:continue
  relatives+=1
  if settings.has(record.id):overrides+=1
 status.text=("Family: %s · %d use Family · %d individual" % [value.capitalize(),relatives-overrides,overrides]) if scope=="lineage" else ("This cell: "+effective.capitalize()+(" · using Family" if value=="inherit" else " · individual setting"))
 if layout_scale!=s or layout_viewport!=viewport:
  layout_scale=s;layout_viewport=viewport
  var style:=StyleBoxFlat.new();style.bg_color=Color("162b49");style.border_color=Color("69a9ab");style.set_border_width_all(roundi(s));style.set_corner_radius_all(roundi(8*s))
  for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,0)
  add_theme_stylebox_override("panel",style)
  var theme:=Theme.new();theme.default_font=preload("res://assets/fonts/ComicNeue-Regular.ttf");theme.default_font_size=roundi(16*s);self.theme=theme
  for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,roundi(8*s))
  box.add_theme_constant_override("separation",roundi(6*s))
  for card in cards:
   card.text_scale=s;card.custom_minimum_size=Vector2(88,100 if card.strategy=="balanced" else 126)*s;card.queue_redraw()
  for button in [family,body,manual,inherit,back,adopt,exemplar,auto_mitosis,auto_bud]:
   button.custom_minimum_size.y=30*s
   button.add_theme_constant_override("icon_max_width",roundi(16*s))
  for label in [note,status]:label.add_theme_font_size_override("font_size",roundi(13*s));label.custom_minimum_size.x=width-20*s
  title.add_theme_font_size_override("font_size",roundi(18*s))
 size=Vector2(width,0);reset_size()
 position=Vector2((viewport.x-size.x)*.5,8*s)

func diagnostics(conversion: Vector2) -> Dictionary:
 var bounds:=func(node: Control) -> Array:
  var rect:=node.get_global_rect();return [rect.position.x*conversion.x,rect.position.y*conversion.y,rect.size.x*conversion.x,rect.size.y*conversion.y]
 return {"visible":is_visible_in_tree(),"scope":scope,"current":current(),"bounds":bounds.call(self),
 "family":bounds.call(family),"cell":bounds.call(body),"manual":bounds.call(manual),"inherit":bounds.call(inherit),
 "cards":cards.map(func(card):return {"kind":card.strategy,"active":card.active,"bounds":bounds.call(card)})}
