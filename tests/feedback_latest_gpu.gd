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
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(360,760);scene.touch_zoom.enabled=true;scene.touch_zoom.pixels=1
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
  root.size=Vector2i(Vector2(setting.logical)/setting.pixels);root.content_scale_size=setting.logical;scene.touch_zoom.pixels=setting.pixels;scene.palette.open()
  for frame in 4:await process_frame
  check(Rect2(Vector2.ZERO,Vector2(setting.logical)).encloses(scene.palette.panel.get_global_rect()),"Color controls and fixed actions fit dense portrait and landscape layouts")
  scene.palette.close()
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(360,760);scene.touch_zoom.pixels=1.0
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
 await family_portraits(scene)
 vp.queue_free();scene.queue_free();await process_frame
 print("FEEDBACK LATEST GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)

func investment_input(scene) -> void:
 scene.settings_panel.hide();scene.user_paused=false;scene.world.server_mode=true
 print("UI_STARTING_SCALE ",scene.preferences.hud_scale)
 scene.build_open=true;scene.perception="exteroception";scene.manual_zoom=5;scene._update_world(1)
 for setting in [{"logical":Vector2i(390,844),"pixels":1.0,"mobile":true},{"logical":Vector2i(1170,2100),"pixels":3.0,"mobile":true},{"logical":Vector2i(760,360),"pixels":1.0,"mobile":true},{"logical":Vector2i(1280,800),"pixels":1.0,"mobile":false},{"logical":Vector2i(760,360),"pixels":1.0,"mobile":true,"scale":1.5},{"logical":Vector2i(390,844),"pixels":1.0,"mobile":true,"scale":1.5},{"logical":Vector2i(1280,800),"pixels":1.0,"mobile":false,"scale":2.0}]:
  root.size=Vector2i(Vector2(setting.logical)/setting.pixels);root.content_scale_size=setting.logical
  scene.touch_zoom.enabled=setting.mobile;scene.touch_zoom.pixels=setting.pixels
  scene.preferences.hud_scale=setting.get("scale",1.0)
  scene._update_world(1);scene.cell_ui.sync(0)
  for frame in 3:await process_frame
  var at: Vector2=scene.cell_ui.screen_at({"kind":"chemistry"})
  check(scene.cell_ui.interior.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(setting.logical)).has_point(at),"The factory is on screen in desktop and touch layouts")
  # Use the actual world click path; overlaps must retain a factory choice.
  scene.camera_motion.cancel();scene._update_world(1);scene.cell_ui.sync(0);scene.touch_zoom.layout()
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
  scene._cancel_placement();scene.camera_motion.cancel();scene._update_world(1);scene.cell_ui.sync(0);scene.touch_zoom.layout()
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
 scene.touch_zoom.enabled=false;scene.preferences.hud_scale=1.0;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
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
  scene.touch_zoom.enabled=setting.mobile;scene.touch_zoom.pixels=setting.pixels;scene.preferences.hud_scale=setting.get("scale",1.0)
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
 scene.touch_zoom.enabled=true;scene.touch_zoom.pixels=1;scene.preferences.hud_scale=1
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
 scene.world.remote_client=false;scene.world.cells=[cell,child]
 click(card.get_global_rect().get_center())
 for frame in 3:await process_frame
 check(scene.world.player.id==42,"Actual pointer selects a relative through its portrait without the art intercepting input")
 scene.build_open=true;ui.open_context({"kind":"lineage"})
 child=cell;child.dead=true;child.health=0;scene.world.lineage.died(child,scene.world)
 ui.sync(0)
 check(not ui.choices.any(func(choice):return choice.get_meta("family_id",-1)==41),"A dead relative is removed even while the family menu stays open")
 ui.close_context()
