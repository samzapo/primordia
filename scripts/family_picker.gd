extends Panel
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
var up:=Button.new()
var down:=Button.new()
var merge_button:=Button.new()
var repeat_direction:=0
var repeat_after:=0.0
var empty:=Label.new()
var layout_key: Array=[]
var touch_index:=-1
var touch_start:=Vector2.ZERO
var touch_scroll:=0
var touch_dragged:=false
var touch_button: Button
var last_touch_at:=-1000


func initialize(ui) -> void:
 owner_ui=ui;z_index=95
 add_child(margin);margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);margin.add_child(box)
 box.add_child(heading);heading.add_child(title);heading.add_child(close_button)
 title.text="Family";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 close_button.text="×";close_button.tooltip_text="Close family"
 close_button.pressed.connect(ui.close_context)
 box.add_child(merge_button);merge_button.text="Merge a relative into this cell"
 merge_button.pressed.connect(owner_ui.game._begin_merge_selection)
 box.add_child(summary);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 box.add_child(up);up.icon=preload("res://assets/ui/family-up.svg");up.tooltip_text="Previous family row"
 box.add_child(scroll);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
 scroll.add_child(grid);grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 box.add_child(down);down.icon=preload("res://assets/ui/family-down.svg");down.tooltip_text="Next family row"
 for pair in [[up,-1],[down,1]]:
  pair[0].button_down.connect(_start_scroll.bind(pair[1]))
  pair[0].button_up.connect(func():repeat_direction=0)
 box.add_child(empty);empty.text="No living relatives."
 hide()

func _start_scroll(direction: int) -> void:
 repeat_direction=direction;repeat_after=.3;_scroll_row(direction)

func _scroll_row(direction: int) -> void:
 scroll.scroll_vertical+=roundi(direction*(80+6)*minf(owner_ui.ui_scale(),minf(owner_ui.get_viewport_rect().size.x/220.0,owner_ui.get_viewport_rect().size.y/170.0)))

func _process(dt: float) -> void:
 if not is_visible_in_tree():repeat_direction=0;touch_index=-1;touch_button=null;return
 var bar=scroll.get_v_scroll_bar()
 up.disabled=scroll.scroll_vertical<=0
 down.disabled=scroll.scroll_vertical>=bar.max_value-bar.page-.5
 if repeat_direction!=0:
  repeat_after-=dt
  if repeat_after<=0:_scroll_row(repeat_direction);repeat_after=.12

func sync() -> void:
 var viewport: Vector2=owner_ui.get_viewport_rect().size
 title.text="Choose a relative to merge" if owner_ui.context.get("kind","")=="merge_family" else "Family"
 merge_button.visible=owner_ui.context.get("kind","")!="merge_family"
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
  up.custom_minimum_size.y=30*s;down.custom_minimum_size.y=30*s
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
  size.x=width
 empty.visible=count==0;scroll.visible=count>0
 var content_height: float=maxf(tile,rows*(tile+gap)-gap) if count>0 else 0.0
 var fixed: float=2*padding
 var fixed_rows:=0
 for control in [heading,merge_button,summary,empty]:
  if control.visible:fixed+=control.get_combined_minimum_size().y;fixed_rows+=1
 fixed+=gap*maxi(0,fixed_rows-1+(1 if count>0 else 0))
 var available_height: float=maxf(1,viewport.y-top-padding)
 var overflow: bool=count>0 and fixed+content_height>available_height
 up.visible=overflow;down.visible=overflow
 if overflow:fixed+=up.get_combined_minimum_size().y+down.get_combined_minimum_size().y+2*gap
 size.y=minf(available_height,fixed+content_height)
 position=Vector2((viewport.x-size.x)*.5,top)
 empty.visible=count==0;scroll.visible=count>0
 if not visible:get_parent().move_child(self,get_parent().get_child_count()-1)
 show()

func _touch_button_at(at: Vector2) -> Button:
 # Fixed controls take priority over portraits clipped above/below the list.
 for button in [close_button,merge_button,up,down]:
  if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(at):return button
 if scroll.is_visible_in_tree() and scroll.get_global_rect().has_point(at):
  for choice in owner_ui.choices:
   if not choice.disabled and choice.get_global_rect().has_point(at):return choice
 return null

func handle_touch(event: InputEvent) -> bool:
 if not is_visible_in_tree():return false
 # Capture the whole panel before GUI buttons can swallow a finger drag.
 if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device==-1:
  return Time.get_ticks_msec()-last_touch_at<250 and get_global_rect().has_point(event.position)
 if event is InputEventScreenTouch:
  if event.pressed:
   if not get_global_rect().has_point(event.position):return false
   if touch_index<0:
    touch_index=event.index;touch_start=event.position;touch_scroll=scroll.scroll_vertical;touch_dragged=false
    touch_button=_touch_button_at(event.position)
    if touch_button==up:_start_scroll(-1)
    elif touch_button==down:_start_scroll(1)
   last_touch_at=Time.get_ticks_msec();return true
  if event.index!=touch_index:return touch_index>=0 or get_global_rect().has_point(event.position)
  last_touch_at=Time.get_ticks_msec();touch_index=-1;repeat_direction=0
  var tapped: Button=touch_button;touch_button=null
  if not event.canceled and not touch_dragged and is_instance_valid(tapped) and _touch_button_at(event.position)==tapped:
   tapped.pressed.emit()
  return true
 if event is InputEventScreenDrag:
  if event.index!=touch_index:return touch_index>=0 or get_global_rect().has_point(event.position)
  last_touch_at=Time.get_ticks_msec()
  if event.position.distance_to(touch_start)>8*owner_ui.ui_scale():touch_dragged=true
  if touch_dragged:
   repeat_direction=0;scroll.scroll_vertical=touch_scroll-roundi(event.position.y-touch_start.y)
  return true
 return false
