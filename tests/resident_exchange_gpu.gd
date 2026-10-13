extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Cell=preload("res://scripts/cell.gd")
const Exchange=preload("res://scripts/resident_exchange.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func packet(kind: int,at: Vector2,amount: float=0.3) -> PackedFloat32Array:
	return PackedFloat32Array([at.x,at.y,0,0,0,0,0,kind,6,amount,0,0])
func setup(data: PackedFloat32Array):
	var gpu=GPU.new()
	check(gpu.configure_interactions("chemistry") and gpu.configure_exchange(),"Enable bridge")
	gpu.initialize(data,Fixture.flow())
	var status: Array=await gpu.ready
	check(status[0],str(status[1]))
	return gpu
func run() -> void:
	Fixture.load_native()
	print("EXCHANGE phase feeding")
	await finite_feeding()
	print("EXCHANGE phase geometry")
	await oxygen_and_carbon()
	await geometry()
	print("EXCHANGE phase identity")
	await identity_and_emissions()
	await coarse_feeding()
	await coarse_hazard()
	print("EXCHANGE_VALIDATION ",checks," checks")
	quit()
func finite_feeding() -> void:
	var a=Cell.new(71,Vector2(4090,100))
	var b=Cell.new(72,Vector2(4090,100))
	a.add_organ("feeding",0,"graze",false);b.add_organ("feeding",0,"graze",false)
	# Duplicate mouth is deliberate: shared capacity, not one budget per pore.
	a.organs.append(a.organs[0].duplicate())
	a.substrate=a.gut_capacity()-0.2;b.substrate=b.gut_capacity()-0.15
	a.oxygen=a.oxygen_capacity();b.oxygen=b.oxygen_capacity()
	var at: Vector2=a.pore_center(a.organs[0]);at.x=fposmod(at.x,4096)
	var data:=packet(0,at,0.5)
	var gpu=await setup(data)
	check(gpu.exchange([a,b]),"Submit overlapping consumers")
	check(not gpu.exchange([a,b]),"One outstanding transaction")
	var receipt: Dictionary=await gpu.exchange_ready
	check(is_equal_approx(receipt.intake[0][0],0.2),"Shared pore capacity")
	var kernels=preload("res://scripts/backend.gd").create()
	if kernels!=null:
		var packets: Array=[{"p":at,"kind":0,"amount":0.5,"alive":true,"owner":-1}]
		var ids: Array[int]=[0]
		var before_a: float=a.substrate
		var before_b: float=b.substrate
		for organ in a.organs: kernels.feed(packets,ids,a,organ,a.position,Vector2(800,500))
		for organ in b.organs: kernels.feed(packets,ids,b,organ,b.position,Vector2(800,500))
		check(absf(a.substrate-before_a-receipt.intake[0][0])<0.000001,"Native first-cell intake agrees")
		check(absf(b.substrate-before_b-receipt.intake[1][0])<0.000001,"Native competing-cell intake agrees")
	check(is_equal_approx(receipt.intake[1][0],0.15),"Second cell takes only remainder within budget")
	check(is_equal_approx(receipt.pores[0],0.2) and receipt.pores[1]==0,"No duplicated pore credit")
	gpu.snapshot();var out: PackedFloat32Array=await gpu.snapshot_ready
	check(absf(out[9]+receipt.intake[0][0]+receipt.intake[1][0]-0.5)<0.000001,"Finite total material")
	check(gpu.exchange_readback_bytes<256,"Small receipt, no pool readback")
	check(gpu.exchange_fallbacks==0,"Async readback supported")
	gpu.close();await gpu.closed
func geometry() -> void:
	var cell=Cell.new(9,Vector2(4090,2550))
	cell.angle=0.7
	cell.oxygen=cell.oxygen_capacity()
	for i in cell.membrane.COUNT:
		cell.membrane.points[i]*=1.0+0.2*sin(i*TAU/cell.membrane.COUNT*3)
	cell.membrane.maximum_radius=57
	cell.membrane.invalidate()
	var data:=PackedFloat32Array()
	for i in 129:
		data.append_array(packet(2,Fixture.wrapped(cell.position+Vector2.from_angle(i*0.7)*10)))
	data.append_array(packet(3,cell.position))
	var gpu=await setup(data)
	check(gpu.exchange([cell]),"Deformed seam projection")
	await gpu.exchange_ready
	gpu.snapshot();var out: PackedFloat32Array=await gpu.snapshot_ready
	for i in 129:
		var before:=Vector2(data[i*12],data[i*12+1])
		var d:=Fixture.wrapped(before-cell.position+Fixture.WORLD*0.5)-Fixture.WORLD*0.5
		var angle:=d.angle() if d.length_squared()>0.0001 else i*2.4
		var expected:=Fixture.wrapped(cell.position+Vector2.from_angle(angle)*(cell.visible_support(angle-cell.angle)+7))
		var error:=Fixture.wrapped(Vector2(out[i*12],out[i*12+1])-expected+Fixture.WORLD*0.5)-Fixture.WORLD*0.5
		check(error.length()<0.01,"GPU follows deformed outline")
		check(out[i*12+9]==data[i*12+9],"Projection preserves amount")
	check(out[129*12]==data[129*12] and out[129*12+1]==data[129*12+1],"Pheromone ignores membrane")
	gpu.close();await gpu.closed
func identity_and_emissions() -> void:
	var cell=Cell.new(2,Vector2(100,100))
	cell.add_organ("feeding",0,"graze",false)
	cell.oxygen=cell.oxygen_capacity()
	var at: Vector2=cell.pore_center(cell.organs[0])
	var gpu=await setup(packet(0,at))
	var emission: Dictionary={"state":packet(0,Vector2(1000,1000),0.2),"owner":2}
	check(gpu.exchange([], [emission], [Vector2i(0,1)]),"Full pool test")
	var full: Dictionary=await gpu.exchange_ready
	check(not full.emissions[0].accepted,"Capacity refusal keeps original")
	check(full.inspections[0].valid and full.inspections[0].state[9]>0.29,"Original handle still live")
	check(gpu.exchange([cell],[emission],[Vector2i(0,1)]),"Reuse consumed slot")
	var reused: Dictionary=await gpu.exchange_ready
	check(is_equal_approx(reused.intake[0][0],0.3),"Original paid into cell")
	check(reused.emissions[0].accepted and reused.emissions[0].handle==Vector2i(0,2),"New generation on reuse")
	check(not reused.inspections[0].valid,"Stale handle rejected")
	check(gpu.exchange([],[],[Vector2i(0,2)]),"Sparse inspection")
	var inspected: Dictionary=await gpu.exchange_ready
	check(inspected.inspections[0].valid and inspected.inspections[0].owner==2,"Emission identity and owner")
	check(absf(inspected.inspections[0].state[9]-0.2)<0.000001,"Emission quantity")
	check(not gpu.exchange([], [{"state":packet(0,Vector2.ZERO),"owner":-2}]),"Invalid request rejected without mutation")
	# Pending receipts must finish before GPU resources are freed.
	check(gpu.exchange([],[],[Vector2i(0,2)]),"Pending close")
	gpu.close()
	await gpu.exchange_ready
	await gpu.closed
	check(true,"Close drains pending asynchronous receipt")

func oxygen_and_carbon() -> void:
	var cell=Cell.new(4,Vector2(600,500))
	cell.add_organ("photosynthesis",0,"graze",false)
	cell.oxygen=cell.oxygen_capacity()-0.1
	cell.carbon=float(preload("res://scripts/chemistry_catalog.gd").data().ecology.carbon_capacity)*cell.growth_scale()-0.15
	var data:=packet(1,cell.position+Vector2(49,0),0.3)
	data.append_array(packet(5,cell.position+Vector2(49,0),0.3))
	var gpu=await setup(data)
	check(gpu.exchange([cell],[],[],false),"Blocking receipt comparison")
	var result: Dictionary=await gpu.exchange_ready
	check(absf(result.intake[0][1]-0.1)<0.000002,"Oxygen storage limit")
	check(absf(result.intake[0][2]-0.15)<0.000002,"Photosynthesis carbon storage limit")
	var kernels=preload("res://scripts/backend.gd").create()
	if kernels!=null:
		var packets: Array=[
			{"p":cell.position+Vector2(49,0),"kind":1,"amount":0.3,"alive":true,"owner":-1},
			{"p":cell.position+Vector2(49,0),"kind":5,"amount":0.3,"alive":true,"owner":-1}]
		var ids: Array[int]=[0,1]
		var oxygen: float=cell.oxygen
		var carbon: float=cell.carbon
		kernels.feed(packets,ids,cell,{},cell.position,Vector2(800,500))
		check(absf(cell.oxygen-oxygen-result.intake[0][1])<0.000002,"Native oxygen agreement")
		check(absf(cell.carbon-carbon-result.intake[0][2])<0.000002,"Native carbon agreement")
	gpu.close();await gpu.closed


func coarse_feeding() -> void:
	var a=Cell.new(81,Vector2(3800,100))
	var b=Cell.new(82,a.position)
	for cell in [a,b]:
		cell.add_organ("feeding",0,"graze",false)
		cell.substrate=cell.gut_capacity()-.15;cell.oxygen=cell.oxygen_capacity()
	# Hidden packet competes between two cells; wrapped foreground packet is
	# protected even though the widened collection sphere reaches it.
	var data:=packet(0,Vector2(3700,100),.5)
	data.append_array(packet(0,Vector2(4,100),.5))
	var gpu=await setup(data)
	var rates: Dictionary={}
	for cell in [a,b]: rates[cell.id]={"dt":.1,"radius":400,"nutrient":1000,"oxygen":0,"carbon":0,"seed":91}
	var options: Dictionary={"coarse":rates,"scope":Vector4(4090,100,20,20),"projection":false}
	var receipt: Dictionary=gpu.exchange_sync([a,b],[],[],[],options)
	check(not receipt.has("error"),"Coarse requests accepted")
	check(absf(receipt.intake[0][0]-.15)<.00001 and absf(receipt.intake[1][0]-.15)<.00001,"Coarse consumers share real packet and individual capacity")
	gpu.snapshot();var values: PackedFloat32Array=await gpu.snapshot_ready
	check(absf(values[9]-.2)<.00001 and values[21]==.5,"Widened feeding leaves foreground material untouched across seam")
	check(absf(values[9]+values[21]+receipt.intake[0][0]+receipt.intake[1][0]-1)<.00001,"Coarse competition conserves material")
	gpu.close();await gpu.closed

func coarse_hazard() -> void:
	# Compare one leap with two half leaps against the same exponential hazard.
	# Tiny packets avoid storage caps biasing the statistical measurement.
	const N:=4096
	var totals: Array[float]=[]
	for steps in [1,2]:
		var cell=Cell.new(83,Vector2(1000,1000))
		cell.add_organ("feeding",0,"graze",false);cell.oxygen=cell.oxygen_capacity()
		var data:=PackedFloat32Array()
		for i in N: data.append_array(packet(0,cell.position+Vector2(80+i%8,i%11),.00001))
		var gpu=await setup(data)
		var total:=0.0
		for j in steps:
			var rate: Dictionary={83:{"dt":.1/steps,"radius":100,"nutrient":4,"oxygen":0,"carbon":0,"seed":400+j}}
			var result: Dictionary=gpu.exchange_sync([cell],[],[],[],{"coarse":rate,"projection":false})
			check(not result.has("error"),"Hazard leap accepted")
			total+=result.intake[0][0]
		totals.append(total/.00001/N)
		check(absf(totals[-1]-(1-exp(-.4)))<.035,"Finite packet uptake matches elapsed-time hazard within sampling error")
		gpu.close();await gpu.closed
	check(absf(totals[0]-totals[1])<.035,"Halving the coarse step does not double feeding")
