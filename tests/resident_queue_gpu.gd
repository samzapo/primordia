extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Cell=preload("res://scripts/cell.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func packet(kind: int,at: Vector2,amount: float=0.3) -> PackedFloat32Array:
	return PackedFloat32Array([at.x,at.y,0,0,0,0,0,kind,6,amount,0,0])
func setup(data: PackedFloat32Array,depth: int):
	var gpu=GPU.new()
	gpu.exchange_parallel_oxygen=depth>1
	gpu.configure_interactions("chemistry")
	check(not gpu.configure_exchange(9,true),"Bounded queue")
	check(not gpu.configure_exchange(8,false),"Pipeline requires capacity ownership")
	check(gpu.configure_exchange(depth,depth>1),"Configure exchange")
	gpu.initialize(data,Fixture.flow())
	var status: Array=await gpu.ready;check(status[0],str(status[1]))
	return gpu
func run() -> void:
	Fixture.load_native()
	ordered_callbacks()
	await high_body_bits()
	await reservations()
	await refused_emissions()
	for distribution in ["uniform","clustered"]:
		await comparison(distribution)
	print("QUEUE_VALIDATION ",checks," checks")
	quit()
func reservations() -> void:
	var a=Cell.new(51,Vector2(500,500))
	var b=Cell.new(52,Vector2(500,500))
	for cell in [a,b]:
		cell.add_organ("feeding",0,"graze",false);cell.oxygen=cell.oxygen_capacity()
		cell.substrate=cell.gut_capacity()-0.25
	a.organs.append(a.organs[0].duplicate())
	var at: Vector2=a.pore_center(a.organs[0])
	var gpu=await setup(packet(0,at,1.4),8)
	var receipts: Array=[]
	gpu.exchange_ready.connect(func(r): receipts.append(r))
	for i in 8: check(gpu.exchange([a,b]),"Queue finite request")
	check(not gpu.exchange([a,b]),"Full queue applies backpressure")
	check(not gpu.end_capacity_epoch(),"Pending reservations cannot reset")
	while receipts.size()<8: await gpu.exchange_ready
	var total:=0.0
	for i in receipts.size():
		check(receipts[i].serial==i+1,"Exactly-once ordered receipts")
		var r: Dictionary=receipts[i]
		for j in 2:
			var consumed: float=r.intake[j][0];total+=consumed
			check(absf(consumed-(0.25 if i==0 else 0.0))<0.000001,"In-flight capacity not reused")
			[a,b][j].substrate+=consumed
		check(r.pores[1]==0,"Overlapping mouth does not double-credit")
	check(absf(total-0.5)<0.000001,"Combined capacity bound")
	check(gpu.exchange_peak_inflight==8 and gpu.exchange_inflight==0,"Pipeline drained")
	check(not gpu.exchange([b,a]),"Account order cannot change mid-epoch")
	var clone=Cell.new(a.id,a.position)
	check(not gpu.exchange([clone,b]),"Same numeric ID cannot replace an account")
	var old: float=a.biomass
	a.biomass+=10
	check(not gpu.exchange([a,b]),"Capacity-changing growth requires drain and new epoch")
	a.biomass=old
	# A subsequent epoch reflects real consumption, not free new feeding room.
	a.substrate-=0.125
	check(gpu.end_capacity_epoch(),"Reset only after receipts have been credited")
	check(gpu.exchange([a,b]),"Reopen after accounted consumption")
	var final: Dictionary=await gpu.exchange_ready
	check(absf(final.intake[0][0]-0.125)<0.000001 and final.intake[1][0]==0,"Only newly freed capacity is available")
	gpu.snapshot();var output: PackedFloat32Array=await gpu.snapshot_ready
	check(absf(output[9]+total+final.intake[0][0]-1.4)<0.000001,"No material duplication across epochs")
	gpu.close();await gpu.closed
func refused_emissions() -> void:
	var data:=packet(-1,Vector2.ZERO,0);data.append_array(data)
	var gpu=await setup(data,8)
	var receipts: Array=[]
	gpu.exchange_ready.connect(func(r): receipts.append(r))
	for i in 8:
		check(gpu.exchange([], [{"owner":i,"state":packet(2,Vector2(100+i,100),0.125)}]),"Queued paid emission")
	gpu.close()
	await gpu.closed
	check(receipts.size()==8,"Close delivers all outstanding receipts")
	var accepted:=0
	for i in 8:
		check(receipts[i].serial==i+1,"Close preserves receipt ordering")
		if receipts[i].emissions[0].accepted: accepted+=1
	check(accepted==2,"Only two available slots may be filled")
	var paid:=1.0
	var emitted:=accepted*0.125
	var retained_escrow: float=(8-accepted)*0.125
	check(emitted+retained_escrow==paid,"Refused emissions remain paid escrow")
func comparison(distribution: String) -> void:
	var results: Array=[]
	for depth in [1,8]:
		var cells: Array=[]
		for i in 4:
			var cell=Cell.new(i+1,Vector2(2048,1280)+Vector2.from_angle(TAU*i/4)*100)
			cell.add_organ("feeding",0,"graze",false);cell.add_organ("photosynthesis",PI,"graze",false)
			cells.append(cell)
		var gpu=await setup(Fixture.make(4097,distribution),depth)
		var receipts: Array=[]
		gpu.exchange_ready.connect(func(r): receipts.append(r))
		for tick in 24:
			while gpu.exchange_inflight>=depth: await gpu.exchange_ready
			gpu.advance(1.0/60,tick)
			check(gpu.exchange(cells,[],[],depth>1),"Submit equal simulation horizon")
			if depth==1:
				var r: Dictionary=await gpu.exchange_ready
				for i in cells.size():
					cells[i].substrate+=r.intake[i][0];cells[i].oxygen+=r.intake[i][1];cells[i].carbon+=r.intake[i][2]
		while gpu.exchange_inflight>0: await gpu.exchange_ready
		gpu.snapshot();var state: PackedFloat32Array=await gpu.snapshot_ready
		results.append({"state":state,"receipts":receipts})
		check(gpu.dispatches==24,"No simulation updates dropped")
		check(gpu.exchange_fallbacks==0,"No blocking fallback")
		gpu.close();await gpu.closed
	var error:=0.0
	for i in results[0].state.size(): error=maxf(error,absf(results[0].state[i]-results[1].state[i]))
	check(error<0.00001,"Pipeline particle outcome matches immediate: "+str(error))
	for tick in 24:
		for body in 4:
			for channel in 4:
				check(absf(results[0].receipts[tick].intake[body][channel]-results[1].receipts[tick].intake[body][channel])<0.00001,"Pipeline intake parity")
func ordered_callbacks() -> void:
	var gpu=GPU.new()
	gpu.configure_interactions("chemistry");gpu.configure_exchange(3,true)
	check(not gpu.configure_interactions("off"),"Cannot disable contacts after configuring exchange")
	gpu.exchange_serial=3;gpu.exchange_inflight=3;gpu.exchange_busy=true
	gpu._exchange_slots.fill(true)
	var delivered: Array[int]=[]
	gpu.exchange_ready.connect(func(r): delivered.append(r.serial))
	gpu._exchange_main({"serial":2,"ring_slot":1,"readback_bytes":16})
	check(delivered.is_empty() and gpu.exchange_inflight==3,"Out-of-order receipt waits without releasing its slot")
	gpu._exchange_main({"serial":1,"ring_slot":0,"readback_bytes":16})
	check(delivered==[1,2] and gpu.exchange_inflight==1,"Contiguous receipts delivered in order")
	gpu._exchange_main({"serial":3,"ring_slot":2,"readback_bytes":16})
	check(delivered==[1,2,3] and gpu.exchange_readback_bytes==48,"Every receipt delivered exactly once")
func high_body_bits() -> void:
	var reference: Array=[]
	for parallel in [false,true]:
		var cells: Array=[]
		for i in 64:
			var cell=Cell.new(i+1,Vector2(4090,2550))
			cell.oxygen=cell.oxygen_capacity()-(0.125 if i==63 else 0.0)
			cells.append(cell)
		var gpu=await setup(packet(1,Fixture.wrapped(Vector2(4090,2550)+Vector2(49,0)),0.5),1)
		gpu.exchange_parallel_oxygen=parallel
		check(gpu.exchange(cells),"Maximum body count and second oxygen-mask word")
		var receipt: Dictionary=await gpu.exchange_ready
		reference.append(receipt)
		check(absf(receipt.intake[63][1]-0.125)<0.000001,"Body 63 receives correct oxygen")
		for i in 63: check(receipt.intake[i][1]==0,"Full bodies cannot absorb oxygen")
		gpu.close();await gpu.closed
	check(reference[0].intake==reference[1].intake,"Parallel oxygen mask matches sequential support")
