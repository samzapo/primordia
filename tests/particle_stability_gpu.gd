extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
var checks:=0
var failed:=false
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func run() -> void:
	await admission()
	await cloud()
	await escrow()
	await asymmetric_contacts()
	print("PARTICLE_STABILITY_VALIDATION ",checks," checks")
	quit(1 if failed else 0)
func admission() -> void:
	var data:=PackedFloat32Array();data.resize(100000*12)
	for i in 100000:data[i*12+7]=-1
	var gpu=GPU.new();gpu.configure_interactions("chemistry");gpu.configure_exchange();gpu.configure_perception();gpu.configure_transfer()
	gpu.initialize(data,Fixture.flow())
	var ready: Array=await gpu.ready;check(ready[0],str(ready[1]))
	for cycle in 3:
		var handles: Array=[]
		for batch in 20:
			var products: Array=[]
			for i in 256:
				var at:=Vector2(200+(i%16)*20,200+floori(i/16.)*20+batch*25)
				products.append({"owner":1,"state":PackedFloat32Array([at.x,at.y,0,0,0,0,0,6,6,.3,.3,0])})
			var receipt: Dictionary=gpu.exchange_sync([],products,[],[],{"feeding":false,"projection":false})
			check(not receipt.has("error") and receipt.emissions.all(func(e):return e.accepted),"100k allocation admits every bounded batch; cycle "+str(cycle)+" batch "+str(batch))
			for emission in receipt.emissions:handles.append(emission.handle)
		var exported:=0
		while true:
			var out: Dictionary=gpu.take_outside(Vector4.ZERO)
			exported+=out.count
			check(gpu.acknowledge_transfer(out.ticket),"Exactly-once bounded eviction")
			if out.deferred==0:break
		check(exported==5120,"No live packet lost across empty-window transfers")
		var stale: Dictionary=gpu.exchange_sync([],[],[handles[0]],[],{"feeding":false,"projection":false})
		check(not stale.inspections[0].valid,"Stale handle rejected after eviction")
	gpu.close();await gpu.closed
func cloud() -> void:
	for count in [2,16,128]:
		var data:=PackedFloat32Array()
		for i in count:
			data.append_array(PackedFloat32Array([100+(i%2)*.01,100,0,0,0,0,0,6,8,.3,.3,0]))
		var field:=PackedVector2Array();field.resize(2560);field.fill(Vector2.ZERO)
		var gpu=GPU.new();gpu.configure_interactions("collisions");gpu.initialize(data,field)
		var ready: Array=await gpu.ready;check(ready[0],str(ready[1]))
		gpu.interact_only();gpu.snapshot()
		var state: PackedFloat32Array=await gpu.snapshot_ready
		var maximum:=0.0;var momentum:=Vector2.ZERO
		for i in count:
			var velocity:=Vector2(state[i*12+4],state[i*12+5])
			maximum=maxf(maximum,velocity.length());momentum+=velocity
		print("DENSE_CLOUD ",JSON.stringify({"count":count,"launch_max":maximum,"momentum":momentum.length()}))
		check(maximum<=16.01,"Contact crowding must not multiply launch speed with the number of overlapping parcels")
		check(momentum.length()<.01,"Pair impulses remain equal and opposite")
		for tick in 120:gpu.advance(1./30,tick)
		gpu.snapshot();state=await gpu.snapshot_ready
		for i in count:
			check(Vector2(state[i*12+4],state[i*12+5]).is_finite() and Vector2(state[i*12+4],state[i*12+5]).length()<100,"Crowded cloud stays finite without a continuing ballistic launch")
			check(state[i*12+7]==6 and absf(state[i*12+9]-.3)<.000001,"Collision relaxation cannot alter species or finite material")
		gpu.close();await gpu.closed

func escrow() -> void:
	var sim=preload("res://scripts/simulation.gd").new(390013)
	sim.cells=[sim.player];sim.particles=[];sim.pheromones=[];sim.grid.rebuild([])
	for i in 4:sim.spawn_particle(sim.ENZYME,sim.player.position+Vector2(i*20,0),Vector2.ZERO,.3,7)
	var bridge=preload("res://scripts/resident_ecology.gd").new();bridge.start(sim,4)
	var ready: Array=await bridge.initialized;check(ready[0],str(ready[1]))
	for i in 300:sim.spawn_particle(sim.ENZYME,sim.player.position+Vector2(10,0),Vector2.ZERO,.1,7)
	var receipt: Dictionary=bridge._receipt([],[],{"feeding":false,"projection":false})
	check(not receipt.has("error") and receipt.get("_capacity",false) and bridge.pending.size()==300,"Full capacity defers all paid emissions without aborting the body receipt")
	sim.step(1./30)
	check(sim.resident==bridge and sim.particles.is_empty(),"A full pool continues resident simulation without CPU pose mirroring")
	var before:=0.0
	for packet in bridge.snapshots():before+=packet.amount
	var out: Dictionary=bridge.gpu.take_outside(Vector4.ZERO)
	check(bridge.streaming.receive(sim,out) and bridge.gpu.acknowledge_transfer(out.ticket),"Eviction transfers existing material exactly once")
	var pending: int=bridge.pending.size()
	receipt=bridge._receipt([],[],{"feeding":false,"projection":false})
	check(not receipt.has("error") and bridge.pending.size()<pending,"Deferred emissions retry into newly freed slots")
	var after:=0.0
	for packet in bridge.snapshots():after+=packet.amount
	check(absf(before-after)<.00001,"Backpressure preserves every pending and transferred material parcel")
	bridge.close();await bridge.gpu.closed

func asymmetric_contacts() -> void:
	var data:=PackedFloat32Array()
	for x in [100,104,110,1000]:
		data.append_array(PackedFloat32Array([x,100,0,0,500 if x==1000 else 0,0,0,6,8,.3,.3,0]))
	var field:=PackedVector2Array();field.resize(2560);field.fill(Vector2.ZERO)
	var gpu=GPU.new();gpu.configure_interactions("collisions");gpu.initialize(data,field)
	var ready: Array=await gpu.ready;check(ready[0],str(ready[1]))
	gpu.interact_only();gpu.snapshot()
	var state: PackedFloat32Array=await gpu.snapshot_ready
	check(absf(state[4]+4)<.00001 and absf(state[16]-2)<.00001 and absf(state[28]-2)<.00001,"Unequal endpoint degrees still use one symmetric divisor per pair")
	check(state[40]==500,"Contact relaxation does not cap an isolated launch velocity")
	gpu.close();await gpu.closed
