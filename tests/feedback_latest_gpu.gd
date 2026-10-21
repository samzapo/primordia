extends SceneTree
var capture:=OS.get_environment("PRIMORDIA_UI_CAPTURE")
var assertions:=0
var failures:=0
func check(ok: bool,why: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 print("LATEST_GPU ",RenderingServer.get_video_adapter_name())
 root.size=Vector2i(360,760)
 var scene=load("res://scenes/pond.tscn").instantiate();scene.use_particle_pool=false;root.add_child(scene)
 scene.set_process(false);scene.set_physics_process(false);scene.music.enabled=false;scene.music.player.stop()
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(360,760);scene.controls.touch_enabled=true;scene.controls.pixels=1
 scene.settings_panel.show();scene.palette.open()
 for i in 5:await process_frame
 var wheel=scene.palette.wheel
 check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(scene.palette.panel.get_global_rect()),"Portrait color panel is fully visible including Save and Back")
 check(is_equal_approx(wheel.size.x,wheel.size.y),"The rendered wheel remains circular on a phone-shaped view")
 var origin: Vector2=wheel.global_position+wheel.size*.5
 var radius: float=wheel.size.x*.5
 var image:=root.get_texture().get_image()
 var green:=image.get_pixelv(Vector2i(origin+Vector2.from_angle(TAU/3)*radius*.91))
 check(green.g>.6 and green.r<.35 and green.b<.35,"Actual pixels show a green hue sector, not a blank panel")
 var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
 press.position=origin+Vector2.RIGHT*radius*.91;press.global_position=press.position
 root.push_input(press,true)
 var release: InputEventMouseButton=press.duplicate();release.pressed=false;root.push_input(release,true)
 for frame in 2:await process_frame
 check(wheel.hue<.02 or wheel.hue>.98,"The visible color modal receives actual pointer input above the Pause menu")
 wheel.choose(wheel.size*.5,true)
 for i in 3:await process_frame
 image=root.get_texture().get_image()
 var red:=image.get_pixelv(Vector2i(origin+Vector2(10,10)))
 check(red.r>red.g*1.4 and red.r>red.b*1.4,"Inner disc visibly follows the chosen hue")
 check(scene.palette.caption.text.begins_with("#") and scene.palette.preview.color==wheel.color(),"Color swatch and code match the selected value")
 scene.palette.close()
 for setting in [{"logical":Vector2i(1170,2100),"pixels":3.0},{"logical":Vector2i(760,360),"pixels":1.0}]:
  root.size=Vector2i(Vector2(setting.logical)/setting.pixels);root.content_scale_size=setting.logical;scene.controls.pixels=setting.pixels;scene.palette.open()
  for frame in 4:await process_frame
  check(Rect2(Vector2.ZERO,Vector2(setting.logical)).encloses(scene.palette.panel.get_global_rect()),"Color controls and fixed actions fit dense portrait and landscape layouts")
  scene.palette.close()
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(360,760);scene.controls.pixels=1.0
 var vp:=SubViewport.new();vp.size=Vector2i(256,128);vp.transparent_bg=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
 var canvas:=Node2D.new();vp.add_child(canvas)
 canvas.draw.connect(func():
  var art=preload("res://scripts/visuals.gd")
  art.icon(canvas,Vector2(64,64),"toxin",0,1,0,"graze",0,true,0,false)
  art.icon(canvas,Vector2(192,64),"toxin",0,1,0,"graze",0,true,0,true))
 canvas.queue_redraw()
 for i in 4:await process_frame
 image=vp.get_texture().get_image()
 var active:=image.get_pixel(61,63);var depleted:=image.get_pixel(189,63)
 check(active.s>.6 and depleted.s<active.s*.4,"Actual depleted organelle pixels are visibly desaturated")
 var cell=scene.world.player
 scene.lineage_names=[{"root":cell.lineage_id(),"color":"#23dc7e","name":"Fixture","online":false}]
 scene._update_world(1)
 check(scene.views[cell.id].art.colors[1].is_equal_approx(Color("#23dc7e")),"Every viewed member reads its lineage’s chosen body color")
 await investment_input(scene)
 await leaf_selection(scene)
 await family_portraits(scene)
 await receptor_factory_controls(scene)
 await family_grid(scene)
 vp.queue_free();scene.queue_free();await process_frame
 print("FEEDBACK LATEST GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)

func investment_input(scene) -> void:
 scene.settings_panel.hide();scene.user_paused=false;scene.world.server_mode=true
 print("UI_STARTING_SCALE ",scene.preferences.hud_scale)
 scene.build_open=true;scene.perception="exteroception";scene.manual_zoom=5;scene._update_world(1)
 for setting in [{"logical":Vector2i(390,844),"pixels":1.0,"mobile":true},{"logical":Vector2i(1170,2100),"pixels":3.0,"mobile":true},{"logical":Vector2i(760,360),"pixels":1.0,"mobile":true},{"logical":Vector2i(1280,800),"pixels":1.0,"mobile":false},{"logical":Vector2i(760,360),"pixels":1.0,"mobile":true,"scale":1.5},{"logical":Vector2i(390,844),"pixels":1.0,"mobile":true,"scale":1.5},{"logical":Vector2i(1280,800),"pixels":1.0,"mobile":false,"scale":2.0}]:
  root.size=Vector2i(Vector2(setting.logical)/setting.pixels);root.content_scale_size=setting.logical
  scene.controls.touch_enabled=setting.mobile;scene.controls.pixels=setting.pixels
  scene.preferences.hud_scale=setting.get("scale",1.0)
  scene._update_world(1);scene.cell_ui.sync(0)
  for frame in 3:await process_frame
  var at: Vector2=scene.cell_ui.screen_at({"kind":"chemistry"})
  check(scene.cell_ui.interior.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(setting.logical)).has_point(at),"The factory is on screen in desktop and touch layouts")
  # Use the actual world click path; overlaps must retain a factory choice.
  scene.camera_motion.cancel();scene._update_world(1);scene.cell_ui.sync(0);scene.controls.layout()
  at=scene.cell_ui.screen_at({"kind":"chemistry"})
  if capture!="" and setting.logical==Vector2i(390,844):root.get_texture().get_image().save_png(capture+"/factory-portrait.png")
  click(at)
  for frame in 2:await process_frame
  if scene.cell_ui.context.get("kind","")=="overlap":
   var option=scene.cell_ui.choices.filter(func(choice):return choice.kind=="internal_factory")
   if not option.is_empty():click(option[0].get_global_rect().get_center())
   for frame in 2:await process_frame
  check(scene.cell_ui.context.get("kind","")=="chemistry","Actual pointer can open the recognizable factory from outside")
  # Internal organs are available through its ordinary catalog and easing path.
  if not scene.cell_ui.choices.is_empty():click(scene.cell_ui.choices[0].get_global_rect().get_center())
  for frame in 2:await process_frame
  check(scene.perception=="interoception" and scene.selected==12,"Internal selection begins placement in Interoception")
  scene._cancel_placement();scene.camera_motion.cancel();scene._update_world(1);scene.cell_ui.sync(0);scene.controls.layout()
  click(scene.cell_ui.screen_at({"kind":"chemistry"}))
  for frame in 2:await process_frame
  if scene.cell_ui.context.get("kind","")=="overlap":
   var option=scene.cell_ui.choices.filter(func(choice):return choice.kind=="internal_factory")
   if not option.is_empty():click(option[0].get_global_rect().get_center())
   for frame in 2:await process_frame
  check(scene.cell_ui.context.get("kind","")=="chemistry","The same visible factory receives actual clicks from inside")
  scene.cell_ui.open_context({"kind":"investment"})
  var picker=scene.cell_ui.investment_picker
  for frame in 5:scene.cell_ui.sync(0);await process_frame
  check(Rect2(Vector2.ZERO,Vector2(setting.logical)).encloses(picker.get_global_rect()),"Complete strategy panel fits viewport: setting=%s actual=%s panel=%s minimum=%s" % [setting,scene.get_viewport_rect(),picker.get_global_rect(),picker.get_combined_minimum_size()])
  check(picker.cards.all(func(card):return picker.get_global_rect().encloses(card.get_global_rect())) and picker.cards[0].get_global_rect().end.x<=picker.cards[1].global_position.x and picker.cards[1].get_global_rect().end.x<=picker.cards[2].global_position.x,"All three cell pictures are visible side by side")
  if capture!="" and setting.logical in [Vector2i(390,844),Vector2i(1280,800)]:
   root.get_texture().get_image().save_png(capture+("/strategy-portrait.png" if setting.mobile else "/strategy-desktop.png"))
  click(picker.cards[1].get_global_rect().get_center())
  for frame in 2:await process_frame
  check(scene.world.investment.lineages.get(scene.world.player.lineage_id(),"")=="producer" and picker.cards[1].active,"Actual pointer selects Producer without cycling")
  var image:=root.get_texture().get_image()
  var rect: Rect2=picker.cards[1].get_global_rect()
  var conversion:=Vector2(root.size)/Vector2(setting.logical)
  var pixel:=image.get_pixelv(Vector2i((rect.position+Vector2(rect.size.x*.5,rect.size.y*.35))*conversion))
  check(pixel.b>.35 or pixel.g>.5,"Strategy card renders an actual colored cell illustration")
  var mark_scale: float=picker.cards[1].text_scale
  var mark_rect:=Rect2((rect.position+Vector2(rect.size.x-25*mark_scale,10*mark_scale))*conversion,Vector2.ONE*16*mark_scale*conversion)
  var mark_pixels:=0
  for y in range(ceili(mark_rect.position.y),floori(mark_rect.end.y)):
   for x in range(ceili(mark_rect.position.x),floori(mark_rect.end.x)):
    var color:=image.get_pixel(x,y)
    if color.r>.55 and color.g>.75 and color.b>.65:mark_pixels+=1
  check(mark_pixels>=3,"Actual pixels show a vector selection tick in every viewport and UI scale")

  scene.cell_ui.close_context();scene.perception="exteroception"
 # The shared drawings must produce visible icons, not names or blank circles.
 scene.controls.touch_enabled=false;scene.preferences.hud_scale=1.0;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
 scene.cell_ui.open_context({"kind":"overlap","targets":["assembly","chemistry","nucleus","atp","bud"].map(func(kind):return {"kind":kind})})
 for frame in 4:scene.cell_ui.sync(0);await process_frame
 var image:=root.get_texture().get_image()
 for choice in scene.cell_ui.choices:
  var pixel:=image.get_pixelv(Vector2i(choice.get_global_rect().get_center()))
  check(pixel.get_luminance()>.2,"Overlap choice draws visible artwork for "+choice.kind)
 if capture!="":image.save_png(capture+"/overlap-desktop.png")
 scene.cell_ui.close_context()
