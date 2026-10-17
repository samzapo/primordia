extends PanelContainer
## All current relatives in one responsive grid; only oversized families scroll.
const FONT=preload("res://assets/fonts/ComicNeue-Regular.ttf")
var owner_ui
var margin:=MarginContainer.new()
var box:=VBoxContainer.new()
var heading:=HBoxContainer.new()
var title:=Label.new()
var close_button:=Button.new()
var summary:=Label.new()
var scroll:=ScrollContainer.new()
var grid:=GridContainer.new()
var empty:=Label.new()
var layout_key: Array=[]

func initialize(ui) -> void:
 owner_ui=ui;z_index=95
 add_child(margin);margin.add_child(box)
 box.add_child(heading);heading.add_child(title);heading.add_child(close_button)
 title.text="Family";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 close_button.text="×";close_button.tooltip_text="Close family"
 close_button.pressed.connect(ui.close_context)
 box.add_child(summary);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 box.add_child(scroll);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true
 scroll.add_child(grid);grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 box.add_child(empty);empty.text="No living relatives."
 hide()

func sync() -> void:
 var viewport: Vector2=owner_ui.get_viewport_rect().size
 var s: float=minf(owner_ui.ui_scale(),minf(viewport.x/220.0,viewport.y/170.0))
 var count: int=owner_ui.choices.size()
 var tile: float=80*s
 var gap: float=6*s
 var padding: float=8*s
 var top: float=32*s # Leave room for the instance badge in the browser.
 # Reserve the vertical scrollbar width even before overflow so columns stay stable.
 var available: float=maxf(tile,viewport.x-4*padding-16*s)
 var columns: int=maxi(1,mini(maxi(1,count),floori((available+gap)/(tile+gap))))
 var rows: int=ceili(float(count)/columns)
 var stats: Dictionary=owner_ui.game.world.lineage.statistics()
 summary.text="Highest generation %d · %d cells ever" % [stats.generation,stats.total]
 var key: Array=[viewport,s,count,columns]
 if key!=layout_key:
  layout_key=key
  var style:=StyleBoxFlat.new();style.bg_color=Color("162b49");style.border_color=Color("69a9ab")
  style.set_border_width_all(maxi(1,roundi(s)));style.set_corner_radius_all(roundi(8*s))
  for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,0)
  add_theme_stylebox_override("panel",style)
  var theme:=Theme.new();theme.default_font=FONT;theme.default_font_size=roundi(14*s);self.theme=theme
  for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,roundi(padding))
  box.add_theme_constant_override("separation",roundi(gap))
  title.add_theme_font_size_override("font_size",roundi(20*s))
  summary.add_theme_font_size_override("font_size",roundi(13*s))
  close_button.custom_minimum_size=Vector2.ONE*32*s
  close_button.add_theme_font_size_override("font_size",roundi(22*s))
  empty.add_theme_font_size_override("font_size",roundi(14*s))
  grid.columns=columns
  for direction in ["h_separation","v_separation"]:grid.add_theme_constant_override(direction,roundi(gap))
  for choice in owner_ui.choices:
   choice.custom_minimum_size=Vector2.ONE*tile;choice.text_scale=s*.85
   choice.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
   choice.size_flags_vertical=Control.SIZE_SHRINK_CENTER
   choice.queue_redraw()
  for i in owner_ui.choices.size():
   var choice=owner_ui.choices[i]
   choice.focus_neighbor_top=owner_ui.choices[posmod(i-columns,count)].get_path()
   choice.focus_neighbor_bottom=owner_ui.choices[(i+columns)%count].get_path()
  var width: float=minf(viewport.x-2*padding,maxf(220*s,columns*(tile+gap)-gap+2*padding+16*s))
  summary.custom_minimum_size.x=width-2*padding
  var header: float=76*s # Close/title row, summary and spacing; close stays outside scrolling.
  var height: float=minf(viewport.y-top-padding,header+2*padding+maxf(tile,rows*(tile+gap)-gap))
  scroll.custom_minimum_size.y=maxf(1,height-header-2*padding)
  size=Vector2(width,height);reset_size()
 position=Vector2((viewport.x-size.x)*.5,top)
 empty.visible=count==0;scroll.visible=count>0
 if not visible:get_parent().move_child(self,get_parent().get_child_count()-1)
 show()
