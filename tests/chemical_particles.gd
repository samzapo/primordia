extends RefCounted
const Cell=preload("res://scripts/cell.gd")
const Catalog=preload("res://scripts/chemistry_catalog.gd")
const Surface=preload("res://scripts/surface_chemistry.gd")
static func empty():return Cell.new()
static func run(check: Callable) -> void:
	preload("res://tests/food_vacuoles.gd").run(check)
	var cell=empty()
	check.call(not cell.add_organ("offensive",0),"Removed spikes cannot be constructed")
	check.call(cell.add_organ("poreforming",0,"graze",false),"Chemical gland is an available paid anatomy type")
	var initial: float=cell.organic_mass()
	check.call(Surface.bind(cell,11,0.03,0),"A surface tag binds locally")
	for i in 4: check.call(Surface.bind(cell,12,0.0375,0),"Aligned pore subunit adds finite bound material")
	check.call(is_equal_approx(cell.surface_material(),0.18),"Surface complex retains all incoming material")
	cell.energy=0
	var hp: float=cell.health
	Surface.advance(cell,0.1)
	check.call(cell.health<hp or cell.organs[0].hp<cell.organs[0].max_hp,"A completed chemical pore damages the ordinary membrane/armor")
	cell=empty();cell.energy=0
	Surface.bind(cell,11,0.03,0)
	for i in 4:Surface.bind(cell,12,.0375,0)
	Surface.advance(cell,.1)
	check.call(is_equal_approx(cell.health,98.4),"A complete finite pore applies the restored membrane damage rate")
	cell=empty()
	Surface.bind(cell,11,0.03,0)
	Surface.bind(cell,12,0.0375,0)
	check.call(Surface.bind(cell,7,0.06,0),"Inhibitor caps an unfinished pore")
	Surface.advance(cell,0.1)
	check.call(cell.surface_complexes.is_empty() and is_equal_approx(cell.waste,0.1275),"Inhibition returns every bound packet's material to waste")

	var sim
	for pooled in [false,true]:
		sim=preload("res://tests/pheromones.gd").isolated()
		if pooled and sim.kernels==null: continue
		var prey=Cell.new(42,sim.player.position+Vector2(180,0))
		prey.activity=1
		sim.cells.append(prey)
		var contact: Vector2=prey.position+prey.local_point(0)
		if pooled: sim.enable_particle_pool()
		for kind in [11,12,12,12,12]:
			sim._emit_aimed(kind,contact,Vector2.LEFT,0,0.03 if kind==11 else 0.0375,sim.player.id)
		sim._surface_contacts()
		check.call(prey.surface_complexes.size()==1 and prey.surface_complexes[0].source==sim.player.id,"Surface assembly preserves secretion owner in both CPU ownership paths")
		Surface.advance(prey,0.1,sim)
		check.call(sim.evolution.exposures.pore>0,"Actual pore damage credits the chemical source for adaptive responses")

	for pooled in [false,true]:
		sim=preload("res://tests/pheromones.gd").isolated()
		if pooled and sim.kernels==null: continue
		cell=sim.player
		sim.camera_follows_player=false
		sim.camera_position=Vector2.ZERO
		sim.view_half=Vector2(10,10)
		cell.activity=0
		Surface.bind(cell,11,0.03,0,999)
		Surface.bind(cell,12,0.0375,0,999)
		if pooled: sim.enable_particle_pool()
		sim._emit_aimed(7,cell.position+cell.local_point(0),Vector2.LEFT,0,0.06,cell.id)
		sim.offscreen_ecology._exposure(sim,cell,100)
		check.call(cell.surface_complexes[0].capped,"Own-family inhibitors protect a hidden cell in both ownership paths")
