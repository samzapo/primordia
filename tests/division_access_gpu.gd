extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Sac=preload("res://scripts/toxin_sac.gd")
var assertions:=0
var failures:=0
func check(ok: bool,why: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	# UI scenes model a browser presenter. The explicit resident shader fixture
	# below still owns real hardware; do not asynchronously start another pond.
	OS.set_environment("PRIMORDIA_PARTICLES","cpu")
	print("DIVISION_ACCESS_GPU ",RenderingServer.get_video_adapter_name())
	if "--controls-only" in OS.get_cmdline_user_args():
		root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(640,400)
		await division_controls()
		await merge_controls()
		print("DIVISION CONTROLS GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1);return
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(640,400)
	var panel:=Control.new();root.add_child(panel)
	var buttons: Array=[]
	for i in 3:
		var button=preload("res://scripts/cell_action.gd").new()
		button.position=Vector2(30+i*100,30);button.size=Vector2(80,80);button.symbol="Divide"
		button.radial_progress=[.5,1.0,1.0][i];button.progress_ready=i==2
		panel.add_child(button);buttons.append(button)
	var canvas:=Node2D.new();root.add_child(canvas)
	canvas.draw.connect(func():
		var art=preload("res://scripts/visuals.gd")
		art.icon(canvas,Vector2(100,230),"toxin_sac",0,2,0,"graze",0,true,0,false,0)
		art.icon(canvas,Vector2(250,230),"toxin_sac",0,2,0,"graze",0,true,0,false,1))
	canvas.queue_redraw()
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	for i in 3:
		var color:=image.get_pixel(108+i*100,70)
		check(color.get_luminance()>.35,"Actual division-ring pixels are visible")
	var amber:=image.get_pixel(208,70);var green:=image.get_pixel(308,70)
	check(amber.r>amber.b*1.2 and green.g>green.r*1.1,"Full blocked and ready rings have distinct actual amber and green pixels")
	var pink: Array=[0,0]
	for i in 2:
		for x in range(-22,23):
			for y in range(-22,23):
				var color:=image.get_pixel(100+i*150+x,230+y)
				if color.r>.8 and color.g<.4:pink[i]+=1
	check(pink[1]>pink[0]*3,"A filled toxin sac visibly has more pink stored contents")
	panel.queue_free();canvas.queue_free();await process_frame
	# Free tags and subunits use the authored decay in the real resident shader.
	var data:=PackedFloat32Array()
	for i in 256:data.append_array(PackedFloat32Array([100+(i%16)*50,100+(i/16)*50,0,0,0,0,0,11+i%2,7,1,1,0]))
	var acid:=PackedFloat32Array();acid.resize(2560)
	var gpu=GPU.new();gpu.configure_interactions("chemistry");gpu.configure_exchange();gpu.configure_perception();gpu.configure_chemistry(acid,390071);gpu.initialize(data,Fixture.flow())
	var ready: Array=await gpu.ready
	check(ready[0],"Real resident hardware initializes the shortened pore lifetime: "+str(ready))
	if not ready[0]:gpu.close();await gpu.closed;quit(1);return
	gpu.advance(1,0)
	var receipt: Dictionary=gpu.exchange_sync([],[],[],[],{"feeding":false,"projection":false,"exposure":false})
	gpu.snapshot()
	var actual: PackedFloat32Array=await gpu.snapshot_ready
	var survivors: Array=[0,0]
	for i in 256:
		if actual[i*12+7]>=0:survivors[i%2]+=1
	for i in 2:check(survivors[i]>35 and survivors[i]<80,"Free pore parcels disperse substantially within one second on the resident GPU")
	check(absf(float(receipt.chemistry.loss)-(256-survivors[0]-survivors[1]))<.001,"Every dispersed free-pore unit is accounted as material outflow")
	gpu.close();await gpu.closed
	# Existing membrane-bound pieces keep assembling after longer than free lifetime.
	var cell=Sim.Cell.new(901);cell.add_organ("feeding",0,"graze",false)
	var surface=preload("res://scripts/surface_chemistry.gd")
	surface.bind(cell,11,.03,0);surface.bind(cell,12,.0375,0);surface.advance(cell,3)
	check(cell.surface_complexes.size()==1 and cell.surface_complexes[0].units==1,"Bound assembly survives while unbound packets decay")
	for i in 3:surface.bind(cell,12,.0375,0)
	var hp: float=cell.health;surface.advance(cell,.1)
	check(cell.health<hp,"Previously bound pieces still finish a damaging pore")
	await division_controls()
	await merge_controls()
	print("DIVISION ACCESS GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)


func settle_ui() -> void:
	for i in 6:await process_frame

func press_ui(button: Button) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.position=button.get_global_rect().get_center();event.global_position=event.position
	root.push_input(event,true)
	var release: InputEventMouseButton=event.duplicate();release.pressed=false;root.push_input(release,true)
	await settle_ui()

func division_controls() -> void:
	print("CONTROL_STAGE division")
	var game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false
	var path: String="user://division-controls-%s-%s.cfg" % [OS.get_process_id(),Time.get_ticks_usec()]
	game.preferences.path=path;root.add_child(game);game.set_process(false);game.set_physics_process(false)
	game.music.enabled=false;game.music.player.stop();game.world.cells=[game.world.player];game.world.habitat_geometry.enabled=false
	game.world.evolution.sandbox=true;game.world.server_mode=true;game.build_open=true;game.notice_timer=0;game.manual_zoom=1.5
	game.world.player.target=Vector2.RIGHT;game.world.player.state="SEEKING LIGHT"
	check(game.world.player.automatic_division,"New sessions start with Auto divide enabled")
	check(game.preferences.show_instinct and game.flow_view.use_crests,"New sessions start with intent and Wave crests enabled")
	for mobile in [false,true]:
		game.world.player.automatic_division=true;game.world.player.division_requested=false
		root.size=Vector2i(412,915) if mobile else Vector2i(1280,800)
		game.touch_zoom.enabled=mobile;game.touch_zoom.pixels=1;game._layout();game._update_world(1)
		game.preferences.show_instinct=true;game.cell_ui.open_context({"kind":"nucleus"});await settle_ui()
		var choices: Array=game.cell_ui.choices.filter(func(choice):return choice.symbol=="Instinct")
		check(choices.size()==1 and choices[0].selected,"Instinct appears as an active direct toggle on both platforms")
		var view: Node2D=game.views[game.world.player.id]
		var point:=root.get_final_transform()*(view.get_global_transform_with_canvas()*Vector2(game.world.player.extent()+14,0).rotated(-game.world.player.angle))
		var on:=root.get_texture().get_image()
		await press_ui(choices[0]);game._update_world(1);await settle_ui()
		var off:=root.get_texture().get_image()
		var pixels:=0
		for y in range(maxi(0,int(point.y)-12),mini(off.get_height(),int(point.y)+12)):
			for x in range(maxi(0,int(point.x)-12),mini(off.get_width(),int(point.x)+12)):
				if on.get_pixel(x,y).get_luminance()>off.get_pixel(x,y).get_luminance()+.08:pixels+=1
		check(not game.preferences.show_instinct and not choices[0].selected and pixels>2,"Actual pointer toggles off the rendered intent arrow: mobile=%s pixels=%s" % [mobile,pixels])
		await press_ui(choices[0]);game.cell_ui.close_context();game.notice_timer=0
		# A real Xvfb/display pointer can hover the cell after dismissal. The
		# empty-water intent readout must be tested outside all anatomy/choices.
		var water:=InputEventMouseMotion.new();water.position=Vector2(20,200);water.global_position=water.position
		Input.warp_mouse(water.position);root.push_input(water,true);await settle_ui();game.cell_ui.sync(0)
		check(game.cell_ui.get_global_mouse_position().distance_to(water.position)<3,"Fixture places the actual display pointer over empty water")
		check(game.preferences.show_instinct and game.cell_ui.tip_box.visible and game.cell_ui.tip.text.begins_with("Instinct"),"The enabled intent readout survives menu dismissal over empty water: mobile=%s cursor=%s text=%s" % [mobile,game.cell_ui.get_global_mouse_position(),game.cell_ui.tip.text])
		var saved=preload("res://scripts/preferences.gd").new();saved.path=path;saved.load_settings()
		check(saved.show_instinct,"Intent toggle is remembered by saved preferences")
		game.cell_ui.open_context({"kind":"bud"});await settle_ui()
		await press_ui(game.cell_ui.choices[0])
		check(game.cell_ui.context.kind=="division" and game.cell_ui.choices.map(func(choice):return choice.caption)==["Mitosis","Auto mitosis","Budding","Auto budding","Back"],"Divide exposes two direct modes and their independent automatic toggles")
		check(game.cell_ui.choices[1].selected and game.cell_ui.choices[3].selected,"Both automatic reproduction modes start enabled")
		await press_ui(game.cell_ui.choices[1])
		check(not game.world.player.automatic_division and not game.cell_ui.choices[1].selected,"Pointer switches automatic mitosis off")
		await press_ui(game.cell_ui.choices[1])
		check(game.world.player.automatic_division and game.cell_ui.choices[1].selected,"Pointer switches automatic mitosis on")
		game.world.player.biomass=200;game.world.player.energy=100;game.world.player.reproduction_retry_at=0
		var parent=game.world.player
		var before: int=game.world.cells.size()
		await press_ui(game.cell_ui.choices[2]);game._update_world(1);await settle_ui()
		check(game.world.cells.size()==before+1 and parent.biomass==158 and not parent.division_requested,"Actual Budding pointer commits one minimal daughter without a reserve queue")
		game.cell_ui.open_context({"kind":"division"});await settle_ui()
		check(not game.cell_ui.choices[0].affordable and not game.cell_ui.choices[2].affordable,"Both manual modes show the same saved one-minute cooldown")
	game.queue_free();await process_frame
	if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func merge_world_click(game,at: Vector2,mobile: bool) -> void:
	if mobile:
		var down:=InputEventScreenTouch.new();down.index=0;down.position=at;down.pressed=true;root.push_input(down,true)
		var up: InputEventScreenTouch=down.duplicate();up.pressed=false;root.push_input(up,true)
	else:
		var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.position=at;down.global_position=at;down.pressed=true;root.push_input(down,true)
		var up: InputEventMouseButton=down.duplicate();up.pressed=false;root.push_input(up,true)
	await settle_ui()

func merge_settle_camera(game) -> void:
	for i in 42:
		game.camera_motion.advance(1.0/60);game._update_world(1);game.cell_ui.sync(0)
		await process_frame
	await settle_ui()

func merge_chroma(image: Image,at: Vector2) -> float:
	var total:=0.0;var count:=0
	for y in range(maxi(0,int(at.y)-5),mini(image.get_height(),int(at.y)+6)):
		for x in range(maxi(0,int(at.x)-5),mini(image.get_width(),int(at.x)+6)):
			var c:=image.get_pixel(x,y);total+=maxf(c.r,maxf(c.g,c.b))-minf(c.r,minf(c.g,c.b));count+=1
	return total/maxi(1,count)

func merge_controls() -> void:
	print("CONTROL_STAGE merge")
	for mobile in [false,true]:
		root.size=Vector2i(412,915) if mobile else Vector2i(1280,800)
		print("MERGE_STAGE begin ",mobile)
		var game=load("res://scenes/pond.tscn").instantiate();game.use_particle_pool=false;game.preferences.persist=false;game.preferences.path="user://merge-controls-%s-%s.cfg" % [OS.get_process_id(),Time.get_ticks_usec()]
		root.add_child(game);game.set_process(false);game.set_physics_process(false)
		game.music.enabled=false;game.music.player.stop();game.habitat_view.hide()
		var sim=game.world;sim.server_mode=true;sim.cells=[sim.player];sim.particles=[];sim.grid.clear();sim.habitat_geometry.enabled=false;sim.evolution.sandbox=true
		var cell=sim.player;cell.position=Vector2(1200,1200);cell.previous_position=cell.position;cell.angle=0;cell.previous_angle=0
		cell.body=80;cell.biomass=20;cell.organs.clear();cell.update_geometry();cell.add_organ("feeding",0,"graze",false)
		var bodies: Array=[]
		for item in [[900,Vector2(160,-20),cell.lineage_id()],[901,Vector2(-160,-20),cell.lineage_id()],[902,Vector2(0,160),902]]:
			var other=Sim.Cell.new(item[0],cell.position+item[1]);other.previous_position=other.position;other.lineage=item[2];other.body=60;other.biomass=10;other.update_geometry()
			sim.cells.append(other);bodies.append(other)
			if other.lineage_id()==cell.lineage_id():sim.lineage.register(other,cell.id,1,"living",sim.time)
		var trace: Dictionary=sim._emit_pheromone(bodies[0]);trace.p=cell.organ_position(cell.organs[0]);sim.grid.rebuild(sim.particles);cell.behavior["family_cues"]=sim._family_reports(cell)
		var commands: Array=[];sim.remote_client=true;sim.command_sink=func(action,args):commands.append({"action":action,"id":int(args.get("id",-1))})
		game.merge_available={"cell":cell.id,"targets":sim.FamilyMerging.candidates(sim,cell)}
		game.touch_zoom.enabled=mobile;game.touch_zoom.pixels=1;game.perception="interoception" if mobile else "exteroception"
		var before_perception: String=game.perception
		game.manual_zoom=8;game.camera_zoom=8;game.camera_locked=true;game.camera_offset=Vector2.ZERO;game.focus_animating=false
		game._layout();game._update_world(1);game.cell_ui.open_context({"kind":"lineage"});await settle_ui()
		var before: Vector2=game.render_camera;var before_zoom: float=game.zoom
		await press_ui(game.cell_ui.family_picker.merge_button)
		check(game.merge_selecting() and not game.cell_ui.family_picker.visible and game.perception=="exteroception","Actual Family Merge pointer opens nearby world selection on mobile/desktop")
		check(Sim.Medium.offset(before,game.render_camera).length()<.001 and absf(game.zoom-before_zoom)<.001,"Merge entry starts at the displayed camera pose without a jump")
		await merge_settle_camera(game)
		print("MERGE_STAGE neighborhood ",mobile)
		check(not game.camera_motion.active and game.zoom<before_zoom and game.camera_locked,"Merge smoothly zooms out to the recipient neighborhood")
		check(game.merge_candidates.keys()==[900] and game.cell_ui.merge_cancel_button.visible,"Only detected relatives are selectable and Cancel is reachable")
		check(not game.cell_ui.merge_cancel_button.get_global_rect().intersects(game.cell_ui.tip_box.get_global_rect()),"Cancel and merge instructions never overlap on either platform")
		var original_position: Vector2=bodies[0].position
		bodies[0].position=cell.position+Vector2(20,0);bodies[0].previous_position=bodies[0].position
		game._update_world(1)
		check(game._merge_at(game.views[900].get_global_transform_with_canvas().origin)==900,"An eligible relative remains clickable where its body overlaps the receiving cell")
		bodies[0].position=original_position;bodies[0].previous_position=original_position;game._update_world(1)
		check(game.touch_zoom.perception_button.text=="Internal" and game.perception_menu_button.text=="Internal [I]","Both platform controls use the new plain view names")
		var image:=root.get_texture().get_image()
		var values: Array=[]
		for body in bodies:
			var view=game.views[body.id]
			var at: Vector2=root.get_final_transform()*(view.get_global_transform_with_canvas()*Vector2(0,-body.radius*.3))
			values.append(merge_chroma(image,at))
		check(values[0]>.04 and values[1]<.012 and values[2]<.012,"Actual mask keeps detected kin colorful and makes other cells grey: "+str(values))
		if OS.has_environment("PRIMORDIA_MERGE_CAPTURE"):image.save_jpg(OS.get_environment("PRIMORDIA_MERGE_CAPTURE")+("-mobile.jpg" if mobile else "-desktop.jpg"),.87)
		for body in [bodies[1],bodies[2]]:
			await merge_world_click(game,game.views[body.id].get_global_transform_with_canvas().origin,mobile)
			check(game.merge_selecting() and commands.is_empty() and sim.player==cell,"Click/tap on a dim cell neither merges nor switches control")
		await merge_world_click(game,game.cell_ui.merge_cancel_button.get_global_rect().get_center(),mobile)
		check(not game.merge_selecting() and game.perception==before_perception and game.manual_zoom==8 and commands.is_empty(),"Cancel restores the previous view without a command or resource mutation")
		await merge_settle_camera(game)
		game.cell_ui.open_context({"kind":"lineage"});await settle_ui();await press_ui(game.cell_ui.family_picker.merge_button);await merge_settle_camera(game)
		game.merge_available.targets[900]=sim.time;game._update_world(1);game.cell_ui.sync(0)
		await merge_world_click(game,game.views[900].get_global_transform_with_canvas().origin,mobile)
		check(game.merge_selecting() and commands.is_empty() and not game.merge_candidates.has(900),"A pheromone expiry removes click permission while the view stays open")
		game.merge_available.targets[900]=sim.time+8;game._update_world(1);await settle_ui()
		await merge_world_click(game,game.views[900].get_global_transform_with_canvas().origin,mobile)
		check(not game.merge_selecting() and commands==[{"action":"merge","id":900}] and sim.player==cell,"A direct eligible click/tap sends exactly one merge, never a family switch")
		game.queue_free();await process_frame