func click(at: Vector2) -> void:
 var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=at;press.global_position=at
 root.push_input(press,true)
 var release: InputEventMouseButton=press.duplicate();release.pressed=false;root.push_input(release,true)


func family_portraits(scene) -> void:
 var Sim=scene.Simulation
 var cell=Sim.Cell.new(41);cell.body=70;cell.biomass=30;cell.update_geometry()
 cell.add_organ("feeding",0,"graze",false);cell.add_organ("photosynthesis",1,"graze",false)
 var child=Sim.Cell.clone_state(cell);child.id=42;child.lineage=41;child.generation=2
 child.add_organ("toxin",2,"graze",false);child.position+=Vector2(180,0)
 scene.world.player=cell;scene.world.cells=[cell,child]
 scene.world.lineage=Sim.Lineage.new();scene.world.lineage.root_id=41
 scene.world.lineage.register(cell,-1,0,"active",0);scene.world.lineage.register(child,41,2,"living",1)
 scene.world.evolution.sandbox=true;scene.build_open=true;scene.perception="exteroception"
 scene.lineage_names=[{"root":41,"color":"#e82b37","name":"Fixture","online":true}]
 var ui=scene.cell_ui
 for setting in [{"logical":Vector2i(390,844),"pixels":1.0,"mobile":true},{"logical":Vector2i(1170,2100),"pixels":3.0,"mobile":true},{"logical":Vector2i(760,360),"pixels":1.0,"mobile":true},{"logical":Vector2i(1280,800),"pixels":1.0,"mobile":false},{"logical":Vector2i(390,844),"pixels":1.0,"mobile":true,"scale":1.5}]:
  root.size=Vector2i(Vector2(setting.logical)/setting.pixels);root.content_scale_size=setting.logical
  scene.controls.touch_enabled=setting.mobile;scene.controls.pixels=setting.pixels;scene.preferences.hud_scale=setting.get("scale",1.0)
  scene._update_world(1);ui.open_context({"kind":"lineage"})
  for frame in 5:ui.sync(0);await process_frame
  var cards: Array=ui.choices.filter(func(choice):return choice.has_meta("family_id"))
  check(cards.size()==2 and cards.all(func(card):return not card.portrait.is_empty()),"Every current family member has actual anatomy in the shared menu")
  check(cards.all(func(card):return Rect2(Vector2.ZERO,Vector2(setting.logical)).encloses(card.get_global_rect())),"Family portraits and badges fit portrait, dense touch, landscape and desktop")
  var card=cards.filter(func(choice):return choice.get_meta("family_id")==42)[0]
  check(card.symbol=="2" and card.portrait.organs.any(func(organ):return organ.kind=="toxin"),"Generation is a small number while the picture uses that relative's own organs")
  var image:=root.get_texture().get_image()
  var conversion:=Vector2(root.size)/Vector2(setting.logical)
  var rect: Rect2=card.get_global_rect()
  var center: Vector2=rect.get_center()*conversion
  var colored:=0;var badge_ink:=0
  for y in range(-8,9):
   for x in range(-8,9):
    var color:=image.get_pixelv(Vector2i(center+Vector2(x,y)))
    if color.r>color.b*1.4 and color.r>.4:colored+=1
  var badge: Vector2=(rect.get_center()+Vector2.ONE*minf(rect.size.x,rect.size.y)*.30)*conversion
  var reach:=maxi(3,roundi(6*card.text_scale*conversion.x))
  for y in range(-reach,reach+1):
   for x in range(-reach,reach+1):
    var color:=image.get_pixelv(Vector2i(badge+Vector2(x,y)))
    if color.r>.65 and color.g>.75 and color.b>.65:badge_ink+=1
  check(colored>10,"Actual pixels show the family-colored cell behind the corner badge")
  check(badge_ink>=2,"Actual pixels show a readable generation number in the bottom corner: %s pixels=%d" % [setting,badge_ink])
  if capture!="" and setting.logical==Vector2i(390,844):image.save_png(capture+"/family-portrait.png")
 # Existing controls keep working above the illustration.
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 scene.controls.touch_enabled=true;scene.controls.pixels=1;scene.preferences.hud_scale=1
 ui.open_context({"kind":"lineage"})
 for frame in 4:ui.sync(0);await process_frame
 var cards: Array=ui.choices.filter(func(choice):return choice.get_meta("family_id",-1)==42)
 var card=cards[0]
 var energy: float=child.energy;var random: int=scene.world.rng.state;var anatomy: Array=child.organs.duplicate(true)
 child.organs[-1].hp*=.5;child.holes.append({"a":1.2,"size":.5});ui.sync(0)
 check(card.portrait.organs[-1].hp==.5 and card.portrait.holes.size()==1,"An open family menu refreshes actual damage and wounds")
 child.organs=anatomy;ui.sync(0)
 check(child.energy==energy and scene.world.rng.state==random,"Drawing family portraits does not consume resources or ecology RNG")
 var before: Dictionary=card.portrait
 scene.lineage_names[0].color="#2735ea";ui.sync(0)
 for frame in 3:await process_frame
 check(card.portrait_art.colors[1].is_equal_approx(Color("#2735ea")),"An open portrait follows a newly chosen lineage color")
 # Off-camera pictures use only the dedicated presentation snapshot.
 scene.world.remote_client=true
 scene.family_portraits=preload("res://scripts/cell_portrait.gd").family(scene.world,scene.world.lineage)
 scene.world.cells=[cell];ui.sync(0)
 check(not card.portrait.is_empty() and card.portrait.id==42,"A remote relative stays illustrated even outside the camera's simulation models")
 var commands: Array=[]
 scene.world.command_sink=func(action,args):commands.append({"action":action,"args":args})
 var selected_id: int=scene.world.player.id
 click(card.get_global_rect().get_center())
 for frame in 3:await process_frame
 check(commands.any(func(command):return command.action=="follow" and command.args.id==42),"An off-camera portrait submits the ordinary authoritative follow command")
 check(scene.world.player.id==selected_id and not scene.world.cells.has(child),"Remote selection waits for the server instead of manufacturing a client body")
 check(not scene._switch_family(99999),"Remote family switching rejects unknown IDs before sending")
 scene.world.remote_client=false;scene.world.command_sink=Callable();scene.world.cells=[cell,child]
 scene.build_open=true;ui.open_context({"kind":"lineage"})
 for frame in 3:ui.sync(0);await process_frame
 card=ui.choices.filter(func(choice):return choice.get_meta("family_id",-1)==42)[0]
 click(card.get_global_rect().get_center())
 for frame in 3:await process_frame
 check(scene.world.player.id==42,"Actual pointer selects a relative through its portrait without the art intercepting input")
 scene.build_open=true;ui.open_context({"kind":"lineage"})
 child=cell;child.dead=true;child.health=0;scene.world.lineage.died(child,scene.world)
 ui.sync(0)
 check(not ui.choices.any(func(choice):return choice.get_meta("family_id",-1)==41),"A dead relative is removed even while the family menu stays open")
 ui.close_context()


