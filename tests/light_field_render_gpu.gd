extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Light=preload("res://scripts/light_field.gd")
var assertions:=0
var failures:=0
var viewport: SubViewport
var background: ColorRect
var material: ShaderMaterial
var sim
var capture_path:=""
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func light_texture(scale: float) -> ImageTexture:
	var values:=PackedByteArray();values.resize(Light.COLS*Light.ROWS)
	for y in Light.ROWS:
		for x in Light.COLS:
			values[y*Light.COLS+x]=roundi(clampf(sim.light_at(Vector2(x+0.5,y+0.5)*Light.SIZE)*scale,.02,1)*255)
	return ImageTexture.create_from_image(Image.create_from_data(Light.COLS,Light.ROWS,false,Image.FORMAT_R8,values))
func render(time: float) -> Image:
	material.set_shader_parameter("clock",time)
	for i in 4:await process_frame
	RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()
func capture(image: Image,suffix: String="") -> void:
	if not capture_path.is_empty():image.save_png(capture_path.get_basename()+suffix+".png")
func luminance(color: Color) -> float:return color.r*.2126+color.g*.7152+color.b*.0722
func compare(a: Image,b: Image) -> Dictionary:
	var lit:=0.0;var shade:=0.0;var lit_n:=0;var shade_n:=0
	var bright:=0.0;var dark:=0.0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var field: float=sim.light_at(Vector2(x+0.5,y+0.5)/Vector2(a.get_size())*Light.WORLD)
			var value:=luminance(a.get_pixel(x,y))
			var difference:=absf(value-luminance(b.get_pixel(x,y)))
			if field>.65:lit+=difference;bright+=value;lit_n+=1
			if field<.18:shade+=difference;dark+=value;shade_n+=1
	return {"motion_lit":lit/maxi(1,lit_n),"motion_shade":shade/maxi(1,shade_n),
		"bright":bright/maxi(1,lit_n),"dark":dark/maxi(1,shade_n)}
func run() -> void:
	sim=Sim.new(81,0,false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
	viewport=SubViewport.new();viewport.size=Vector2i(820,512)
	viewport.disable_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var texture:=light_texture(1)
	var acid:=ImageTexture.create_from_image(Image.create(64,40,false,Image.FORMAT_R8))
	background=ColorRect.new();background.size=viewport.size
	material=ShaderMaterial.new();material.shader=preload("res://shaders/light.gdshader")
	background.material=material
	material.set_shader_parameter("camera",Light.WORLD*0.5);material.set_shader_parameter("view_size",Light.WORLD)
	material.set_shader_parameter("screen_center",Vector2(0.5,0.5))
	material.set_shader_parameter("light_map",texture);material.set_shader_parameter("acidity_map",acid)
	material.set_shader_parameter("habitat_seed",81.0)
	viewport.add_child(background)
	# Exercise ordinary artwork, not only the old diagnostic with both effects off.
	var first:=await render(17)
	var later:=await render(20)
	check(not first.is_empty() and texture.get_format()==Image.FORMAT_R8,"Actual water shader renders a portable normalized light texture")
	var day:=compare(first,later)
	check(day.bright-day.dark>.17 and day.bright>day.dark*4,"Normal artwork has substantial broad sun/shade contrast")
	check(day.motion_lit>.008,"Caustics visibly ripple through sunlit water")
	check(day.motion_shade<.002 and day.motion_lit>day.motion_shade*8,"Moving light stays out of deep shade")
	capture(first);capture(later,"-later")
	material.set_shader_parameter("water_ripples",false)
	var still:=await render(17)
	var still_later:=await render(20)
	check(still.get_data()==still_later.get_data(),"Disabling water ripples removes all time-driven background motion")
	var seam:=0.0
	for y in range(0,viewport.size.y,16):
		seam=maxf(seam,absf(still.get_pixel(0,y).g-still.get_pixel(viewport.size.x-1,y).g))
	check(seam<.01,"Rendered water remains continuous at the habitat wrapping edge")
	# Dim weather must dim the water without collapsing all spatial contrast.
	material.set_shader_parameter("water_ripples",true)
	material.set_shader_parameter("illumination_scale",.12)
	material.set_shader_parameter("light_map",light_texture(.12))
	var dim:=await render(17)
	var dim_later:=await render(20)
	var night:=compare(dim,dim_later)
	check(night.bright-night.dark>.12 and night.bright<day.bright,"Dim conditions retain clear shade while reducing overall brightness")
	check(night.motion_lit>.005 and night.motion_shade<.002,"Visible caustics remain confined to lit patches in dim conditions")
	capture(dim,"-dim")
	# A portrait camera crosses a patch boundary at the owner's wide-view scale.
	viewport.size=Vector2i(412,824);background.size=viewport.size
	material.set_shader_parameter("view_size",Vector2(1400,2800))
	material.set_shader_parameter("camera",Vector2(1540,1280))
	var portrait:=await render(17)
	var minimum:=1.0;var maximum:=0.0
	for y in range(0,824,4):
		for x in range(0,412,4):
			var value:=luminance(portrait.get_pixel(x,y))
			minimum=minf(minimum,value);maximum=maxf(maximum,value)
	check(maximum-minimum>.18,"Actual portrait water retains visible light/shade and caustic detail")
	capture(portrait,"-portrait")
	viewport.queue_free();await process_frame
	print("LIGHT RENDER GPU: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
