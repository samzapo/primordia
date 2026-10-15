extends SceneTree
var failures:=0
var assertions:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func colored(image: Image,at: Vector2,food: bool) -> bool:
	for y in range(roundi(at.y)-5,roundi(at.y)+6):
		for x in range(roundi(at.x)-5,roundi(at.x)+6):
			var c:=image.get_pixel(x,y)
			if c.a>.4 and ((c.g>c.r*1.2 and c.g>c.b*1.4) if food else (c.r>c.g*1.25 and c.b>c.g*1.3)):return true
	return false
func run() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(128,128);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var view=preload("res://scripts/cytoplasm_view.gd").new();viewport.add_child(view);view.position=Vector2.ONE*64;view.scale=Vector2.ONE*7
	var mask:=Image.create(2,2,false,Image.FORMAT_RGBA8);mask.fill(Color.WHITE)
	var texture:=ImageTexture.create_from_image(mask)
	var cell=preload("res://scripts/cell.gd").new();cell.chemistry.emit("food",3,Vector2.ZERO)
	view.sync(cell.chemistry,1,texture,100)
	for i in 5:await process_frame
	var image:=viewport.get_texture().get_image()
	for i in 7:
		var at:=Vector2.ONE*64+(Vector2.ZERO if i==0 else Vector2.from_angle((i-1)*TAU/6)*24.5)
		check(colored(image,at,true),"Compatibility presentation draws all seven illustrated contents")
	cell.chemistry.emit("waste",3,Vector2.ZERO,-1,cell.chemistry.particles[0].compartment,0)
	view.sync(cell.chemistry,1,texture,100)
	for i in 5:await process_frame
	image=viewport.get_texture().get_image()
	for i in 7:
		var at:=Vector2.ONE*64+(Vector2.ZERO if i==0 else Vector2.from_angle((i-1)*TAU/6)*24.5)
		check(colored(image,at,i<4),"Compatibility colors preserve the mixed food/waste proportions at glyph %d" % i)
	check(view.multimesh.visible_instance_count==1,"Mixed contents stay in one presented carrier on the browser rendering path")
	viewport.queue_free();await process_frame
	print("VACUOLE COMPATIBILITY GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
