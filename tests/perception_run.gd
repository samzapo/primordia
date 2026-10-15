extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var assertions:=0
var failures:=0
func check(value: bool,message: String) -> void:
	assertions+=1
	if not value:failures+=1;push_error("FAIL: "+message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=Sim.new(18,0,false);sim.cells=[sim.player]
	var cell=sim.player
	cell.chemistry.particles.clear();cell.chemistry.bins.clear();cell.chemistry.totals.clear();cell.chemistry.vacuoles.clear()
	for node in cell.chemistry.nodes:node.enabled=false
	cell.chemistry.emit("waste",1,Vector2(10,0))
	var mass: float=cell.organic_mass()
	cell.coarse_elapsed=.25;sim.enable_perception_domains();sim.enable_perception_domains()
	check(is_equal_approx(cell.chemistry.pending_time,.25),"Legacy unresolved chemistry time migrates once")
	cell.chemistry.coarse_due=.75
	var start: Vector2=cell.chemistry.particles[0].p
	sim._step_internal_chemistry(.25)
	check(cell.chemistry.particles[0].p==start and is_equal_approx(cell.chemistry.pending_time,.5),"Hidden intracellular chemistry accumulates elapsed time without fake transport")
	var saved=preload("res://scripts/network/state_codec.gd").new().capture({"world":sim})
	var restored=preload("res://scripts/network/state_codec.gd").new().restore(saved).world
	check(is_equal_approx(restored.player.chemistry.pending_time,.5),"Checkpoint roundtrip retains unresolved intracellular time")
	restored.interoceptive_cells[restored.player.id]=true;restored._step_internal_chemistry(.1)
	check(is_equal_approx(restored.player.chemistry.simulated_time,.6) and restored.player.chemistry.pending_time==0 and restored.player.chemistry.particles[0].p!=start,"Opening internal detail advances all real deferred transport exactly once")
	check(absf(restored.player.organic_mass()-mass)<.00001,"Internal promotion conserves actual retained particle material")
	var before: float=restored.player.chemistry.simulated_time
	restored._metabolize(restored.player,.1)
	check(restored.player.chemistry.simulated_time==before,"Body metabolism cannot double-step the independent intracellular clock")
	sim._step_internal_chemistry(.5)
	check(is_equal_approx(cell.chemistry.simulated_time,1) and cell.chemistry.coarse_updates==1,"Hidden chemistry executes real bounded offscreen substeps at the ordinary period")
	var host=preload("res://scripts/network/world_host.gd").new();host.world=sim
	var account={"selected":cell.id,"current":cell,"lineage":sim.lineage,"root":cell.lineage_id()}
	host.accounts={"fixture":account}
	var one={"account":"fixture","view":Vector4(cell.position.x,cell.position.y,600,400),"detail":Vector2(700,500),"seen":Time.get_ticks_msec(),"perception":"interoception"}
	var two={"account":"fixture","view":Vector4(cell.position.x+300,cell.position.y+100,600,400),"detail":Vector2(700,500),"seen":Time.get_ticks_msec(),"perception":"exteroception"}
	host.peers={1:one,2:two};host._set_views()
	check(sim.camera_views.size()==1 and sim.interoceptive_cells.has(cell.id),"Mixed players independently retain exterior footprint and interior cell detail")
	two.perception="interoception";host._set_views()
	check(sim.camera_views.is_empty() and sim.interoceptive_cells.size()==1,"Two inside viewers do not retain external fine simulation or duplicate internal ownership")
	one.view=Vector4(-10000,-10000,100,100);two.view=one.view;host._set_views()
	check(sim.interoceptive_cells.is_empty(),"An internal view panned away from its cell retains only the coarse simulation")
	host.free()
	var scene=load("res://scenes/pond.tscn").instantiate();scene.use_particle_pool=false;root.add_child(scene)
	scene.set_process(false);scene.set_physics_process(false);scene.music.enabled=false;scene.music.player.stop()
	check(not scene.internal_visible(scene.world.player),"Default exteroception hides all intracellular chemical particles")
	var inside_key:=InputEventKey.new();inside_key.keycode=KEY_I;inside_key.pressed=true
	scene._input(inside_key)
	check(scene.internal_visible(scene.world.player) and scene.perception_mask.enabled and scene.perception_mask.body.mesh!=null,"Interoception shows focused particles with an actual membrane mesh mask")
	check(scene.batches.all(func(batch):return not batch.visible),"Interoception hides external particle drawing")
	scene.world.player.dead=true;scene.world.cells=[];scene._update_world(1)
	check(not scene.perception_mask.enabled and scene.microscope_layer.material.get_shader_parameter("interoception") and not scene.microscope_layer.material.get_shader_parameter("focus_valid"),"No visible membrane leaves the entire inside-mode scene dim instead of a stale colored hole")
	scene._toggle_perception()
	check(not scene.perception_mask.enabled and not scene.internal_visible(scene.world.player),"Returning outside restores exterior presentation without an internal mask")
	scene.queue_free();await process_frame
	print("PERCEPTION: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
