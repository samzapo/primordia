extends SceneTree
var assertions:=0
var failures:=0
var preferences_path:="user://flow-visual-%s-%s.cfg" % [OS.get_process_id(),Time.get_ticks_usec()]
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for frame in 6:await process_frame
func run() -> void:
	root.size=Vector2i(1200,900)
	var game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false;game.preferences.path=preferences_path
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
	for i in stages.size():
		var tile:=stages[i].duplicate();tile.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(tile,area,Vector2i(i*area.size.x,0))
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
	material.set_shader_parameter("camera",Vector2(200,200));material.set_shader_parameter("zoom",3.0*root.get_final_transform().get_scale().x)
	var sources:=PackedVector4Array([Vector4(400,200,40,1)])
	for i in range(1,preload("res://scripts/induced_currents.gd").COUNT):sources.append(Vector4(0,0,1,0))
	material.set_shader_parameter("eddy_sources",sources)
	var paths: Array[PackedVector2Array]=[]
	for y in [200.0,300.0]:
		var path:=PackedVector2Array()
		for i in 33:path.append(Vector2(332.0+168*i/32.0,y))
		paths.append(path)
	flow.publish_paths(paths,[],Vector2(200,200))
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
	await single_crest(flow,texture,sources)
	flow.queue_free();background.queue_free();await process_frame
	# Actual portrait scene at the widest playable view, including its default art.
	root.size=Vector2i(412,915)
	game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false;game.preferences.path=preferences_path
	root.add_child(game);game.set_process(false);game.set_physics_process(false)
	game.music.enabled=false;game.music.player.stop()
	var currents=preload("res://scripts/induced_currents.gd")
	game.world.time=10;game.manual_zoom=.8;game.camera_locked=false
	var events:=currents.sources(game.world.seed_value,game.world.time)
	game.free_camera=events[0].p
	game.world.environment.light=.12;game._refresh_light_texture()
	game.world.fluid.activity.fill(1);game.world.fluid.set_plants(game.world.habitat_geometry)
	currents.update(game.world)
	for i in 12:game.world.fluid.step(.25)
	game._update_world(1);await settle()
	var shown:=root.get_texture().get_image()
	var blank:=PackedVector4Array()
	for i in currents.COUNT:blank.append(Vector4(0,0,1,0))
	var active: MultiMeshInstance2D=game.flow_view.crests if game.flow_view.use_crests else game.flow_view.streamers
	active.material.set_shader_parameter("eddy_sources",blank)
	await settle()
	var plain:=root.get_texture().get_image()
	var source_pixels:=0;var distant_pixels:=0
	for y in shown.get_height():
		for x in shown.get_width():
			var on:=shown.get_pixel(x,y);var off:=plain.get_pixel(x,y)
			if on.r<=off.r+.006 or on.b>=off.b-.005:continue
			source_pixels+=1
			var at: Vector2=game._screen_world(root.get_final_transform().affine_inverse()*Vector2(x+.5,y+.5))
			var local:=false
			for event in events:
				if event.envelope>.001 and game.Simulation.Medium.offset(event.p,at).length()<=event.radius*currents.GOLD_CORE+16/game.zoom:local=true;break
			if not local:distant_pixels+=1
	check(source_pixels>8 and distant_pixels==0,"Actual dim portrait scene shows source-local gold at the widest playable view")
	check(active.multimesh.visible_instance_count<=game.flow_view.MAX_CRESTS,"Visible crest samples stay inside their bounded budget")
	if OS.has_environment("PRIMORDIA_CURRENT_PORTRAIT_CAPTURE"):shown.save_png(OS.get_environment("PRIMORDIA_CURRENT_PORTRAIT_CAPTURE"))
	print("CURRENT_PORTRAIT source_pixels=%d distant_pixels=%d curves=%d" % [source_pixels,distant_pixels,active.multimesh.visible_instance_count])
	await current_geometry(game)
	await current_style_controls(game)
	game.queue_free();await process_frame
	print("FEEDBACK VISUAL GPU: %d assertions, %d failures; gold=%d outside=%d ordinary=%d GPU=%s" % [assertions,failures,gold,gold_outside,ordinary,RenderingServer.get_video_adapter_name()])
	if FileAccess.file_exists(preferences_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
	quit(0 if failures==0 else 1)


func single_crest(flow,texture: Texture2D,sources: PackedVector4Array) -> void:
	flow.streamers.hide();flow.crests.show()
	flow.position=Vector2(600,450)
	var material: ShaderMaterial=flow.crests.material
	material.set_shader_parameter("camera",Vector2(400,200));material.set_shader_parameter("eddy_sources",sources)
	var path:=PackedVector2Array()
	for i in 33:path.append(Vector2(400,150.0+100*i/32.0))
	var paths: Array[PackedVector2Array]=[path]
	flow.use_crests=true
	flow.publish_paths(paths,[],Vector2(400,200))
	for zoom in [3.0,.8]:
		var stroke_zoom: float=zoom*root.get_final_transform().get_scale().x
		flow.scale=Vector2.ONE*zoom;material.set_shader_parameter("zoom",stroke_zoom)
		flow.crests.hide();await settle();var blank:=root.get_texture().get_image()
		flow.crests.show();await settle();var shown:=root.get_texture().get_image()
		var pixels: Dictionary={}
		var inverse: Transform2D=(root.get_final_transform()*flow.get_global_transform_with_canvas()).affine_inverse()
		var low:=INF;var high:=-INF;var width:=0.0
		for y in shown.get_height():
			for x in shown.get_width():
				var at: Vector2=inverse*Vector2(x+.5,y+.5)+Vector2(400,200)
				if absf(at.x-400)>4 or absf(at.y-200)>55:continue
				var a:=shown.get_pixel(x,y);var b:=blank.get_pixel(x,y)
				if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()<.025:continue
				pixels[Vector2i(x,y)]=true;low=minf(low,at.y);high=maxf(high,at.y);width=maxf(width,absf(at.x-400))
		var components:=0
		while not pixels.is_empty():
			components+=1
			var pending: Array[Vector2i]=[pixels.keys()[0]];pixels.erase(pending[0])
			while not pending.is_empty():
				var at: Vector2i=pending.pop_back()
				for offset in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
					var n: Vector2i=at+offset
					if pixels.erase(n):pending.append(n)
		check(components==1,"One crest instance renders one connected line, without a train of dots")
		check((high-low)*.2>16 and (high-low)*.2<20.5 and width<2.3/stroke_zoom,"A crest keeps its real20um span and thin cross-current profile across zoom")

func current_style_controls(game) -> void:
	var path: String="user://current-style-test-%s-%s.cfg" % [OS.get_process_id(),Time.get_ticks_usec()]
	game.preferences.path=path;game.preferences.persist=true
	game.settings_panel.show()
	for touch in [true,false]:
		root.content_scale_size=Vector2i.ZERO
		root.size=Vector2i(412,915) if touch else Vector2i(1280,800)
		game.touch_zoom.enabled=touch;game.touch_zoom.pixels=1;game._layout()
		game.set_current_style("crests")
		for button in [game.streamline_style_button,game.crest_style_button]:
			var scroll: ScrollContainer=button.get_parent().get_parent().get_parent()
			scroll.ensure_control_visible(button);await settle()
			var rect: Rect2=button.get_global_rect()
			check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect),"Current style control is reachable: touch=%s rect=%s viewport=%s panel=%s" % [touch,rect,root.size,game.settings_panel.get_global_rect()])
			var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=rect.get_center();press.global_position=press.position
			root.push_input(press,true)
			var release: InputEventMouseButton=press.duplicate();release.pressed=false;root.push_input(release,true)
			await settle();game._update_world(1);await settle()
			var waves: bool=button==game.crest_style_button
			check(game.flow_view.use_crests==waves and game.flow_view.crests.visible==waves and game.flow_view.streamers.visible!=waves,"Actual Pause pointer switches mutually exclusive current renderers")
			var restored=preload("res://scripts/preferences.gd").new();restored.path=path;restored.load_settings()
			check(restored.current_style==("crests" if waves else "streamlines"),"Current display preference survives reload")
	game.preferences.persist=false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func current_geometry(game) -> void:
	var flow=game.flow_view
	for style in ["crests","streamlines"]:
		game.set_current_style(style);game.world.time=10;game._update_world(1)
		check(flow.drawn_paths.size()>3,"Both current styles retain several real-field curves")
		for offset in [0.0,.02,.06]:
			game.world.time=10+offset;game._update_world(1)
			var shown: Array[PackedVector2Array]=[]
			for row in flow.drawn_paths.size():
				var path: PackedVector2Array=flow.drawn_paths[row]
				var delta: Vector2=flow.Medium.offset(flow.curve_baselines[row],flow.drawn_samples[row].track.p)
				var first: Vector2=flow.Medium.offset(flow.curve_camera,path[0])+delta
				var points:=PackedVector2Array()
				for point in path:points.append(first+point-path[0])
				shown.append(points)
			var crossings:=0
			for a in shown.size():
				for b in range(a+1,shown.size()):
					for i in range(1,shown[a].size()):
						var p: Vector2=shown[a][i-1];var q: Vector2=shown[a][i]
						var box:=Rect2(p,q-p).abs().grow(.0001)
						for j in range(1,shown[b].size()):
							var r: Vector2=shown[b][j-1];var s: Vector2=shown[b][j]
							if box.intersects(Rect2(r,s-r).abs().grow(.0001)) and Geometry2D.segment_intersects_segment(p,q,r,s)!=null:crossings+=1
			check(crossings==0,"Independent segment inspection finds no crossing at or between geometry refreshes in "+style)
		game.world.time=12;game._update_world(1)
		if not flow.drawn_samples.is_empty():
			var track: Dictionary=flow.drawn_samples[0].track
			var before: Vector2=track.p;var velocity: Vector2=flow._display_flow(before)
			game.world.time=12.02;game._update_world(1)
			var displacement: Vector2=flow.Medium.offset(before,track.p)
			check(displacement.distance_to(velocity*.02)<.05,"Visible centers move at actual local current speed, independent of source migration")
