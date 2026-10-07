extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func make_gpu(data: PackedFloat32Array,backend: String,mode: String="chemistry"):
	var gpu=GPU.new()
	check(gpu.configure_grid(backend),"Grid configuration")
	gpu.configure_interactions(mode);gpu.initialize(data,Fixture.flow())
	var status: Array=await gpu.ready
	check(status[0],str(status[1]))
	return gpu
func run() -> void:
	for count in [1,127,128,129,4097,50000,100000]:
		var data:=Fixture.make(count,"uniform")
		for i in count:
			# Include inactive sentinels and occupied boundary bins.
			if i%7==0: data[i*12+7]=-1
			if i%11==0: data[i*12]=4095.99;data[i*12+1]=2559.99
		await grid(data)
	# A pathological bin must remain exact without capped occupancy.
	var packed:=Fixture.make(50000,"seam")
	for i in 50000: packed[i*12]=4;packed[i*12+1]=4;packed[i*12+7]=2
	await grid(packed)
	for i in 50000: packed[i*12+7]=-1
	await grid(packed)
	for distribution in ["uniform","clustered","seam"]:
		for count in [129,4097]:
			await compare(Fixture.make(count,distribution),20 if distribution!="seam" else 2)
	print("RADIX_VALIDATION ",checks," checks")
	quit()
func grid(data: PackedFloat32Array) -> void:
	var gpu=await make_gpu(data,"radix","contacts")
	RenderingServer.call_on_render_thread(gpu._prepare_grid_rd)
	gpu.contact_snapshot();var actual: Dictionary=await gpu.contacts_ready
	var count: int=data.size()/12
	var expected: Array=[]
	for i in gpu.padded_count:
		var key:=0xffffffff
		if i<count and data[i*12+7]>=0 and data[i*12+7]!=3:
			key=int(floor(fposmod(data[i*12+1],2560)/16))*256+int(floor(fposmod(data[i*12],4096)/16))
		expected.append([key,i])
	expected.sort_custom(func(a,b): return a[0]<b[0] or (a[0]==b[0] and a[1]<b[1]))
	var ranges:=PackedInt32Array();ranges.resize(40960*2)
	var correct:=true
	for i in expected.size():
		var key: int=expected[i][0]
		correct=correct and (actual.order[i*2]&0xffffffff)==key and actual.order[i*2+1]==expected[i][1]
		if key<40960:
			if i==0 or expected[i-1][0]!=key: ranges[key*2]=i
			ranges[key*2+1]=i+1
	check(correct,"Canonical grid order at capacity "+str(count))
	check(actual.ranges==ranges,"Exact periodic ranges at capacity "+str(count))
	check(gpu.grid_dispatches==14,"Bounded radix dispatch count")
	check(not gpu.configure_grid("bitonic"),"Cannot replace live GPU resources")
	gpu.close();await gpu.closed
func compare(data: PackedFloat32Array,ticks: int) -> void:
	var outputs: Array=[]
	var contacts: Array=[]
	for backend in ["bitonic","radix"]:
		var gpu=await make_gpu(data,backend)
		for tick in ticks: gpu.advance(1.0/60,tick)
		gpu.snapshot();outputs.append(await gpu.snapshot_ready)
		gpu.contact_snapshot();contacts.append(await gpu.contacts_ready)
		gpu.close();await gpu.closed
	check(outputs[0]==outputs[1],"Bit-identical transport, impulses, matching and material")
	for field in ["order","ranges","counts","choices","stats"]:
		check(contacts[0][field]==contacts[1][field],"Equivalent "+field)
