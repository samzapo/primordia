extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Cell=preload("res://scripts/cell.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Fixture.load_native()
	for repeat in 2:
		for distribution in ["uniform","clustered"]:
			for mode in (["immediate","pipeline"] if repeat==0 else ["pipeline","immediate"]):
				for parallel in ([false,true] if repeat==0 else [true,false]):
					await measure(distribution,mode,repeat,parallel)
	quit()
func measure(distribution: String,mode: String,repeat: int,parallel: bool) -> void:
	var cells: Array=[]
	for i in 8:
		var cell=Cell.new(i+1,Vector2(2048,1280)+Vector2.from_angle(TAU*i/8)*270)
		cell.add_organ("feeding",0,"graze",false);cell.add_organ("photosynthesis",PI,"graze",false)
		if i==0:
			for j in cell.membrane.COUNT: cell.membrane.points[j]*=3
			cell.membrane.maximum_radius*=3;cell.membrane.invalidate()
		cells.append(cell)
	var gpu=GPU.new()
	gpu.exchange_parallel_oxygen=parallel
	gpu.configure_interactions("chemistry");gpu.configure_exchange(8 if mode=="pipeline" else 1,mode=="pipeline")
	gpu.initialize(Fixture.make(50000,distribution),Fixture.flow())
	var status: Array=await gpu.ready
	if not status[0]: push_error(str(status[1]));quit(1);return
	var accounting: Dictionary={"accepted":0,"receipts":0,"intake":0.0}
	gpu.exchange_ready.connect(func(receipt):
		accounting.receipts+=1
		for i in cells.size():
			cells[i].substrate+=receipt.intake[i][0];cells[i].oxygen+=receipt.intake[i][1];cells[i].carbon+=receipt.intake[i][2]
			accounting.intake+=receipt.intake[i][0]+receipt.intake[i][1]+receipt.intake[i][2]
		for product in receipt.emissions:
			if product.accepted: accounting.accepted+=1)
	gpu.advance(1.0/60,0);gpu.exchange(cells,[],[],mode!="immediate");await gpu.exchange_ready
	var start:=Time.get_ticks_usec()
	var uploaded: int=gpu.exchange_upload_bytes
	var readback: int=gpu.exchange_readback_bytes
	var receipts_before: int=accounting.receipts
	var steps:=60
	for tick in steps:
		while gpu.exchange_busy: await gpu.exchange_ready
		gpu.advance(1.0/60,tick+1)
		var products: Array=[]
		for cell in cells:
			var at: Vector2=Fixture.wrapped(cell.position+Vector2(160,0))
			products.append({"owner":cell.id,"state":PackedFloat32Array([at.x,at.y,0,0,0,0,0,2,4.8,0.01,0,0])})
		if not gpu.exchange(cells,products,[],mode!="immediate"): push_error("Exchange rejected");quit(1);return
	while gpu.exchange_inflight>0: await gpu.exchange_ready
	var ms: float=(Time.get_ticks_usec()-start)/(steps*1000.0)
	gpu.snapshot();var state: PackedFloat32Array=await gpu.snapshot_ready
	var material:=0.0
	var alive:=0
	for i in 50000:
		material+=state[i*12+9]
		if state[i*12+7]>=0: alive+=1
	print("QUEUE_BENCH ",JSON.stringify({"distribution":distribution,"mode":mode,"repeat":repeat,"parallel_oxygen":parallel,
		"starting_slots":50000,"alive":alive,"cells":8,"large_cell_radius":141,"completed_ms_per_step":ms,
		"steps":steps,"receipts":accounting.receipts-receipts_before,"peak_inflight":gpu.exchange_peak_inflight,
		"uploaded_bytes_per_step":(gpu.exchange_upload_bytes-uploaded)/steps,
		"readback_bytes_per_step":(gpu.exchange_readback_bytes-readback)/steps,"fallbacks":gpu.exchange_fallbacks,
		"emitted":accounting.accepted*0.01,"refused_escrow":(steps*8-accounting.accepted)*0.01,"particle_material":material,"intake":accounting.intake,
		"scope":"Fixed-capacity cell exchange, transport, matching and exclusion; no physiology, sensing or full scene"}))
	gpu.close();await gpu.closed
