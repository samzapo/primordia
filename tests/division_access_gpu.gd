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
	print("DIVISION_ACCESS_GPU ",RenderingServer.get_video_adapter_name())
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
	print("DIVISION ACCESS GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
