extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Cell=preload("res://scripts/cell.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func packet(kind: int,at: Vector2,angle: float=0,amount: float=.2) -> PackedFloat32Array:
	return PackedFloat32Array([at.x,at.y,angle,0,0,0,0,kind,8,amount,amount,0])
func setup(data: PackedFloat32Array,metadata: Array):
	var gpu=GPU.new()
	gpu.configure_interactions("chemistry");gpu.configure_exchange();gpu.configure_perception();gpu.configure_exposure()
	gpu.initialize(data,Fixture.flow(),metadata)
	var status: Array=await gpu.ready;check(status[0],str(status[1]))
	return gpu
func query(mode: String,at: Vector2,reach: float=30) -> Dictionary:
	return {"at":at,"reach":reach,"id":0,"lineage":0,"mass":20,"mode":mode,"target_id":-1,"incumbent":false}
func run() -> void:
	var cell=Cell.new(0,Vector2(2048,1280))
	cell.add_organ("feeding",0,"graze",false)
	var organ: Dictionary=cell.organs[0]
	var center: Vector2=cell.organ_position(organ)
	var direction: Vector2=cell.organ_normal(organ).rotated(cell.angle)
	var data:=packet(4,cell.position)
	data.append_array(packet(4,cell.position+Vector2(1,0)))
	data.append_array(packet(10,center+direction*8,(-direction).angle(),.13))
	data.append_array(packet(10,center+direction*9,direction.angle(),.17))
	data.append_array(packet(2,Vector2(100,100)))
	var gpu=await setup(data,[{"slot":0,"owner":5,"lineage":0},{"slot":1,"owner":6,"lineage":6},{"slot":2,"owner":6},{"slot":3,"owner":6}])
	var needs: Dictionary=gpu.exchange_sync([],[],[],[query("waste",Vector2(100,100)),query("toxin",cell.position),query("inspect",Vector2(100,100))],{"projection":false})
	check(needs.senses[0].valid and needs.senses[1].valid,"Local secretion demand reads real packets")
	check(needs.senses[2].state[7]==2 and needs.senses[2].handle.x==4,"Sparse picking returns slot generation and species")
	var lens:=query("inspect",Vector2(110,100));lens["inner"]=3.0
	var missed: Dictionary=gpu.exchange_sync([],[],[],[lens],{"projection":false})
	check(not missed.senses[0].valid,"Lens rejects a center outside its rendered hit area")
	lens.inner=.5
	var found: Dictionary=gpu.exchange_sync([],[],[],[lens],{"projection":false})
	check(found.senses[0].valid,"Lens hit area remains usable when zoomed out")
	var receipt: Dictionary=gpu.exchange_sync([cell],[],[],[],{"feeding":false,"exposure":true,"projection":false})
	check(receipt.exposure.hits[0].size()==1,"Toxins spare inherited family")
	check(is_equal_approx(receipt.exposure.hits[0][0].amount,.2),"Finite toxin transferred exactly once")
	check(receipt.exposure.hits[0][0].owner==6,"Damage credit retains chemical owner")
	check(receipt.exposure.decoys[0].count==1 and is_equal_approx(receipt.exposure.decoys[0].amount,.13),"Only correctly facing decoy occupies receptor")
	var again: Dictionary=gpu.exchange_sync([cell],[],[],[query("toxin",cell.position)],{"feeding":false,"exposure":true,"projection":false})
	check(again.exposure.hits[0].is_empty() and again.exposure.decoys[0].count==0,"Contact receipts cannot double consume")
	check(not again.senses[0].valid,"Neutralizer ignores remaining family toxin")
	gpu.close();await gpu.closed
	# More than one compact receipt is drained before exclusion, with no damage
	# or material dropped and no packet consumed by overlapping bodies twice.
	data=PackedFloat32Array()
	var metadata: Array=[]
	for i in 140:
		data.append_array(packet(4,cell.position+Vector2.from_angle(i)*2,0,.01))
		metadata.append({"slot":i,"owner":7,"lineage":7})
	gpu=await setup(data,metadata)
	var other=Cell.new(1,cell.position)
	receipt=gpu.exchange_sync([cell,other],[],[],[],{"feeding":false,"exposure":true,"projection":false})
	check(receipt.exposure.hits[0].size()==128 and receipt.exposure.deferred==12,"Contact overflow remains resident until drained")
	check(receipt.exposure.hits[1].is_empty(),"Overlapping cells never both consume a toxin")
	again=gpu.exchange_sync([cell,other],[],[],[],{"feeding":false,"exposure":true,"projection":false})
	check(again.exposure.hits[0].size()==12 and again.exposure.deferred==0,"Overflow finishes without losing toxins")
	var final: Dictionary=gpu.exchange_sync([cell,other],[],[],[],{"feeding":false,"exposure":true,"projection":false})
	check(final.exposure.hits[0].is_empty(),"Drained exposure stays empty")
	gpu.close();await gpu.closed
	await coarse_exposure()
	await surface_assemblies()
	print("RESIDENT_EXPOSURE_VALIDATION ",checks," checks")
	quit()

func coarse_exposure() -> void:
	var cell=Cell.new(21,Vector2(1000,1000))
	var data:=PackedFloat32Array()
	var metadata: Array=[]
	for i in 2048:
		data.append_array(packet(4,cell.position+Vector2.from_angle(i)*2,0,.00001))
		metadata.append({"slot":i,"owner":22 if i<1024 else 21,"lineage":22 if i<1024 else 21})
	var gpu=await setup(data,metadata)
	var rates: Dictionary={21:{"dt":.1,"radius":150,"nutrient":0,"oxygen":0,"carbon":0,"seed":78}}
	var options: Dictionary={"feeding":false,"exposure":true,"projection":false,"coarse":rates}
	var receipt: Dictionary=gpu.exchange_sync([cell],[],[],[],options)
	var expected: int=receipt.exposure.hits[0].size()+receipt.exposure.deferred
	check(expected>128 and absf(expected-1024*(1-exp(-.2)))<40,"Offscreen toxin hazard is time-scaled and family-safe")
	var total: int=receipt.exposure.hits[0].size()
	while receipt.exposure.deferred>0:
		receipt=gpu.exchange_sync([cell],[],[],[],options)
		total+=receipt.exposure.hits[0].size()
	check(total==expected,"Overflow retry never rerolls the coarse exposure lottery")
	receipt=gpu.exchange_sync([cell],[],[],[],options)
	check(receipt.exposure.hits[0].is_empty(),"Completed hazard interval cannot consume more toxins")
	gpu.close();await gpu.closed


func surface_assemblies() -> void:
	var cell=Cell.new(20,Vector2(2048,1280))
	var normal:=Vector2.RIGHT
	var at: Vector2=cell.position+cell.local_point(0)
	var data:=packet(11,at,PI,.03)
	data.append_array(packet(12,at,PI,.0375))
	data.append_array(packet(11,at,PI,.03))
	var gpu=await setup(data,[{"slot":0,"owner":21,"lineage":21},{"slot":1,"owner":21,"lineage":21},{"slot":2,"owner":20,"lineage":20}])
	var result: Dictionary=gpu.exchange_sync([cell],[],[],[],{"feeding":false,"exposure":true,"projection":false})
	check(result.exposure.hits[0].size()==2,"Only foreign, correctly facing surface packets bind")
	check(result.exposure.hits[0][0].kind==11 and result.exposure.hits[0][1].kind==12,"Exposure receipt retains surface species and ordered finite subunits")
	var Surface=preload("res://scripts/surface_chemistry.gd")
	for hit in result.exposure.hits[0]:
		check(Surface.bind(cell,hit.kind,hit.amount,hit.angle),"GPU-bound subunits form the same finite CPU membrane complex")
	check(absf(cell.surface_material()-.0675)<.000001,"Bound GPU chemical material is retained exactly")
	var again: Dictionary=gpu.exchange_sync([cell],[],[],[],{"feeding":false,"exposure":true,"projection":false})
	check(again.exposure.hits[0].is_empty(),"Surface packets cannot be consumed twice")
	gpu.close();await gpu.closed
