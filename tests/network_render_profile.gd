extends Node
## Isolated real-client rendering/replay diagnostic; never connects to a pond.
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
class Client:
	extends "res://scripts/network/network_client.gd"
	func _load_identity() -> void:pass
	func _save_identity() -> void:pass
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
func option(key: String,fallback: String) -> String:
	if OS.has_feature("web"):
		var value=JavaScriptBridge.eval("new URLSearchParams(location.search).get("+JSON.stringify(key)+")")
		return str(value) if value!=null else fallback
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"+key+"="):return arg.trim_prefix("--"+key+"=")
	return fallback
func _ready() -> void:
	settings={"cells":int(option("cells","48")),"zoom":float(option("zoom","0.8")),"case":option("case","all"),"seconds":float(option("seconds","8"))}
	assert(settings.cells>=1 and settings.cells<=64 and settings.zoom>=.8)
	game=Client.new();add_child(game);game.login.hide()
	game.preferences.persist=false;game.archive.persist=false
	game.music.enabled=option("music","off")=="on"
	game.touch_zoom.enabled=true
	game.epoch=1;game.camera_seen_world=true;game.camera_initialized=true
	game.manual_zoom=settings.zoom;game.camera_zoom=settings.zoom;game.camera_locked=true
	if settings.case=="no-flow":game.flow_streamers=false;game.flow_wakes=false
	if settings.case=="no-post":game.microscope_layer.hide()
	if settings.case=="no-light":game.light_layer.hide()
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
	var packets:=PackedByteArray();packets.resize(700*32)
	var random:=RandomNumberGenerator.new();random.seed=9701
	for i in 700:
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
	if elapsed>=3 and not started:
		started=true;measure_start=elapsed;trace=preload("res://scripts/frame_trace.gd").new();game.frame_trace=trace;trace.start(game)
	if started and elapsed-measure_start>=settings.seconds:
		finished=true;trace.stop();game.frame_trace=null
		var result={"settings":settings,"adapter":RenderingServer.get_video_adapter_name(),"device":RenderingServer.get_video_adapter_vendor(),"rows":trace.rows}
		if OS.has_feature("web"):JavaScriptBridge.eval("window.primordiaRenderProfile="+JSON.stringify(result))
		else:
			var file:=FileAccess.open(option("output","res://build/network-render.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify(result));file.close();get_tree().quit()
