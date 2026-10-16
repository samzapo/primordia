extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Light=preload("res://scripts/light_field.gd")
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=Sim.new(81,0,false)
	var viewport:=SubViewport.new();viewport.size=Vector2i(820,512)
	viewport.disable_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var values:=PackedByteArray();values.resize(Light.COLS*Light.ROWS)
	var reference: bool="--reference-grid" in OS.get_cmdline_user_args()
	for y in Light.ROWS:
		for x in Light.COLS:
			var p:=Vector2(x+0.5,y+0.5)*Light.SIZE
			var value: float=0.5+0.28*sin(TAU*p.x/Light.WORLD.x*3+0.4)+0.22*cos(TAU*p.y/Light.WORLD.y*3-0.8) if reference else sim.light_at(p)
			values[y*Light.COLS+x]=roundi(clampf(value,0,1)*255)
	var image:=Image.create_from_data(Light.COLS,Light.ROWS,false,Image.FORMAT_R8,values)
	var texture:=ImageTexture.create_from_image(image)
	var acid:=ImageTexture.create_from_image(Image.create(64,40,false,Image.FORMAT_R8))
	var background:=ColorRect.new();background.size=viewport.size
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/light.gdshader")
	background.material=material
	material.set_shader_parameter("camera",Light.WORLD*0.5);material.set_shader_parameter("view_size",Light.WORLD)
	material.set_shader_parameter("screen_center",Vector2(0.5,0.5))
	material.set_shader_parameter("light_map",texture);material.set_shader_parameter("acidity_map",acid)
	material.set_shader_parameter("water_ripples",false);material.set_shader_parameter("fractal_color",false)
	material.set_shader_parameter("habitat_seed",81.0)
	viewport.add_child(background)
	for i in 4:await process_frame
	RenderingServer.force_draw(false)
	var rendered:=viewport.get_texture().get_image()
	check(not rendered.is_empty() and texture.get_format()==Image.FORMAT_R8,"Actual light shader renders a portable normalized texture")
	var low:=0;var high:=0
	for i in values.size():
		if values[i]<values[low]:low=i
		if values[i]>values[high]:high=i
	var dark:=Vector2i((low%Light.COLS+0.5)*viewport.size.x/Light.COLS,(floori(float(low)/Light.COLS)+0.5)*viewport.size.y/Light.ROWS)
	var bright:=Vector2i((high%Light.COLS+0.5)*viewport.size.x/Light.COLS,(floori(float(high)/Light.COLS)+0.5)*viewport.size.y/Light.ROWS)
	check(rendered.get_pixelv(bright).g-rendered.get_pixelv(dark).g>0.1,"Broad bright and dark regions remain visibly distinct")
	var seam:=0.0
	for y in range(0,viewport.size.y,16):
		seam=maxf(seam,absf(rendered.get_pixel(0,y).g-rendered.get_pixel(viewport.size.x-1,y).g))
	check(seam<0.01,"Actual rendered water has no light discontinuity at the wrapping edge")
	material.set_shader_parameter("fractal_color",true)
	for i in 4:await process_frame
	RenderingServer.force_draw(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):viewport.get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	viewport.queue_free();await process_frame
	print("LIGHT RENDER GPU: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
