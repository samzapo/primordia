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
	if "--resource-warnings-only" in OS.get_cmdline_user_args():
		await resource_warning_pixels(game)
		print("RESOURCE WARNING GPU: %d assertions, %d failures; GPU=%s" % [assertions,failures,RenderingServer.get_video_adapter_name()])
		game.queue_free();await process_frame
		if FileAccess.file_exists(preferences_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
		quit(0 if failures==0 else 1);return
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
	await resource_warning_pixels(game)
	game.queue_free();await process_frame
	var background:=ColorRect.new();background.color=Color(.025,.04,.10);background.size=Vector2(1200,900);root.add_child(background)
	var flow=preload("res://scripts/flow_view.gd").new();root.add_child(flow);flow.position=Vector2(140,200);flow.scale=Vector2.ONE*3
	flow.wakes.hide();flow.use_crests=false
	var image:=Image.create(64,40,false,Image.FORMAT_RGF)
	for y in 40:
		for x in 64:image.set_pixel(x,y,Color(20,0,0))
	var texture:=ImageTexture.create_from_image(image)
	var material: ShaderMaterial=flow.streamers.material
	material.set_shader_parameter("camera",Vector2(200,200));material.set_shader_parameter("zoom",3.0*root.get_final_transform().get_scale().x)
	var sources:=PackedVector4Array([Vector4(400,200,40,1)])
	for i in range(1,flow.SOURCE_MARKERS):sources.append(Vector4(0,0,1,0))
	material.set_shader_parameter("eddy_sources",sources)
	flow.input_crests.material.set_shader_parameter("eddy_sources",sources)
	flow.input_crests.material.set_shader_parameter("camera",Vector2(200,200));flow.input_crests.material.set_shader_parameter("zoom",3.0*root.get_final_transform().get_scale().x)
	var paths: Array[PackedVector2Array]=[]
	for y in [200.0,300.0]:
		var path:=PackedVector2Array()
		for i in 33:path.append(Vector2(332.0+168*i/32.0,y))
		paths.append(path)
	flow.publish_paths(paths,[],Vector2(200,200))
	var input_path:=PackedVector2Array()
	for i in 33:input_path.append(Vector2(400,180.0+40*i/32.0))
	flow.input_paths.clear();flow.input_paths.append(input_path);flow._publish_input()
	flow.input_crests.multimesh.set_instance_custom_data(0,Color(0,0,0,1))
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
	check(gold>10 and gold_outside==0,"Only the separate induced-input layer renders source-local gold pixels")
	check(ordinary>10,"The denser combined-current samples retain their pale color")
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
	for step in 81:
		game.world.time=10+step*.02;game.free_camera=currents.sources(game.world.seed_value,game.world.time)[0].p;game._update_world(1)
	await settle()
	var shown:=root.get_texture().get_image()

	var active: MultiMeshInstance2D=game.flow_view.crests if game.flow_view.use_crests else game.flow_view.streamers
	var input: MultiMeshInstance2D=game.flow_view.input_streamers if game.flow_view.use_crests else game.flow_view.input_crests
	input.hide()
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
			for marker in game.flow_view.visual_sources.values():
				var event: Dictionary=marker.source
				if marker.opacity>.001 and game.Simulation.Medium.offset(event.p,at).length()<=event.radius+16/game.zoom:local=true;break
			if not local:distant_pixels+=1
	check(source_pixels>30 and distant_pixels==0,"Actual dim portrait scene shows the enlarged, input-only gold footprint at the widest playable view")
	check(active.multimesh.visible_instance_count<=game.flow_view.MAX_CRESTS,"Visible crest samples stay inside their bounded budget")
	if OS.has_environment("PRIMORDIA_CURRENT_PORTRAIT_CAPTURE"):shown.save_png(OS.get_environment("PRIMORDIA_CURRENT_PORTRAIT_CAPTURE"))
	if OS.has_environment("PRIMORDIA_CURRENT_PORTRAIT_JPEG"):shown.save_jpg(OS.get_environment("PRIMORDIA_CURRENT_PORTRAIT_JPEG"),.87)
	print("CURRENT_PORTRAIT source_pixels=%d distant_pixels=%d curves=%d input_curves=%d" % [source_pixels,distant_pixels,active.multimesh.visible_instance_count,input.multimesh.visible_instance_count])
	input.show()
	await current_geometry(game)
	await induced_fades(game)
	await current_style_controls(game)
	game.queue_free();await process_frame
	print("FEEDBACK VISUAL GPU: %d assertions, %d failures; gold=%d outside=%d ordinary=%d GPU=%s" % [assertions,failures,gold,gold_outside,ordinary,RenderingServer.get_video_adapter_name()])
	if FileAccess.file_exists(preferences_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
	quit(0 if failures==0 else 1)


func single_crest(flow,texture: Texture2D,sources: PackedVector4Array) -> void:
	flow.streamers.hide();flow.crests.show();flow.input_crests.hide();flow.input_streamers.hide()
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
			check(game.flow_view.use_crests==waves and game.flow_view.crests.visible==waves and game.flow_view.streamers.visible!=waves,"Actual Pause pointer switches mutually exclusive base current renderers")
			check(game.flow_view.input_streamers.visible==waves and game.flow_view.input_crests.visible!=waves,"Gold input switches to the opposite style on desktop and touch")
			var restored=preload("res://scripts/preferences.gd").new();restored.path=path;restored.load_settings()
			check(restored.current_style==("crests" if waves else "streamlines"),"Current display preference survives reload")
	game.preferences.persist=false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func current_geometry(game) -> void:
	var flow=game.flow_view
	for style in ["crests","streamlines"]:
		game.set_current_style(style)
		for step in 61:
			game.world.time=10+step*.02;game._update_world(1)
		check(flow.drawn_paths.size()>3,"Both current styles retain several real-field curves")
		if OS.has_environment("PRIMORDIA_CURRENT_STYLE_CAPTURE"):
			await settle()
			root.get_texture().get_image().save_jpg(OS.get_environment("PRIMORDIA_CURRENT_STYLE_CAPTURE")+"-"+style+".jpg",.87)
		for offset in [0.0,.02,.06]:
			game.world.time=11.2+offset;game._update_world(1)
			var shown: Array[PackedVector2Array]=[]
			for input in [false,true]:
				var paths: Array[PackedVector2Array]=flow.input_paths if input else flow.drawn_paths
				var samples: Array[Dictionary]=flow.input_samples if input else flow.drawn_samples
				var baselines: Array[Vector2]=flow.input_baselines if input else flow.curve_baselines
				for row in paths.size():
					var path: PackedVector2Array=paths[row]
					var delta: Vector2=flow.Medium.offset(baselines[row],samples[row].track.p)
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
			if crossings>0:print("CROSSINGS ",style," offset=",offset," count=",crossings)
			check(crossings==0,"Independent segment inspection finds no crossing at or between geometry refreshes in "+style)
		game.world.time=12;game._update_world(1)
		var moving: Array=flow.drawn_samples.filter(func(sample):return not sample.retiring and not sample.blocked)
		if not moving.is_empty():
			var track: Dictionary=moving[0].track
			var before: Vector2=track.p;var velocity: Vector2=flow._display_flow(before)
			game.world.time=12.02;game._update_world(1)
			var displacement: Vector2=flow.Medium.offset(before,track.p)
			check(displacement.distance_to(velocity*.02)<.05,"Visible centers move at actual local current speed, independent of source migration")


func induced_fades(game) -> void:
	var flow=game.flow_view
	# Opposed ambient and input directions distinguish input-only from total flow
	# and from source migration. No real pond is mutated by this fixture.
	var constant: Array=[{"p":Vector2(500,500),"radius":400.0,"heading":Vector2.RIGHT,"strength":20.0,"kind":"directional","spin":1.0,"envelope":1.0}]
	flow.input_events=constant
	flow.input_velocity=flow.Currents.raster_forcing(constant);flow.previous_input_velocity=flow.input_velocity;flow.input_mix=1
	flow.cached_velocity.fill(Vector2(0,20));flow.previous_velocity.fill(Vector2(0,20))
	var gold_path: PackedVector2Array=flow._curve(Vector2(500,500),100,false,true)
	var pale_path: PackedVector2Array=flow._curve(Vector2(500,500),100,false,false)
	check(absf(gold_path[-1].y-gold_path[0].y)<.01 and gold_path[-1].x>gold_path[0].x+20 and absf(pale_path[-1].x-pale_path[0].x)<.01 and pale_path[-1].y>pale_path[0].y+20,"Gold traces induced forcing alone even when total water points elsewhere")
	flow.visual_sources.clear();flow.source_clock=100
	var first: PackedVector4Array=flow._source_markers(constant,100.1)
	var next: PackedVector4Array=flow._source_markers(constant,100.2)
	var leaving: PackedVector4Array=flow._source_markers([],100.3)
	check(first[0].z==400 and first[0].w>0 and first[0].w<next[0].w and leaving[0].w>0 and leaving[0].w<next[0].w,"Full-radius input masks ramp up and survive source disappearance with a gradual fade")
	var seeds: Array[Color]=flow._dense_seeds(constant,Vector2(500,500),Vector2(600,450))
	check(seeds.any(func(seed):return Vector2(seed.r,seed.g).distance_to(Vector2(500,500))>400*.5),"Pale local-current density covers the full induced area, beyond the former small gold core")
	flow.crest_tracks.clear();flow.curve_style=flow.use_crests;flow.field_speed=20
	var now:=200.0
	game.world.time=now;flow._build_curves(game.world,constant,Vector2(500,500),Vector2(600,450),3)
	flow._move_drawn(now+.2,Vector2(500,500))
	var held: Dictionary={}
	for sample in flow.crest_tracks.values():
		if sample.opacity>0:held[sample.id]=sample.opacity
	game.world.time=now+.21;flow.input_events=[]
	flow.input_velocity.fill(Vector2.ZERO);flow.previous_input_velocity=flow.input_velocity;flow.input_mix=1
	flow._build_curves(game.world,[],Vector2(500,500),Vector2(600,450),3)
	flow._move_drawn(now+.21,Vector2(500,500))
	var fading:=0
	for sample in flow.crest_tracks.values():
		if sample.dense and held.has(sample.id):
			if sample.opacity>0 and sample.opacity<held[sample.id]:fading+=1
	check(fading>0,"Visible dense samples retain their identity and nonzero alpha when the source disappears")
	var matching:=true
	for input in [false,true]:
		var samples: Array[Dictionary]=flow.input_samples if input else flow.drawn_samples
		var batch: MultiMeshInstance2D
		if input:batch=flow.input_streamers if flow.use_crests else flow.input_crests
		else:batch=flow.crests if flow.use_crests else flow.streamers
		for row in samples.size():
			if absf(batch.multimesh.get_instance_custom_data(row).a-float(samples[row].opacity))>.002:matching=false
	check(matching,"Actual GPU batches receive each persistent curve's current fade opacity")
	var prior: Dictionary={}
	for sample in flow.crest_tracks.values():prior[sample.id]=sample.opacity
	game.world.time=now+.25;flow._build_curves(game.world,[],Vector2(500,500),Vector2(600,450),3);flow._move_drawn(now+.25,Vector2(500,500))
	var jump:=0.0
	for sample in flow.crest_tracks.values():
		if prior.has(sample.id):jump=maxf(jump,absf(sample.opacity-float(prior[sample.id])))
	check(jump<=.101,"Four-hundredths of a second cannot cause a visible opacity step larger than the fade rate")


func changed_pixels(before: Image,after: Image,area: Rect2i) -> int:
	var count:=0
	var clipped:=area.intersection(Rect2i(Vector2i.ZERO,after.get_size()))
	for y in range(clipped.position.y,clipped.end.y):
		for x in range(clipped.position.x,clipped.end.x):
			var a:=before.get_pixel(x,y);var b:=after.get_pixel(x,y)
			if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>.04:count+=1
	return count

func resource_warning_pixels(game) -> void:
	var cell=game.world.player
	game.world.evolution.sandbox=true;game.preferences.show_instinct=false;game.show_senses=false
	game.cell_ui.reset();game.notice="Existing notice";game.notice_timer=0
	var original_time: float=game.world.time
	var original_rng: int=game.world.rng.state
	for mobile in [false,true]:
		root.size=Vector2i(412,915) if mobile else Vector2i(1200,900)
		game.touch_zoom.enabled=mobile;game.touch_zoom.pixels=1
		game.camera_has_pose=false;game.camera_followed_id=-1;game.camera_motion.cancel()
		for depth in [true,false]:
			game.membrane_depth=depth
			for state in [{"energy":2.0,"health":100.0},{"energy":50.0,"health":15.0},{"energy":0.0,"health":15.0},{"energy":50.0,"health":100.0}]:
				cell.energy=state.energy;cell.health=state.health
				game.ui_time=0;game._update_world(1);game.cell_ui.sync(0);await settle()
				var quiet:=root.get_texture().get_image()
				game.ui_time=.8;game._update_world(1);game.cell_ui.sync(0);await settle()
				var bright:=root.get_texture().get_image()
				if state.energy==0 and depth and OS.has_environment("PRIMORDIA_RESOURCE_WARNING_CAPTURE"):
					var path: String=OS.get_environment("PRIMORDIA_RESOURCE_WARNING_CAPTURE")+("-mobile" if mobile else "-desktop")
					bright.save_jpg(path+"-bright.jpg",.9);quiet.save_jpg(path+"-quiet.jpg",.9)
				var interior=game.cell_ui.interior
				var transform: Transform2D=root.get_final_transform()*interior.get_global_transform_with_canvas()
				var center: Vector2=transform*interior.anchors.atp
				var extent: int=ceili(maxf(interior.atp_size*absf(transform.get_scale().x)*1.6+3,14*game.cell_ui.ui_scale()))
				var atp_pixels:=changed_pixels(quiet,bright,Rect2i(Vector2i(center)-Vector2i.ONE*extent,Vector2i.ONE*extent*2))
				check((atp_pixels>3 if state.energy<10 else atp_pixels==0),"ATP warning is independently visible, including empty ATP, on mobile=%s shaded=%s ATP=%s pixels=%s" % [mobile,depth,state.energy,atp_pixels])
				var view=game.views[cell.id]
				var body_transform: Transform2D=root.get_final_transform()*view.get_global_transform_with_canvas()
				var rim_pixels:=0
				for point in cell.membrane.outline():
					var edge: Vector2=body_transform*(point*.955)
					rim_pixels+=changed_pixels(quiet,bright,Rect2i(Vector2i(edge)-Vector2i(3,3),Vector2i(6,6)))
				check((rim_pixels>10 if state.health<30 else rim_pixels==0),"Only critically damaged membranes blink along the actual outline on mobile=%s shaded=%s health=%s pixels=%s" % [mobile,depth,state.health,rim_pixels])
				check(game.notice=="Existing notice","Resource warnings do not replace the current notice with a critical-resource message")
				check(cell.energy==state.energy and cell.health==state.health and game.world.time==original_time and game.world.rng.state==original_rng,"Blinking is presentation-only with unchanged ATP, health, world time and RNG")
				if state.energy==0:check(interior.atp_size==0,"Warning around an empty ATP sac never invents resource fill")
			cell.dead=true;cell.health=0;cell.energy=0
			game._update_world(1);await settle()
			check(not game.views.has(cell.id) and not game.cell_ui.interior.visible,"A dead cell does not continue resource warning cues")
			cell.dead=false;cell.health=100;cell.energy=50
	game.membrane_depth=true;game.touch_zoom.enabled=false
