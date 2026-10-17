extends SceneTree
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for frame in 6:await process_frame
func run() -> void:
	root.size=Vector2i(1200,900)
	var game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false
	root.add_child(game);game.set_process(false);game.set_physics_process(false)
	game.music.enabled=false;game.music.player.stop()
	game.world.cells=[game.world.player];game.habitat_view.hide();game.manual_zoom=6
	var cell=game.world.player;cell.angle=0;cell.previous_angle=0
	game._update_world(1);await settle()
	var before:=root.get_texture().get_image()
	var surface=preload("res://scripts/surface_chemistry.gd")
	surface.bind(cell,11,.03,0)
	game._update_world(1);await settle()
	var stages: Array[Image]=[root.get_texture().get_image()]
	for i in 4:
		surface.bind(cell,12,.0375,0)
		game._update_world(1);await settle()
		stages.append(root.get_texture().get_image())
	var after:=stages[-1]
	var view: Node2D=game.views[cell.id]
	var pose:=preload("res://scripts/pore_art.gd").layout(cell,cell.surface_complexes[0])
	var screen: Vector2=root.get_final_transform()*(view.get_global_transform_with_canvas()*pose.at)
	var extent: int=ceili((pose.radius+8)*game.zoom)
	var changed:=0
	for y in range(maxi(0,int(screen.y)-extent),mini(after.get_height(),int(screen.y)+extent)):
		for x in range(maxi(0,int(screen.x)-extent),mini(after.get_width(),int(screen.x)+extent)):
			if Vector3(after.get_pixel(x,y).r,after.get_pixel(x,y).g,after.get_pixel(x,y).b).distance_to(Vector3(before.get_pixel(x,y).r,before.get_pixel(x,y).g,before.get_pixel(x,y).b))>.07:changed+=1
	check(changed>80,"Actual bound pore parts and completed pore are visibly rendered at the membrane")
	var area:=Rect2i(Vector2i(screen)-Vector2i.ONE*extent,Vector2i.ONE*extent*2).intersection(Rect2i(Vector2i.ZERO,after.get_size()))
	for stage in range(1,stages.size()):
		var distinct:=0
		for y in range(area.position.y,area.end.y):
			for x in range(area.position.x,area.end.x):
				if stages[stage].get_pixel(x,y)!=stages[stage-1].get_pixel(x,y):distinct+=1
		check(distinct>20,"Pore assembly phase "+str(stage)+" has distinct actual raster artwork")
	var sheet:=Image.create(area.size.x*stages.size(),area.size.y,false,Image.FORMAT_RGB8)
	for i in stages.size():sheet.blit_rect(stages[i],area,Vector2i(i*area.size.x,0))
	if OS.has_environment("PRIMORDIA_FEEDBACK_PORE_PHASES"):sheet.save_png(OS.get_environment("PRIMORDIA_FEEDBACK_PORE_PHASES"))
	if OS.has_environment("PRIMORDIA_FEEDBACK_PORE_CAPTURE"):after.save_png(OS.get_environment("PRIMORDIA_FEEDBACK_PORE_CAPTURE"))
	game.queue_free();await process_frame
	var background:=ColorRect.new();background.color=Color(.025,.04,.10);background.size=Vector2(1200,900);root.add_child(background)
	var flow=preload("res://scripts/flow_view.gd").new();root.add_child(flow);flow.position=Vector2(140,200);flow.scale=Vector2.ONE*3
	flow.wakes.hide()
	var image:=Image.create(64,40,false,Image.FORMAT_RGF)
	for y in 40:
		for x in 64:image.set_pixel(x,y,Color(20,0,0))
	var texture:=ImageTexture.create_from_image(image)
	var material: ShaderMaterial=flow.streamers.material
	material.set_shader_parameter("flow_map",texture);material.set_shader_parameter("flow_map_old",texture)
	material.set_shader_parameter("camera",Vector2(200,200));material.set_shader_parameter("clock",15.0);material.set_shader_parameter("zoom",3.0)
	var sources:=PackedVector4Array([Vector4(400,200,40,1),Vector4(0,0,1,0),Vector4(0,0,1,0),Vector4(0,0,1,0),Vector4(0,0,1,0),Vector4(0,0,1,0)])
	material.set_shader_parameter("eddy_sources",sources)
	flow.streamers.multimesh.visible_instance_count=2
	flow.streamers.multimesh.set_instance_custom_data(0,Color(200,200,0,1))
	flow.streamers.multimesh.set_instance_custom_data(1,Color(200,300,0,1))
	await settle()
	var capture:=root.get_texture().get_image()
	var gold:=0;var gold_outside:=0;var ordinary:=0
	var inverse: Transform2D=(root.get_final_transform()*flow.get_global_transform_with_canvas()).affine_inverse()
	for y in capture.get_height():
		for x in capture.get_width():
			var color:=capture.get_pixel(x,y)
			var at: Vector2=inverse*Vector2(x+.5,y+.5)+Vector2(200,200)
			if color.r>color.g+.005 and color.r>color.b+.01:
				gold+=1
				if at.distance_to(Vector2(400,200))>40.5:gold_outside+=1
			if absf(at.y-300)<2 and color.g>.05 and color.b>color.r+.04:ordinary+=1
	check(gold>10 and gold_outside==0,"Actual shader pixels turn gold only immediately around the induced source")
	check(ordinary>10,"A separate ordinary streamline retains its pale color")
	if OS.has_environment("PRIMORDIA_FEEDBACK_FLOW_CAPTURE"):capture.save_png(OS.get_environment("PRIMORDIA_FEEDBACK_FLOW_CAPTURE"))
	print("FEEDBACK VISUAL GPU: %d assertions, %d failures; gold=%d outside=%d ordinary=%d GPU=%s" % [assertions,failures,gold,gold_outside,ordinary,RenderingServer.get_video_adapter_name()])
	quit(0 if failures==0 else 1)
