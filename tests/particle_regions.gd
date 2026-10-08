extends RefCounted
const Regions=preload("res://scripts/particle_regions.gd")
const Perception=preload("res://scripts/resident_perception.gd")
static func run(expect: Callable) -> void:
	var regions=Regions.new()
	for i in 10000: regions.put({"alive":true,"p":Vector2(i*512,0),"amount":.3},0)
	expect.call(regions.count==10000,"Sparse world retains all authored packets")
	var near: Array=regions.take_region(Vector2.ZERO,Vector2(100,100),16)
	expect.call(near.size()==1 and regions.count==9999,"Local query only borrows nearby chunks")
	for i in 1000:
		regions.put_all(near,0)
		near=regions.take_region(Vector2.ZERO,Vector2(100,100),16)
	expect.call(regions.due.size()==regions.chunks.size(),"Repeated borrow/return never accumulates stale scheduler entries")
	var visited: Dictionary={}
	for i in 100:
		var due: Array=regions.take_due(1,8,2)
		expect.call(due.size()==1 and regions.visits<=2,"Cold work has a fixed visit/packet ceiling")
		if not due.is_empty(): visited[due[0].p]=true
	expect.call(visited.size()==100,"Due scheduler progresses fairly through distant regions")
	regions=Regions.new();regions.dimensions=Vector2i(16,10)
	regions.put({"alive":true,"p":Vector2(4095,2559),"amount":2},0)
	expect.call(regions.take_region(Vector2.ZERO,Vector2(5,5),10).size()==1,"Wrapped seam borrows the correct region once")
	expect.call(regions.due.is_empty(),"Empty region releases scheduler memory")
	var a: Dictionary={"food":{Vector2i.ZERO:{"mass":2.,"moment":Vector2(20,0),"distance":10.,"nearest":Vector2(10,0)}},"reports":{7:{"report":{"emitted_at":1.,"defended":false}}}}
	var b: Dictionary={"food":{Vector2i.ZERO:{"mass":3.,"moment":Vector2(60,0),"distance":20.,"nearest":Vector2(20,0)}},"reports":{7:{"report":{"emitted_at":2.,"defended":true}}}}
	var merged: Dictionary=Perception.merge(a,b)
	expect.call(merged.food[Vector2i.ZERO].mass==5 and merged.food[Vector2i.ZERO].moment==Vector2(80,0),"Food moments combine across ownership boundary")
	expect.call(merged.food[Vector2i.ZERO].nearest==Vector2(10,0),"Combined patch retains its nearest food")
	expect.call(merged.reports[7].report.defended,"Newer ineligible report supersedes older eligible report across ownership boundary")

	var sim=preload("res://scripts/simulation.gd").new(4108)
	var streaming=preload("res://scripts/particle_streaming.gd").new()
	if sim.kernels!=null:
		var scalar=Regions.new();var native_chunks=Regions.new()
		scalar.dimensions=Vector2i(16,10);native_chunks.dimensions=scalar.dimensions;native_chunks.kernels=sim.kernels
		scalar.put_all(sim.particles,sim.time);native_chunks.put_all(sim.particles,sim.time)
		expect.call(scalar.count==native_chunks.count and scalar.snapshots()==native_chunks.snapshots(),"Native region partition preserves packets, metadata and spatial order")
		for key in scalar.chunks:
			expect.call(scalar.chunks[key].transport_due==native_chunks.chunks[key].transport_due and scalar.chunks[key].chemical_due==native_chunks.chunks[key].chemical_due,"Native chunk deadlines match the reference")
		for cell in sim.cells: sim._emit_pheromone(cell)
		for cell in sim.cells:
			for mode in ["graze","hunt","flee"]:
				var query: Dictionary={"at":cell.position,"center":cell.position,"reach":700.,"id":cell.id,"lineage":cell.lineage_id(),"mode":mode}
				var native: Dictionary=streaming.sense(sim,query)
				var kernels=sim.kernels;sim.kernels=null
				var script: Dictionary=streaming.sense(sim,query)
				sim.kernels=kernels
				expect.call(native.reports==script.reports,"Native cold perception preserves all immutable reports")
				expect.call(native.food.keys()==script.food.keys(),"Native cold food bins retain reference traversal")
				for key in native.food:
					expect.call(absf(native.food[key].mass-script.food[key].mass)<.00001 and native.food[key].moment.distance_to(script.food[key].moment)<.001,"Native cold food moments match script reference")
	var packets: Array=sim.particles.slice(0,64).duplicate(true)
	var expected: Array=packets.duplicate(true)
	sim.time=2.;sim.transport_clock=2.
	streaming.random.seed=4108
	streaming.advance(sim,packets,true)
	var native_random: int=streaming.random.state
	var kernels=sim.kernels;sim.kernels=null;streaming.random.seed=4108
	streaming.advance(sim,expected,true);sim.kernels=kernels
	for i in packets.size():
		expect.call(packets[i].p.distance_to(expected[i].p)<.002 and absf(packets[i].age-expected[i].age)<.00001,"Cold promotion integrates exactly elapsed time with shared native/reference transport")
	expect.call(streaming.random.state==native_random,"Cold native transport retains independent random-walk draws")
