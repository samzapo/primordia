extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Ecology=preload("res://scripts/resident_ecology.gd")
const Simulation=preload("res://scripts/simulation.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Perception=preload("res://scripts/resident_perception.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func packet(kind: int,at: Vector2,amount: float=.3) -> PackedFloat32Array:
	return PackedFloat32Array([at.x,at.y,.3,.2,7,-2,0,kind,6,amount,amount,0])
func report(id: int,emitted: float,expiry: float,mass: float=20) -> Dictionary:
	return {"owner":id,"lineage":id,"expires_at":expiry,"report":{"id":id,"lineage":id,"mass":mass,"at":Vector2(1800,900),"radius":30.,"emitted_at":emitted,"hostile":true,"defended":true}}
func setup(values: PackedFloat32Array,metadata: Array=[],local: bool=false):
	var gpu=GPU.new();gpu.configure_interactions("chemistry");gpu.configure_exchange();gpu.configure_perception()
	gpu.configure_transfer(local)
	gpu.initialize(values,Fixture.flow(),metadata)
	var status: Array=await gpu.ready;check(status[0],str(status[1]))
	return gpu
func run() -> void:
	Fixture.load_native()
	preload("res://tests/particle_regions.gd").run(check)
	await transfer()
	await summaries()
	await food_summary()
	await journey()
	print("STREAMING_VALIDATION ",checks," checks")
	quit()
func transfer() -> void:
	var values:=PackedFloat32Array()
	var metadata: Array=[]
	for i in 1200:
		values.append_array(packet(3 if i%7==0 else 0,Vector2(3000+i%100,100)))
		if i%7==0:
			var m:=report(i+10,0,20);m["slot"]=i;metadata.append(m)
	values.append_array(packet(0,Vector2(4095,100)))
	var gpu=await setup(values,metadata,true)
	var unique: Dictionary={}
	var mass:=0.0
	var first_handle:=Vector2i.ZERO
	for turn in 3:
		var receipt: Dictionary=gpu.take_outside(Vector4(5,100,100,100))
		check(receipt.count==mini(512,1200-turn*512),"Bounded transfer count including final partial batch")
		check(receipt.readback_bytes==16+512*128,"Fixed transfer byte ceiling")
		check(gpu.take_outside(Vector4.ZERO)==receipt,"Unacknowledged transfer retries return the same escrow")
		check(not gpu.acknowledge_transfer(-1),"Wrong acknowledgement cannot discard escrow")
		for i in receipt.count:
			var at: int=i*128
			var slot: int=receipt.bytes.decode_u32(at+112)
			check(not unique.has(slot),"Each source slot transferred exactly once")
			unique[slot]=true
			mass+=receipt.bytes.decode_float(at+36)
			check(absf(receipt.bytes.decode_float(at+8)-.3)<.000001,"Transfer preserves orientation")
			if receipt.bytes.decode_float(at+28)==3:
				check(receipt.bytes.decode_s32(at+48+16)==slot+10,"Immutable report identity survives handoff")
				check(receipt.bytes.decode_float(at+48+36)==20,"Absolute expiry survives handoff")
			if turn==0 and i==0: first_handle=Vector2i(slot,receipt.bytes.decode_u32(at+116))
		check(gpu.acknowledge_transfer(receipt.ticket),"Accept transfer exactly once")
		check(not gpu.acknowledge_transfer(receipt.ticket),"Duplicate acknowledgement does not accept a later receipt")
	check(unique.size()==1200 and absf(mass-360)<.0001,"Transfer conserves all material without overflow loss")
	var inspected: Dictionary=gpu.exchange_sync([],[],[first_handle],[],{"feeding":false,"projection":false})
	check(not inspected.inspections[0].valid,"Departed particle cannot be tracked through stale GPU handle")
	var state: Dictionary=gpu.export_sync()
	var live:=0
	for i in 1201:
		if state.state[i*12+7]>=0: live+=1
	check(live==1 and state.state[1200*12]==4095,"Toroidal seam retains the genuinely nearby packet")
	gpu.close();await gpu.closed
func summaries() -> void:
	var values:=PackedFloat32Array()
	for i in 32: values.append_array(packet(-1,Vector2.ZERO,0))
	var gpu=await setup(values,[],true)
	var query: Dictionary={"at":Vector2(10,100),"reach":120.,"id":1,"lineage":1,"mass":100.,"mode":"hunt","target_id":-1,"incumbent":false}
	for round_id in 40:
		gpu.perception_time=round_id*2.
		var products: Array=[]
		for i in 32:
			var product:=report(10+(round_id*32+i)*1024,gpu.perception_time,gpu.perception_time+1,200 if i==0 else 20)
			product.state=packet(3,Vector2(10,100));products.append(product)
		var receipt: Dictionary=gpu.exchange_sync([],products,[],[],{"feeding":false,"projection":false})
		check(not receipt.has("error") and receipt.emissions.all(func(p): return p.accepted),"Local identity mapping survives more than 1024 historical sources")
		receipt=gpu.exchange_sync([],[],[],[query],{"feeding":false,"projection":false,"summaries":true})
		check(not receipt.summaries[0].has("error") and receipt.summaries[0].reports.size()==32,"Summary retains every latest source including ineligible prey")
		check(receipt.summaries[0].reports[10+round_id*32*1024].report.mass==200,"Large defended report is retained before eligibility filtering")
	check(gpu._perception.sources.is_empty(),"Streaming stores no ever-growing global source map")
	gpu.close();await gpu.closed
func food_summary() -> void:
	var values:=packet(0,Vector2(25,100),2)
	values.append_array(packet(0,Vector2(30,100),3))
	var gpu=await setup(values,[],true)
	var query: Dictionary={"at":Vector2(10,100),"center":Vector2(10,100),"reach":310.,"id":1,"lineage":1,"mass":100.,"mode":"graze","target_id":-1,"incumbent":false}
	var receipt: Dictionary=gpu.exchange_sync([],[],[],[query],{"feeding":false,"projection":false,"summaries":true})
	var summary: Dictionary=receipt.summaries[0]
	check(summary.food.size()==1 and summary.food[Vector2i.ZERO].mass==5.,"GPU summary preserves bin mass before choosing a food patch")
	check(summary.food[Vector2i.ZERO].moment==Vector2(90,0),"GPU food moments use the cell-centered wrapped coordinate frame")
	check(summary.food[Vector2i.ZERO].nearest==Vector2(15,0),"Summary retains nearest particle for inner-threshold steering")
	var cold: Dictionary={"food":{Vector2i.ZERO:{"mass":1.,"moment":Vector2(5,0),"nearest":Vector2(5,0),"distance":5.}},"reports":{}}
	var merged: Dictionary=Perception.merge(cold,summary)
	check(merged.food[Vector2i.ZERO].mass==6. and merged.food[Vector2i.ZERO].moment==Vector2(95,0),"Cross-boundary patches combine before target selection")
	gpu.close();await gpu.closed

func organic(sim,packets: Array) -> float:
	var total: float=sim.lineage.stored_material()+sim.respiration_loss-sim.external_input
	for cell in sim.cells:
		if not cell.dead: total+=cell.organic_mass()
	for p in packets:
		if p.alive and p.kind not in [1,3]: total+=p.amount
	return total
func journey() -> void:
	var sim=Simulation.new(41021)
	var before:=organic(sim,sim.particles)
	var original: int=sim.particles.size()
	var bridge=Ecology.new();bridge.start(sim,8192)
	var status: Array=await bridge.initialized;check(status[0],str(status[1]))
	check(bridge.stored_count()>0 and bridge.alive<original,"Only the nearby window is initially resident")
	sim.camera_follows_player=false
	for i in 360:
		var requested:=Simulation.Medium.wrap_position(sim.player.position+Vector2(i*8,100*sin(i*.03)))
		if i%90>=45: requested=Simulation.Medium.wrap_position(sim.player.position-Vector2(i*8,100))
		sim.camera_position=bridge.streaming.request_view(requested)
		var coverage: Vector2=Simulation.Medium.offset(bridge.streaming.center,sim.camera_position).abs()+bridge.detail_half
		check(coverage.x<=bridge.streaming.half.x-127.9 and coverage.y<=bridge.streaming.half.y-127.9,"Camera reversal keeps the entire visible rectangle inside prepared GPU water")
		sim.step(1./60)
		check(sim.resident!=null,"Travel does not force CPU fallback")
		check(sim.particles.is_empty() and sim.pheromones.is_empty(),"Cold borrowed worksets never become pose mirrors")
		check(bridge.streaming.entered<=256 and bridge.streaming.cold.visits<=8,"Admissions and cold scheduler work stay bounded")
		check(bridge.streaming.cold.due.size()==bridge.streaming.cold.chunks.size(),"Scheduler storage remains proportional to cold regions")
	check(bridge.streaming.exited>0,"Moving camera evicts actual packets")
	check(bridge.gpu.readbacks==0,"Travel never exports the whole GPU pool")
	var packets: Array=bridge.snapshots()
	check(sim.habitat_census().external==packets.filter(func(packet):return packet.alive).size(),"Global census includes all disjoint live owners without a per-frame snapshot")
	var error:=organic(sim,packets)-before
	check(absf(error)<.01,"Moving-window conservation including ecology: "+str(error))
	print("STREAMING_JOURNEY ",JSON.stringify({"resident":bridge.alive,"cold":bridge.stored_count(),"transferred":bridge.streaming.exited,"material_error":error,"transfer_bytes":bridge.gpu.transfer_readback_bytes}))
	var total: int=packets.size()
	var unaccepted: Dictionary=bridge.gpu.take_outside(Vector4.ZERO)
	check(unaccepted.count>0,"Regression retains an unacknowledged transfer during recovery")
	check(bridge.snapshots().size()==total,"Snapshots include unacknowledged transfer escrow exactly once")
	bridge.fallback("Intentional streaming recovery regression")
	check(sim.resident==null and sim.particle_pool,"CPU recovery restores native ownership")
	check(sim.particle_count()==total,"Fallback includes cold chunks, resident packets and paid escrow")
	check(absf(organic(sim,sim.particle_snapshots())-before)<.01,"Fallback preserves complete material")
	await bridge.gpu.closed
