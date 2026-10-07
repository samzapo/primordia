extends SceneTree
## Fixed-horizon coupling throughput, not a full-game FPS benchmark.
const GPU=preload("res://scripts/resident_particles.gd")
const Perception=preload("res://scripts/resident_perception.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Cell=preload("res://scripts/cell.gd")
const Simulation=preload("res://scripts/simulation.gd")
const DT:=1.0/60
var rows: Array=[]
func _initialize() -> void: run.call_deferred()
func require(ok: bool,message: String) -> void:
	if not ok: push_error(message);quit(1);assert(ok,message)
func run() -> void:
	Fixture.load_native()
	for repeat in 2:
		for distribution in ["uniform","clustered"]:
			for mode in (["immediate-no-queries","immediate-packed","immediate","async"] if repeat==0 else ["async","immediate","immediate-packed","immediate-no-queries"]):
				await measure(distribution,mode,repeat)
	for distribution in ["uniform","clustered"]:
		var baseline: Dictionary={}
		for row in rows:
			if row.distribution!=distribution: continue
			if baseline.is_empty(): baseline=row
			for key in ["alive","accepted","queries","particle_material","cell_material","oxygen","ATP","processed"]:
				if key=="queries" and (row.mode=="immediate-no-queries" or baseline.mode=="immediate-no-queries"): continue
				require(absf(float(row[key])-float(baseline[key]))<0.00001,"Equal horizon "+key+" differs for "+distribution)
	print("COUPLING_PARITY passed: material, ATP, intake and final populations agree across handoff modes")
	quit()
func measure(distribution: String,mode: String,repeat: int) -> void:
	var sim=Simulation.new(380055)
	sim.disable_particle_pool();sim.particles=[];sim.pheromones=[];sim.grid.rebuild([])
	sim.time=10
	var cells: Array=[]
	for i in 8:
		var cell=Cell.new(i+1,Vector2(2048,1280)+Vector2.from_angle(TAU*i/8)*270)
		if i==0:
			cell.body=2040;cell.update_geometry();cell.membrane=Cell.Membrane.new(cell.radius,3800)
		cell.add_organ("feeding",0,"graze",false)
		cell.add_organ("hunting",PI*.7,"hunt",false)
		cell.add_organ("sensing",PI*1.3,"flee",false)
		cells.append(cell)
	var data:=Fixture.make(50000,distribution)
	var metadata: Array=[]
	for i in 50000:
		if data[i*12+7]!=3: continue
		var source:=100+i%64
		metadata.append({"slot":i,"owner":source,"expires_at":10.3+float(i%47)*.1,
			"report":{"id":source,"lineage":source,"at":Vector2(2000+i%200,1200),"mass":float(15+i%200),"radius":30,
			"emitted_at":5.0+(i%37)*.1,"hostile":i%3==0,"defended":i%5!=0}})
	var gpu=GPU.new()
	gpu.perception_spread_queries=mode!="immediate-packed"
	gpu.configure_interactions("chemistry");gpu.configure_exchange();gpu.configure_perception(10)
	gpu.initialize(data,Fixture.flow(),metadata)
	var status: Array=await gpu.ready;require(status[0],str(status[1]))
	var start:=Time.get_ticks_usec()
	var biology_usec:=0
	var query_count:=0
	var accepted:=0
	var elapsed: Array[float]=[]
	var steps:=120
	var initial_upload: int=gpu.exchange_upload_bytes
	var initial_readback: int=gpu.exchange_readback_bytes
	for tick in steps:
		var step_start:=Time.get_ticks_usec()
		gpu.advance(DT,tick);sim.time+=DT
		var prepare_start:=Time.get_ticks_usec()
		for cell in cells:
			cell.age+=DT
			cell.animate_resources(DT);sim._clear_receptors(cell,DT)
		var queries: Array=Perception.requests(cells,DT,sim.time) if mode!="immediate-no-queries" else []
		biology_usec+=Time.get_ticks_usec()-prepare_start
		query_count+=queries.size()
		var products: Array=[]
		var emission_cells: Array=[]
		for cell in cells:
			if cell.waste>=0.2:
				var at: Vector2=Fixture.wrapped(cell.position+Vector2(cell.extent()+20,0))
				products.append({"owner":cell.id,"state":PackedFloat32Array([at.x,at.y,0,0,0,0,0,2,4.8,cell.waste,0,0])})
				emission_cells.append(cell)
		require(gpu.exchange(cells,products,[],mode=="async",queries),"Coupling exchange refused")
		var receipt: Dictionary=await gpu.exchange_ready
		var biology_start:=Time.get_ticks_usec()
		for i in products.size():
			if receipt.emissions[i].accepted:
				# These packets were escrowed from actual accumulated metabolism.
				emission_cells[i].waste-=products[i].state[9];accepted+=1
		var pore:=0
		for i in cells.size():
			var cell=cells[i]
			# Sensing uses pre-feeding mass, matching the ordinary CPU phase order.
			sim._sense(cell,DT,Perception.for_cell(queries,receipt.senses,cell))
			cell.substrate+=receipt.intake[i][0];cell.oxygen+=receipt.intake[i][1];cell.carbon+=receipt.intake[i][2]
			cell.eaten+=receipt.intake[i][0];cell.foreign_intake+=receipt.intake[i][3]
			for organ in cell.organs:
				if organ.kind=="feeding": cell.consumed(organ,receipt.pores[pore]);pore+=1
			pore+=1 # Oxygen request.
			sim._metabolize(cell,DT);cell.heal(DT);cell.update_geometry()
			cell.membrane.step(DT,cell.radius,Vector2.ZERO,sim.time)
		biology_usec+=Time.get_ticks_usec()-biology_start
		elapsed.append((Time.get_ticks_usec()-step_start)/1000.0)
	var completed_ms: float=(Time.get_ticks_usec()-start)/1000.0/steps
	require(gpu.readbacks==0,"No full particle readback inside timed window")
	gpu.snapshot();var tail: PackedFloat32Array=await gpu.snapshot_ready
	var alive:=0;var material:=0.0
	for i in 50000:
		if tail[i*12+7]>=0: alive+=1
		if tail[i*12+7]!=3: material+=tail[i*12+9]
		for j in 12: require(is_finite(tail[i*12+j]),"Finite state")
	var cell_material:=0.0;var atp:=0.0;var oxygen:=0.0;var processed:=0.0
	for cell in cells:
		cell_material+=cell.organic_mass();atp+=cell.energy;oxygen+=cell.oxygen;processed+=cell.processed
	elapsed.sort()
	var result: Dictionary={"distribution":distribution,"mode":mode,"repeat":repeat,"steps":steps,
		"mean_completed_step_ms":completed_ms,"p95_completed_step_ms":elapsed[ceili(steps*.95)-1],
		"cpu_biology_ms":biology_usec/1000.0/steps,"starting_slots":50000,"alive":alive,
		"cells":8,"large_radius":cells[0].radius,"queries":query_count,"accepted":accepted,
		"particle_material":material,"cell_material":cell_material,"ATP":atp,"oxygen":oxygen,"processed":processed,
		"upload_bytes_per_step":float(gpu.exchange_upload_bytes-initial_upload)/steps,
		"readback_bytes_per_step":float(gpu.exchange_readback_bytes-initial_readback)/steps,"timed_pool_readbacks":0,
		"scope":"GPU transport/pair chemistry/expiry/feeding/exclusion/food and pheromone perception and existing CPU receptor delivery, metabolism, maintenance, healing and membrane updates. Stationary bodies and fixed flow; no full scene, unary chemistry, acidity, photosynthesis, motion/combat, offscreen ecology, succession or music. Not game FPS."}
	rows.append(result);print("COUPLING_BENCH ",JSON.stringify(result))
	gpu.close();await gpu.closed
