extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Cell=preload("res://scripts/cell.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Fixture.load_native()
	for distribution in ["uniform","clustered"]:
		for asynchronous in [false,true]:
			await measure(distribution,asynchronous)
	quit()
func measure(distribution: String,asynchronous: bool) -> void:
	var cells: Array=[]
	for i in 8:
		var cell=Cell.new(i+1,Vector2(2048,1280)+Vector2.from_angle(TAU*i/8)*270)
		cell.add_organ("feeding",0,"graze",false)
		cell.add_organ("photosynthesis",PI,"graze",false)
		if i==0:
			for j in cell.membrane.COUNT: cell.membrane.points[j]*=3
			cell.membrane.maximum_radius*=3;cell.membrane.invalidate()
		cells.append(cell)
	var gpu=GPU.new()
	gpu.configure_interactions("chemistry");gpu.configure_exchange()
	gpu.initialize(Fixture.make(50000,distribution),Fixture.flow())
	var status: Array=await gpu.ready
	if not status[0]: push_error(str(status[1]));quit(1);return
	gpu.advance(1.0/60,0)
	gpu.exchange(cells,[],[],asynchronous);var warm: Dictionary=await gpu.exchange_ready
	credit(cells,warm)
	var start:=Time.get_ticks_usec()
	var uploaded: int=gpu.exchange_upload_bytes
	var readback: int=gpu.exchange_readback_bytes
	var emission_paid:=0.0
	var emission_accepted:=0.0
	for tick in 30:
		gpu.advance(1.0/60,tick+1)
		# Fixture-owned escrow: refused products remain here, never vanish.
		var products: Array=[]
		for cell in cells:
			var at: Vector2=Fixture.wrapped(cell.position+Vector2(160,0))
			products.append({"owner":cell.id,"state":PackedFloat32Array([at.x,at.y,0,0,0,0,0,2,4.8,0.01,0,0])})
			emission_paid+=0.01
		if not gpu.exchange(cells,products,[],asynchronous): push_error("Exchange rejected");quit(1);return
		var receipt: Dictionary=await gpu.exchange_ready
		credit(cells,receipt)
		for product in receipt.emissions:
			if product.accepted: emission_accepted+=0.01
	var elapsed: float=(Time.get_ticks_usec()-start)/30000.0
	print("EXCHANGE_BENCH ",JSON.stringify({"distribution":distribution,"async":asynchronous,"starting_slots":50000,
		"cells":8,"large_cell_radius":141,"mean_completed_step_ms":elapsed,
		"uploaded_bytes_per_step":(gpu.exchange_upload_bytes-uploaded)/30,
		"readback_bytes_per_step":(gpu.exchange_readback_bytes-readback)/30,
		"fallbacks":gpu.exchange_fallbacks,"emitted":emission_accepted,"refused_escrow":emission_paid-emission_accepted}))
	gpu.close();await gpu.closed
func credit(cells: Array,receipt: Dictionary) -> void:
	for i in cells.size():
		cells[i].substrate+=receipt.intake[i][0]
		cells[i].oxygen+=receipt.intake[i][1]
		cells[i].carbon+=receipt.intake[i][2]
