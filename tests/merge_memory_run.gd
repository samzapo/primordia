extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const View=preload("res://scripts/merge_view.gd")
class Game:
	extends RefCounted
	func lineage_color(_id: int) -> String:return ""
var checks:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=Sim.new(18,0,false);sim.server_mode=true;sim.cells=[sim.player]
	sim.habitat_geometry=Sim.Habitat.new(18,sim.cells);sim.habitat_geometry.enabled=false
	var cell=sim.player;cell.organs.clear();cell.add_organ("feeding",0,"graze",false)
	var donor=Sim.Cell.new(501,cell.position+Vector2(300,0));donor.lineage=cell.lineage_id()
	donor.add_organ("feeding",0,"graze",false);donor.add_organ("photosynthesis",1,"graze",false)
	sim.cells.append(donor);sim.lineage.register(donor,cell.id,1,"living",0)
	var trace: Dictionary=sim._emit_pheromone(donor)
	trace.p=cell.organ_position(cell.organs[0]);trace.expires_at=.1
	sim.grid.rebuild(sim.particles);sim._sense(cell,.2)
	check(sim.FamilyMerging.candidates(sim,cell).has(donor.id),"An actual received tracer authorizes merge selection")
	var expires: float=sim.FamilyMerging.candidates(sim,cell)[donor.id]
	check(expires==5.0,"Memory lasts five seconds from reception, independently of the tracer expiry")
	var remembered: Vector2=cell.behavior.merge_cues[donor.id].report.at
	sim.particles=[];sim.grid.rebuild(sim.particles);sim.time=1;cell.sense_clock=0;sim._sense(cell,.2)
	check(cell.behavior.family_cues.is_empty() and sim.FamilyMerging.detected(sim,cell,donor.id),"A missed reception no longer makes a recent relative flicker out")
	check(sim.FamilyMerging.request(sim,donor.id),"Recently detected family remains clickable after its physical tracer is gone")
	donor.position+=Vector2(0,200)
	check(sim.FamilyMerging.direction(sim,cell).is_equal_approx(Sim.Medium.offset(cell.position,remembered).normalized()),"Approach uses the immutable received position, never live donor movement")
	for i in 20:sim.FamilyMerging.candidates(sim,cell)
	check(sim.FamilyMerging.candidates(sim,cell)[donor.id]==expires,"Drawing, target export and repeated inspection do not refresh memory")
	sim.time=4.99
	check(sim.FamilyMerging.detected(sim,cell,donor.id),"The recent-signal window stays stable through short gaps")
	sim.managed_cells=[donor.id]
	check(sim.FamilyMerging.candidates(sim,cell).is_empty() and not sim.FamilyMerging.request(sim,donor.id),"A newly controlled donor becomes unavailable immediately despite memory")
	sim.managed_cells=[]
	sim.time=5.01;cell.sense_clock=0;sim._sense(cell,.2)
	check(sim.FamilyMerging.candidates(sim,cell).is_empty() and sim.FamilyMerging.direction(sim,cell)==Vector2.ZERO,"No signal for five seconds expires selection and approach")
	sim.FamilyMerging.remember(sim,cell,{donor.id:{"expires_at":5.0,"report":trace.report}})
	check(not sim.FamilyMerging.detected(sim,cell,donor.id),"An already expired packet cannot renew permission")
	# A second true reception renews the finite window.
	trace=sim._emit_pheromone(donor);trace.p=cell.organ_position(cell.organs[0]);trace.expires_at=5.2
	sim.grid.rebuild(sim.particles);cell.sense_clock=0;sim._sense(cell,.2)
	check(sim.FamilyMerging.candidates(sim,cell)[donor.id]==10.01,"A fresh actual reception renews the window")
	donor.position=cell.position+Vector2(cell.extent()+donor.extent()-2,0)
	var organs: int=donor.organs.size()
	check(sim.FamilyMerging.request(sim,donor.id) and not sim.cells.has(donor),"Contact commits one transfer and removes the donor from simulation")
	check(sim.merge_bursts.size()==1 and sim.merge_bursts[0].portrait.organs.size()==organs,"The committed fact retains the donor artwork before organs are reabsorbed")
	check(not sim.FamilyMerging.request(sim,donor.id) and sim.merge_bursts.size()==1,"Retried selection cannot transfer again or replay the animation")
	var stored: Dictionary=Codec.new().capture(sim)
	check(not stored.objects[0].fields.has("merge_bursts"),"Animation artwork is transient and never retained in pond checkpoints")
	var view=View.new();view.game=Game.new();root.add_child(view)
	var amount: float=cell.biomass;var rng: int=sim.rng.state;var bodies: int=sim.cells.size()
	view.sync(sim,Vector2.ZERO,0)
	check(view.pulls.size()==1 and view.pulls[0].node.position.is_equal_approx(Sim.Medium.offset(Vector2.ZERO,donor.position)),"Pull-in starts at the consumed body's true position")
	view.sync(sim,Vector2.ZERO,.6)
	var midway: Vector2=view.pulls[0].node.position
	check(Sim.Medium.offset(midway,cell.position).length()<Sim.Medium.offset(donor.position,cell.position).length(),"The donor translates toward the receiving cell")
	view.sync(sim,Vector2.ZERO,0)
	check(view.pulls[0].node.position==midway,"A paused presentation holds the pull-in")
	view.sync(sim,Vector2.ZERO,.45)
	check(Sim.Medium.offset(view.pulls[0].node.position,cell.position).length()<.001 and view.pulls[0].node.modulate.a<1,"The image overlaps the receiving cell before fading")
	view.sync(sim,Vector2.ZERO,.2)
	check(view.pulls.is_empty(),"The consumed image disappears after the bounded animation")
	check(cell.biomass==amount and sim.rng.state==rng and sim.cells.size()==bodies,"Animation never adds a body, changes resources or advances ecology randomness")
	view.queue_free();await process_frame
	if "--gpu" in OS.get_cmdline_user_args():
		root.size=Vector2i(960,540)
		var art_class=preload("res://scripts/cell_art.gd")
		var portrait_class=preload("res://scripts/cell_portrait.gd")
		var model: Dictionary=portrait_class.capture(cell)
		var art: Dictionary=art_class.make(sim.seed_value,model.lineage)
		art["core"]=art_class.nucleus_outline(art.nucleus,art.phase)
		var mesh: ArrayMesh=portrait_class.body(model,art)
		var canvas:=Node2D.new();root.add_child(canvas)
		canvas.position=Vector2(320,240)+Sim.Medium.offset(donor.position,cell.position)
		canvas.draw.connect(func():portrait_class.draw(canvas,model,art,mesh,model.extent))
		canvas.queue_redraw()
		var raster=View.new();raster.game=Game.new();root.add_child(raster);raster.position=Vector2(320,240)
		raster.sync(sim,donor.position,0)
		for i in 3:await process_frame
		await RenderingServer.frame_post_draw
		var initial:=root.get_texture().get_image()
		var pixel: Vector2i=Vector2i(root.get_final_transform()*Vector2(320,240))
		var color: Color=initial.get_pixelv(pixel)
		raster.sync(sim,donor.position,.6)
		for i in 2:await process_frame
		check(raster.pulls[0].node.position.length()>1,"The drawn donor actually moves across the viewport")
		raster.sync(sim,donor.position,.7)
		for i in 3:await process_frame
		await RenderingServer.frame_post_draw
		var gone: Color=root.get_texture().get_image().get_pixelv(pixel)
		check(absf(color.r-gone.r)+absf(color.g-gone.g)+absf(color.b-gone.b)>.1 and raster.pulls.is_empty(),"Hardware pixels show donor artwork, then remove it after pull-in")
		raster.queue_free();canvas.queue_free();await process_frame
	print("MERGE MEMORY: %d assertions, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