func family_fixture(scene,count: int) -> void:
 var Sim=scene.Simulation
 scene.cell_ui.close_context();scene.world.cells=[]
 scene.world.lineage=Sim.Lineage.new();scene.world.lineage.root_id=4000
 for i in count:
  var cell=Sim.Cell.new(4000+i);cell.lineage=4000
  cell.position=Vector2(1500+(i%8)*150,1000+floori(i/8.0)*150)
  cell.previous_position=cell.position;cell.add_organ("feeding",0,"graze",false)
  cell.add_organ("photosynthesis",1,"graze",false)
  scene.world.cells.append(cell)
  scene.world.lineage.register(cell,-1 if i==0 else 4000,i%7,"active" if i==0 else "living",i)
 scene.world.player=scene.world.cells[0];scene.world.remote_client=false
 scene.lineage_names=[{"root":4000,"color":"#2885ea","name":"Fixture","online":true}]
 scene.world.evolution.sandbox=true;scene.build_open=false;scene.selected=-1;scene.moving_id=-1;scene.world.commit_build()
 scene.cell_ui.reset()

func family_grid(scene) -> void:
 var ui=scene.cell_ui
 family_fixture(scene,16)
 for setting in [{"logical":Vector2i(390,844),"pixels":1.0,"mobile":true},{"logical":Vector2i(1170,2100),"pixels":3.0,"mobile":true},{"logical":Vector2i(760,360),"pixels":1.0,"mobile":true},{"logical":Vector2i(1280,800),"pixels":1.0,"mobile":false},{"logical":Vector2i(390,844),"pixels":1.0,"mobile":true,"scale":1.5},{"logical":Vector2i(1280,800),"pixels":1.0,"mobile":false,"scale":2.0}]:
  root.size=Vector2i(Vector2(setting.logical)/setting.pixels);root.content_scale_size=setting.logical
  scene.controls.touch_enabled=setting.mobile;scene.controls.pixels=setting.pixels
  scene.preferences.hud_scale=setting.get("scale",1.0)
  scene._update_world(1);ui.open_context({"kind":"lineage"})
  for frame in 6:ui.sync(0);await process_frame
  var picker=ui.family_picker
  check(ui.choices.size()==16 and ui.choices.all(func(choice):return choice.has_meta("family_id") and not choice.portrait.is_empty()),"All current portraits share one grid without summary/More action slots on either platform")
  check(not ui.choices.any(func(choice):return choice.symbol.begins_with("G") or choice.symbol=="More"),"Family navigation has no G-generation tile or pagination")
  check(picker.visible and Rect2(Vector2.ZERO,Vector2(setting.logical)).encloses(picker.get_global_rect()),"The expanded family panel fits every screen and UI scale: %s bounds=%s" % [setting,picker.get_global_rect()])
  check(picker.get_global_rect().encloses(picker.close_button.get_global_rect()) and picker.close_button.is_visible_in_tree(),"Family Close stays inside the fixed header")
  check(picker.summary.text.contains("6") and picker.summary.text.contains("16"),"Highest generation and lifetime totals remain small header text")
  check(ui.choices.all(func(choice):return choice.size.x>=60*minf(ui.ui_scale(),float(setting.logical.x)/220)),"Family pictures keep a useful selectable size")
  if setting.logical==Vector2i(390,844) and setting.get("scale",1.0)==1:
   check(picker.size.y>setting.logical.y*.32 and picker.scroll.get_v_scroll_bar().max_value<=picker.scroll.size.y+1,"An ordinary large family expands beyond the old tray cap and fits without paging or scrolling")
   if capture!="":root.get_texture().get_image().save_png(capture+"/family-grid-portrait.png")
  # Every visible picture occupies a distinct, non-overlapping grid cell.
  for i in range(1,ui.choices.size()):
   check(not ui.choices[i].get_global_rect().intersects(ui.choices[i-1].get_global_rect()),"Portrait grid cells do not overlap")
  click(picker.close_button.get_global_rect().get_center())
  for frame in 2:await process_frame
  check(ui.context.is_empty() and not picker.visible,"Actual pointer closes the family grid without a server response: %s context=%s viewport=%s close=%s hovered=%s" % [setting,ui.context,scene.get_viewport_rect(),picker.close_button.get_global_rect(),root.gui_get_hovered_control()])
 # A very large family keeps every entry while only its portrait area scrolls.
 family_fixture(scene,64)
 var picker=ui.family_picker
 for setting in [{"logical":Vector2i(574,1106),"pixels":1.0},{"logical":Vector2i(1170,2100),"pixels":3.0},{"logical":Vector2i(390,500),"pixels":1.0}]:
  root.size=Vector2i(Vector2(setting.logical)/setting.pixels);root.content_scale_size=setting.logical
  scene.controls.touch_enabled=true;scene.controls.pixels=setting.pixels;scene.preferences.hud_scale=1
  scene._update_world(1);ui.open_context({"kind":"lineage"})
  for frame in 6:ui.sync(0);await process_frame
  check(Rect2(Vector2.ZERO,Vector2(setting.logical)).encloses(picker.get_global_rect()),"All64 portraits stay in a bounded panel after viewport resizing: "+str(picker.get_global_rect()))
  check(picker.get_global_rect().encloses(picker.down.get_global_rect()) and picker.get_global_rect().encloses(picker.close_button.get_global_rect()),"Close and lower arrow stay inside the visible panel")
 check(ui.choices.size()==64 and picker.scroll.get_v_scroll_bar().max_value>picker.scroll.size.y,"An overflowing family keeps all 64 entries in one scrollable menu: count=%d viewport=%s columns=%d panel=%s max=%f page=%f" % [ui.choices.size(),scene.get_viewport_rect(),picker.grid.columns,picker.get_global_rect(),picker.scroll.get_v_scroll_bar().max_value,picker.scroll.get_v_scroll_bar().page])
 check(picker.down.visible and picker.up.visible and picker.up.disabled and not picker.down.disabled,"Overflow displays fixed vector arrow controls with correct end states")
 var close_at: Vector2=picker.close_button.global_position
 var original_id: int=scene.world.player.id
 var start: Vector2=picker.scroll.get_global_rect().get_center()
 var touch:=InputEventScreenTouch.new();touch.index=0;touch.position=start;touch.pressed=true
 root.push_input(touch,true)
 for i in 8:
  var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=start-Vector2(0,(i+1)*18);drag.relative=Vector2(0,-18)
  root.push_input(drag,true);await process_frame
 var release_touch: InputEventScreenTouch=touch.duplicate();release_touch.pressed=false;release_touch.position=start-Vector2(0,144)
 root.push_input(release_touch,true)
 for frame in 3:ui.sync(0);await process_frame
 check(picker.scroll.scroll_vertical>=130 and scene.world.player.id==original_id and not ui.context.is_empty(),"A real finger swipe scrolls portraits without selecting a relative or moving the world")
 # Swipes may start on pictures, fixed header buttons or the panel margin.
 for region in ["portrait","title","merge","close","margin"]:
  picker.scroll.scroll_vertical=200
  for frame in 3:await process_frame
  var swipe_start: Vector2
  match region:
   "portrait":
    var visible_choices: Array=ui.choices.filter(func(choice):return picker.scroll.get_global_rect().encloses(choice.get_global_rect()))
    check(not visible_choices.is_empty(),"An actual visible portrait is available for swipe capture")
    if visible_choices.is_empty():continue
    swipe_start=visible_choices[0].get_global_rect().get_center()
   "title":swipe_start=picker.title.get_global_rect().get_center()
   "merge":swipe_start=picker.merge_button.get_global_rect().get_center()
   "close":swipe_start=picker.close_button.get_global_rect().get_center()
   "margin":swipe_start=picker.get_global_rect().position+Vector2(2,60)
  var before_swipe: int=picker.scroll.scroll_vertical
  var begin:=InputEventScreenTouch.new();begin.index=0;begin.position=swipe_start;begin.pressed=true
  root.push_input(begin,true)
  for i in 6:
   var move:=InputEventScreenDrag.new();move.index=0;move.position=swipe_start+Vector2(0,(i+1)*12);move.relative=Vector2(0,12)
   root.push_input(move,true);await process_frame
  var finish: InputEventScreenTouch=begin.duplicate();finish.pressed=false;finish.position=swipe_start+Vector2(0,72)
  root.push_input(finish,true)
  for frame in 3:ui.sync(0);await process_frame
  check(picker.scroll.scroll_vertical<=before_swipe-65 and not ui.context.is_empty() and scene.world.player.id==original_id and not scene.merge_selecting(),"A swipe starting on %s scrolls without activating its button or selecting a cell" % region)
 picker.scroll.scroll_vertical=0
 click(picker.down.get_global_rect().get_center())
 for frame in 3:await process_frame
 check(picker.scroll.scroll_vertical>0,"Actual pointer on the down arrow scrolls a family row")
 click(picker.up.get_global_rect().get_center())
 for frame in 3:await process_frame
 check(picker.scroll.scroll_vertical==0,"Actual pointer on the up arrow returns to the first row")
 for button in [picker.down,picker.up]:
  var arrow_touch:=InputEventScreenTouch.new();arrow_touch.index=0;arrow_touch.position=button.get_global_rect().get_center();arrow_touch.pressed=true
  root.push_input(arrow_touch,true)
  var arrow_release: InputEventScreenTouch=arrow_touch.duplicate();arrow_release.pressed=false;root.push_input(arrow_release,true)
  for frame in 3:await process_frame
  check((picker.scroll.scroll_vertical>0 if button==picker.down else picker.scroll.scroll_vertical==0) and picker.repeat_direction==0,"Touch arrow taps still scroll one row and release their hold after panel capture")

 var at: Vector2=picker.scroll.get_global_rect().get_center()
 for i in 6:
  var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=at;wheel.global_position=at
  root.push_input(wheel,true)
  var up: InputEventMouseButton=wheel.duplicate();up.pressed=false;root.push_input(up,true)
  await process_frame
 check(picker.scroll.scroll_vertical>0,"Real scroll input reaches the family list: scroll=%d max=%f page=%f hovered=%s" % [picker.scroll.scroll_vertical,picker.scroll.get_v_scroll_bar().max_value,picker.scroll.get_v_scroll_bar().page,root.gui_get_hovered_control()])
 ui.choices[-1].grab_focus()
 for frame in 8:ui.sync(0);await process_frame
 check(picker.scroll.get_global_rect().encloses(ui.choices[-1].get_global_rect()),"Keyboard focus can reveal the last relative without another page")
 check(picker.close_button.global_position==close_at,"Scrolling portraits never moves the Close button")
 if capture!="":root.get_texture().get_image().save_png(capture+"/family-grid-scrolled.png")
 var relative_id: int=ui.choices[-1].get_meta("family_id")
 var last=ui.choices[-1]
 var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
 press.position=last.get_global_rect().get_center();press.global_position=press.position
 root.push_input(press,true)
 for frame in 3:await process_frame
 var release: InputEventMouseButton=press.duplicate();release.pressed=false;root.push_input(release,true)
 for frame in 3:await process_frame

 check(scene.world.player.id==relative_id,"The last scrolled portrait still switches through the validated family action")
 ui.open_context({"kind":"lineage"})
 for frame in 6:ui.sync(0);await process_frame
 picker.scroll.scroll_vertical=0
 for frame in 3:await process_frame
 var first=ui.choices[0];var first_id: int=first.get_meta("family_id")
 var tap:=InputEventScreenTouch.new();tap.index=0;tap.position=first.get_global_rect().get_center();tap.pressed=true
 root.push_input(tap,true)
 var release_tap: InputEventScreenTouch=tap.duplicate();release_tap.pressed=false;root.push_input(release_tap,true)
 for frame in 3:await process_frame
 check(scene.world.player.id==first_id,"A real finger tap after scrolling still selects exactly the intended living relative")
 ui.open_context({"kind":"lineage"})
 for frame in 3:ui.sync(0);await process_frame
 var close_touch:=InputEventScreenTouch.new();close_touch.index=0;close_touch.position=picker.close_button.get_global_rect().get_center();close_touch.pressed=true
 root.push_input(close_touch,true)
 var close_release: InputEventScreenTouch=close_touch.duplicate();close_release.pressed=false;root.push_input(close_release,true)
 for frame in 3:await process_frame
 check(ui.context.is_empty() and not picker.visible,"A real finger tap still activates Close after whole-panel swipe capture")

