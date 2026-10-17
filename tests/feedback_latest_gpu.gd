extends SceneTree
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
 vp.queue_free();scene.queue_free();await process_frame
 print("FEEDBACK LATEST GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
