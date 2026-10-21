extends Node
## Isolated real-client rendering/replay diagnostic; never connects to a pond.
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
class Client:
	extends "res://scripts/network/network_client.gd"
	func _load_identity() -> void:pass
	func _save_identity() -> void:pass
	func _poll_network() -> void:pass
	var sent: Array=[]
	func _send(value: Dictionary) -> void:
		sent.append(value.duplicate(true))
		if sent.size()>128:sent.pop_front()
var game
var wire: Array=[]
var elapsed:=0.0
var initialized_at:=0
var next_snapshot:=0.0
var measure_start:=0.0
var started:=false
var finished:=false
var trace
var settings: Dictionary={}
var cache_checks: Array=[]
var input_checks: Array=[]
var check_phase:=0
var cached_view_refs: Array=[]
func option(key: String,fallback: String) -> String:
	if OS.has_feature("web"):
		var value=JavaScriptBridge.eval("new URLSearchParams(location.search).get("+JSON.stringify(key)+")")
		return str(value) if value!=null else fallback
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"+key+"="):return arg.trim_prefix("--"+key+"=")
	return fallback
func _ready() -> void:
	settings={"cells":int(option("cells","48")),"particles":int(option("particles","700")),"zoom":float(option("zoom","0.8")),"case":option("case","all"),"seconds":float(option("seconds","8"))}
	assert(settings.cells>=1 and settings.cells<=64 and settings.zoom>=.8)
	game=Client.new();add_child(game);game.login.hide()
	game.preferences.persist=false;game.archive.persist=false
	game.music.enabled=option("music","off")=="on"
	game.controls.touch_enabled=true
	if settings.case in ["controls-check","placement-check"]:game.connected=true
	game.epoch=1;game.camera_seen_world=true;game.camera_initialized=true
	game.manual_zoom=settings.zoom;game.camera_zoom=settings.zoom;game.camera_locked=true
	if settings.case=="no-flow":game.flow_streamers=false;game.flow_wakes=false
	if settings.case=="no-post":game.microscope_layer.hide()
	if settings.case=="no-light":game.light_layer.hide()
	if settings.case=="full-water":game.water_cache_enabled=false
	var sim=Sim.new(9701,0,false);sim.server_mode=true;sim.cells.clear();sim.particles.clear()
	var center:=Vector2(2048,1280)
	for i in settings.cells:
		var cell=Sim.Cell.new(i,center+Vector2((i%8)-3,int(i/8)-2)*210)
		if i==0:cell.position=center
		cell.previous_position=cell.position;cell.lineage=i/12;cell.body=80;cell.biomass=180;cell.energy=120
		var kinds: Array=[["hunting","propulsion","proboscis","feeding","mitochondrion","protection"],["photosynthesis","photosynthesis","mitochondrion","protection"],["feeding","cilia","mitochondrion","regenerative"]][i%3]
		for kind in kinds:cell.add_organ(kind,cell.organs.size()*1.2,"graze",false)
		cell.chemistry.emit("food",120 if i%3==0 else 15,Vector2.ZERO,-1,-1,100)
		cell.update_geometry();sim.cells.append(cell)
	sim.player=sim.cells[0];sim.lineage=sim._family_ledger(sim.player);sim.evolution=sim.lineage.progression
	sim.fluid.velocity.fill(Vector2(28,12));sim.environment={"light":.8}
	sim.habitat_geometry=Sim.Habitat.new(9701,sim.cells)
	game.world.habitat_geometry=sim.habitat_geometry;game.habitat_view.configure(sim.habitat_geometry)
	var packets:=PackedByteArray();packets.resize(settings.particles*32)
	var random:=RandomNumberGenerator.new();random.seed=9701
	for i in settings.particles:
		var at:=center+Vector2(random.randf_range(-1300,1300),random.randf_range(-1900,1900))
		for k in 6:packets.encode_float(i*32+k*4,[at.x,at.y,random.randf()*TAU,i%Sim.SPECIES_COUNT,.6,5][k])
		packets.encode_u32(i*32+24,i)
	var overrides: Dictionary={}
	for cell in sim.cells:
		overrides[cell.chemistry.get_instance_id()]={"particles":[],"vacuoles":[],"presentation_totals":{"material":cell.chemistry.material(),"storage":cell.chemistry.storage_used(),"potential":cell.chemistry.potential(),"raw_fuel":cell.chemistry.raw_fuel(),"packets":cell.chemistry.particle_count()}}
	for index in 8:
		for cell in sim.cells:
			cell.render_revision=index if settings.case!="stable-shapes" else 0;cell.age=index*.1
		var frame={"kind":"snapshot","world_id":"isolated-render-fixture","epoch":1,"tick":index,"time":1000+index*.1,"edit":0,"sequence":0,
		 "graph":Codec.new().capture({"cells":sim.cells,"player":sim.player,"focus":sim.player,"lineage":sim.lineage,"evolution":sim.evolution,"investment":sim.investment},overrides,true,2),
		 "particles":packets,"flow":sim.fluid.velocity,"acid":sim.acidity.values,"sounds":[],"sound_sequence":0,"sparks":sim.reaction_sparks,"perception":"exteroception","census":{}}
		wire.append(var_to_bytes(frame))
	game._layout();set_process(true);initialized_at=Time.get_ticks_usec()
	if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaRenderReady=true")