func leaf_selection(scene) -> void:
 var cell=scene.world.player
 if cell.count("photosynthesis")==0:cell.add_organ("photosynthesis",1,"graze",false)
 var leaf: Dictionary=cell.organs.filter(func(o):return o.kind=="photosynthesis")[0]
 for mobile in [false,true]:
  root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844) if mobile else Vector2i(1280,800)
  scene.controls.touch_enabled=mobile;scene.controls.pixels=1;scene.preferences.hud_scale=1
  leaf.mutation="shade_leaf";scene.cell_ui.open_context({"kind":"organ","id":leaf.id})
  for frame in 4:scene.cell_ui.sync(0);await process_frame
  var options: Array=scene.cell_ui.choices.filter(func(choice):return choice.caption.begins_with("Sun"))
  check(options.size()==1 and not options[0].disabled,"Sun is an available ordinary specialization on both platforms")
  if options.is_empty():continue
  click(options[0].get_global_rect().get_center())
  for frame in 3:scene.cell_ui.sync(0);await process_frame
  check(cell.organ_by_id(leaf.id).mutation=="sun_leaf","Actual pointer commits Sun specialization to the selected leaf")
  scene.cell_ui.close_context()

func receptor_factory_controls(_previous_scene) -> void:
 _previous_scene.hide();_previous_scene.ui.hide()
 var scene=load("res://scenes/pond.tscn").instantiate();scene.use_particle_pool=false;scene.preferences.persist=false
 root.add_child(scene);scene.set_process(false);scene.set_physics_process(false);scene.music.enabled=false;scene.music.player.stop()
 var ui=scene.cell_ui
 family_fixture(scene,1)
 var cell=scene.world.player;cell.ap=0
 for mobile in [false,true]:
  root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(412,915) if mobile else Vector2i(1280,800)
  scene.controls.touch_enabled=mobile;scene.controls.pixels=1;scene.preferences.hud_scale=1
  for mode in ["exteroception","interoception"]:
   scene.perception=mode;scene.camera_locked=true;scene.camera_offset=Vector2.ZERO;scene.manual_zoom=4;scene.build_open=true;scene.camera_followed_id=-1;scene.camera_has_pose=false
   scene.camera_motion.cancel()
   for frame in 6:scene._layout();scene._update_world(1);ui.sync(0);await process_frame
   var at: Vector2=ui.screen_at({"kind":"receptors"})
   var pick: Dictionary=ui.pick(at)
   check(pick.get("kind","")=="receptors" or pick.get("targets",[]).any(func(item):return item.kind=="receptors"),"The receptor factory is a real reachable click point in both views and platforms: %s at=%s visible=%s" % [pick,at,ui.interior.visible])
   ui.open_context({"kind":"receptors"})
   for frame in 5:ui.sync(0);await process_frame
   check(ui.choices.map(func(choice):return choice.kind)==["sensing","hunting","family_toward","family_away"] and ui.choices.all(func(choice):return choice.ap_cost==0 and not choice.disabled),"All four receptor pictures show free available construction at zero AP")
   if OS.has_environment("PRIMORDIA_RECEPTOR_CAPTURE"):root.get_texture().get_image().save_jpg(OS.get_environment("PRIMORDIA_RECEPTOR_CAPTURE")+("-mobile.jpg" if mobile else "-desktop.jpg"),.85)
   var choice=ui.choices[2]
   click(choice.get_global_rect().get_center())
   for frame in 3:ui.sync(0);await process_frame
   check(scene.selected==15 and not scene.placement_status().contains("Needs") and ui.mobile_stocks.text.contains("Cost 0 biomass") if mobile else scene.selected==15 and not scene.placement_status().contains("Needs"),"Actual factory choice enters ordinary free receptor placement without switching cell")
   scene._cancel_placement()
 ui.close_context();scene.queue_free();await process_frame
 _previous_scene.show();_previous_scene.ui.show()
