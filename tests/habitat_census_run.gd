extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Regions=preload("res://scripts/particle_regions.gd")
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:
	var regions=Regions.new()
	regions.put({"alive":true,"kind":0,"p":Vector2(10,10)},0)
	regions.put({"alive":true,"kind":3,"p":Vector2(12,10)},0)
	regions.put({"alive":false,"kind":0,"p":Vector2(12,10)},0)
	check(regions.count==2 and regions.living==2 and regions.signals==1,"Cold census excludes dead insertions")
	var chunks: Array=regions.borrow_region(Vector2.ZERO,Vector2(100,100))
	check(regions.living==0 and regions.signals==0,"Borrowed ownership is removed from cold census")
	chunks[0].packets[0].alive=false;regions.restore(chunks[0],0)
	check(regions.count==2 and regions.living==1 and regions.signals==1,"Retained dead storage slots are not living particles")
	regions.take(Vector2i.ZERO,1)
	check(regions.count==1 and regions.living==1 and regions.signals==1,"Taking a dead storage slot cannot decrement live census")
	regions.take(Vector2i.ZERO,1)
	check(regions.living==0 and regions.signals==0 and regions.chunks.is_empty(),"Final transfer clears census exactly")
	for pool in [false,true]:
		var sim=Sim.new(7100)
		sim.cells=[sim.player];sim.particles.clear();sim.grid.clear()
		sim.spawn_particle(Sim.NUTRIENT,Vector2(100,100),Vector2.ZERO,.3,0)
		sim.spawn_particle(Sim.PHEROMONE,Vector2(100,100),Vector2.ZERO,.3,0)
		sim.spawn_particle(Sim.WASTE,Vector2(100,100),Vector2.ZERO,.3,0)
		sim.particles[-1].alive=false
		if pool and sim.kernels!=null:sim.enable_particle_pool()
		var census: Dictionary=sim.habitat_census()
		check(census.external==2 and census.signals==1 and census.chemicals==1 and census.living_cells==1,"Native/reference habitat census uses live particles, not storage length")
	var text: String=preload("res://scripts/network/network_client.gd").population_text({"external":9000,"living_cells":17,"camera_particles":12,"gpu":3000,"cold":5990,"pending":10},12)
	check(text.contains("12 particles") and text.contains("17 living cells / 9000 particles"),"Browser HUD distinguishes server-global counts from camera snapshots")
	text=preload("res://scripts/network/network_client.gd").population_text({"external":9000,"internal":330,"total":9330,"living_cells":17,"camera_particles":12},12)
	check(text.contains("9330 particles") and text.contains("9000") and text.contains("330"),"Habitat total includes internal particles while retaining the exterior budget count")
	text=preload("res://scripts/network/network_client.gd").population_text({},12)
	check(text.contains("waiting for server") and not text.contains("12 living"),"Old server compatibility cannot fabricate a habitat total")
	print("HABITAT CENSUS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