func _process(dt: float) -> void:
	if finished:return
	elapsed=(Time.get_ticks_usec()-initialized_at)/1000000.0
	if elapsed>=next_snapshot:
		var at:=Time.get_ticks_usec()
		var message: Dictionary=bytes_to_var(wire[int(next_snapshot*10)%wire.size()])
		message.tick=floori(elapsed*10);message.time=1000+elapsed;message.presentation_usec=elapsed*1000000
		game._receive_snapshot(message)
		if trace!=null:trace.work("wire_decode",Time.get_ticks_usec()-at)
		next_snapshot+=floor((elapsed-next_snapshot)/.1+1)*.1
	if settings.case=="no-body-grid":game.network_particles.batch.material.set_shader_parameter("use_body_grid",false)
	if settings.case=="no-raster":
		for view in game.views.values():view.raster_enabled=false
	if settings.case=="placement-check" and elapsed>4 and check_phase==0:
		check_phase=1;_check_placement()
	if settings.case=="raster-check":
		if elapsed>4 and check_phase==0:
			cache_checks.append(game.views.values().any(func(view):return view.raster_active))
			cached_view_refs=game.views.values().map(func(view):return weakref(view))
			game.manual_zoom=4;check_phase=1
		elif elapsed>5 and check_phase==1:
			cache_checks.append(game.views.values().all(func(view):return not view.raster_active and view.body_ink.get_parent()==view) and cached_view_refs.filter(func(ref):return is_instance_valid(ref.get_ref())).size()<=game.views.size())
			game.manual_zoom=.8;check_phase=2
		elif elapsed>6 and check_phase==2:
			cache_checks.append(game.views.values().any(func(view):return view.raster_active))
			game.perception="interoception";check_phase=3
		elif elapsed>7 and check_phase==3:
			var selected=game.views.get(game.world.player.id)
			cache_checks.append(selected!=null and not selected.raster_active and selected.body_ink.get_parent()==selected and selected.cytoplasm.visible)
			game.perception="exteroception";check_phase=4
	if elapsed>=3 and not started:
		started=true;measure_start=elapsed;trace=preload("res://scripts/frame_trace.gd").new();game.frame_trace=trace;trace.start(game)
	if started and elapsed-measure_start>=settings.seconds:
		finished=true;trace.stop();game.frame_trace=null
		if settings.case=="placement-check":assert(input_checks.size()>=10 and input_checks.all(func(ok):return ok),"Local placement/animation and menu checks")
		if settings.case=="raster-check":assert(cache_checks.size()==4 and cache_checks.all(func(ok):return ok),"Small-cell cache must exit cleanly for zoom/internal views")
		var result={"settings":settings,"adapter":RenderingServer.get_video_adapter_name(),"device":RenderingServer.get_video_adapter_vendor(),"cache_checks":cache_checks,"input_checks":input_checks,"viewport":str(game.get_viewport_rect().size),"canvas_scale":game.detail_canvas_scale,"dpr":game.detail_pixel_ratio,"views":game.views.values().map(func(view):return {"radius":view.cell.radius,"css_radius":view.cell.radius*game.zoom*game.detail_canvas_scale/game.detail_pixel_ratio,"small":view.simple_view,"raster":view.raster_active}),"rows":trace.rows}
		if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaRenderProfile="+JSON.stringify(result))
		else:
			var file:=FileAccess.open(option("output","res://build/network-render.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify(result));file.close();get_tree().quit()

func _check_placement() -> void:
 var cell=game.world.player
 var view=game.views[cell.id]
 var count: int=cell.organs.size()
 var heading: float=view.rotation
 view.rotation=cell.angle+.7 # Deliberately different from the latest server angle.
 var angle:=.25
 var local: Vector2=cell.local_point(angle)
 var screen: Vector2=game.world_layer.to_global(view.position+local.rotated(view.rotation))
 input_checks.append(game._player_relative(screen).rotated(-game._player_heading()).distance_to(local)<.001)
 game.build_open=true;game.selected=Sim.KINDS.find("photosynthesis")
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=screen
 game._unhandled_input(click)
 input_checks.append(game.inflight.get("action","")=="install")
 input_checks.append(absf(game.inflight.get("args",{}).get("angle",-100)-angle)<.001)
 input_checks.append(game.placement_feedback.entries.size()==1 and cell.organs.size()==count)
 input_checks.append(game.sent[-1].action=="install" and not game.sent[-1].has("local_placement"))
 var item: Dictionary=game.placement_feedback.entries[0]
 game.placement_feedback.result(item.id,false,0)
 input_checks.append(not item.pending and not item.ghost.visible)
 game.inflight.clear();game.placement_feedback.clear()
 var token: int=game.placement_feedback.begin(cell,"photosynthesis",angle)
 item=game.placement_feedback.entries[0]
 game.placement_feedback.result(token,true,101);game.placement_feedback.reconcile(100)
 input_checks.append(item.pending and item.ghost.visible)
 game.placement_feedback.reconcile(101)
 input_checks.append(not item.pending and not item.ghost.visible and cell.organs.size()==count)
 game.placement_feedback.clear();game.selected=-1;game.build_open=false;view.rotation=heading
 var age: float=cell.age
 var clock: float=game.ui_time
 view.motile_art.sync(cell,true,clock+.15,game.world)
 preload("res://scripts/motile_art.gd").set_clock(clock+.15)
 input_checks.append(is_equal_approx(view.motile_art.material.get_shader_parameter("clock"),clock+.15) and cell.age==age and view.motile_art.get_parent()==view)
 game.build_open=true;game.cell_ui.open_context({"kind":"division"})
 var auto_choices=game.cell_ui.choices.filter(func(choice):return choice.has_meta("reproduction_auto"))
 input_checks.append(auto_choices.size()==2 and auto_choices.all(func(choice):return not choice.selection_glow))
 game.cell_ui.close_context();game.build_open=false
 game.settings_panel.show();game._layout()
 await get_tree().process_frame
 var menu: Rect2=game.settings_panel.get_global_rect()
 input_checks.append(menu.encloses(game.quit_button.get_global_rect()) and menu.encloses(game.logout_menu_button.get_global_rect()) and game.quit_button.get_parent()==game.logout_menu_button.get_parent() and game.logout_menu_button.get_global_rect().end.y<=game.quit_button.get_global_rect().position.y)
 game.settings_panel.hide()
