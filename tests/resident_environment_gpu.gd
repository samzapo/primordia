extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
const Acidity=preload("res://scripts/acidity.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: push_error(message);quit(1);assert(ok,message)
func packet(kind: int,at: Vector2,amount: float=.3,capacity: float=0,angle: float=0) -> PackedFloat32Array:
	return PackedFloat32Array([at.x,at.y,angle,0,0,0,0,kind,6,amount,capacity,0])
func setup(data: PackedFloat32Array,acid: PackedFloat32Array,seed: int=3900):
	var gpu=GPU.new()
	check(gpu.configure_interactions("chemistry") and gpu.configure_exchange() and gpu.configure_perception(),"Configure")
	check(gpu.configure_chemistry(acid,seed),"Finite environmental chemistry")
	check(not gpu.configure_interactions("contacts"),"Cannot disable required chemistry pipeline")
	var flow:=PackedVector2Array();flow.resize(2560)
	gpu.initialize(data,flow)
	var status: Array=await gpu.ready;check(status[0],str(status[1]))
	return gpu
func run() -> void:
	await finite_acid()
	await tiny_spent_charge()
	await spatial_pair_rules()
	await decay_and_inventory()
	await flow_update()
	await expanded_inventory()
	print("ENVIRONMENT_VALIDATION ",checks," checks")
	quit()
func receipt(gpu) -> Dictionary:
	check(gpu.exchange([],[],[],false),"Environment-only receipt")
	return await gpu.exchange_ready
func finite_acid() -> void:
	var acid=Acidity.new();acid.values[65]=.95
	var data:=packet(8,Vector2(82,82),.3,.1)
	data.append_array(packet(9,Vector2(111,111),.3,.12))
	data.append_array(packet(8,Vector2(78,110),.3,.8))
	var seed:=0
	while true:
		var safe:=true
		for i in 3:
			var random:=Fixture.hash32(i^Fixture.hash32(0)^Fixture.hash32(1)^seed)
			if ((random>>8)+.5)/16777216.0<.1: safe=false
		if safe: break
		seed+=1
	var expected:=PackedFloat32Array([.1,.12,.8])
	for i in 3:
		var used: float=absf(acid.exchange(Vector2(96,96),(-1 if i==1 else 1)*minf(expected[i],.4)))
		expected[i]-=used
	var initial:=PackedFloat32Array();initial.resize(2560);initial[65]=.95
	var gpu=await setup(data,initial,seed)
	gpu.advance(2,0)
	var r:=await receipt(gpu)
	check(absf(r.chemistry.acid[65]-acid.values[65])<.000001,"Finite field exchange agrees with scalar slot order")
	gpu.snapshot();var out: PackedFloat32Array=await gpu.snapshot_ready
	for i in 3:
		check(int(out[i*12]/64)==1 and int(out[i*12+1]/64)==1,"Fixture stays in intended field node")
		check(absf(out[i*12+10]-expected[i])<.000001,"Particle only spends effective acid/buffer charge")
	check(out[19]==2,"Exhausted buffer becomes waste")
	check(r.chemistry.loss==0 and r.chemistry.alive==3 and r.chemistry.decay==0,"No unaccounted decay")
	check(absf(r.chemistry.material-.9)<.000001,"Field exchange preserves chemical material")
	gpu.close();await gpu.closed
func spatial_pair_rules() -> void:
	for level in [.4,.95]:
		var field:=PackedFloat32Array();field.resize(2560);field.fill(.4);field[65]=level
		var data:=packet(6,Vector2(96,96),.3,0,0)
		data.append_array(packet(2,Vector2(101,96),.3,0,PI))
		var gpu=await setup(data,field)
		gpu.interact_only()
		var r:=await receipt(gpu)
		gpu.snapshot();var out: PackedFloat32Array=await gpu.snapshot_ready
		check(out[19]==(0 if level<.9 else 2),"Pair uses local acid field rather than fixed fixture acidity")
		check(r.chemistry.pairs[4]==(1 if level<.9 else 0),"Pair event counters copied with environmental receipt")
		gpu.close();await gpu.closed
func decay_and_inventory() -> void:
	var field:=PackedFloat32Array();field.resize(2560)
	var data:=PackedFloat32Array();var seed:=390071
	var expected_decay:=0;var expected_loss:=0.0;var expected_alive:=50000
	var initial_material:=0.0;var initial_oxygen:=0.0;var oxygen_loss:=0.0
	var dt:=1.0/60
	for i in 50000:
		var kind: int=[0,1,4][i%3]
		var at:=Vector2((i%256)*16+8,(i/256)*12+8)
		data.append_array(packet(kind,at,.01))
		if kind==1: initial_oxygen+=.01
		else: initial_material+=.01
		var random:=Fixture.hash32(i^Fixture.hash32(0)^Fixture.hash32(1)^seed)
		if ((random>>8)+.5)/16777216.0<1-exp(-preload("res://scripts/chemistry_catalog.gd").decay(kind)*dt):
			expected_decay+=1;expected_alive-=1
			if kind==1: oxygen_loss+=.01
			else: expected_loss+=.01
	var gpu=await setup(data,field,seed)
	gpu.advance(dt,0)
	var r:=await receipt(gpu)
	check(r.chemistry.decay==expected_decay and r.chemistry.alive==expected_alive,"Counter-based decay probability and live inventory")
	check(absf(r.chemistry.loss-expected_loss)<.00001,"Organic decay is explicitly accounted")
	check(r.chemistry.pairs[4]==0,"Parallel-facing fixture excludes pair chemistry")
	check(absf(r.chemistry.material+expected_loss-initial_material)<.0001,"Finite organic inventory after decay")
	check(absf(r.chemistry.oxygen+oxygen_loss-initial_oxygen)<.0001,"Finite oxygen inventory after decay")
	check(gpu.readbacks==0,"Environmental totals do not require particle snapshots")
	gpu.close();await gpu.closed
func flow_update() -> void:
	var field:=PackedFloat32Array();field.resize(2560)
	var data:=packet(0,Vector2(300,200))
	var gpu=await setup(data,field)
	var flow:=PackedVector2Array();flow.resize(2560);flow.fill(Vector2(80,15))
	check(gpu.environment(flow,field),"Update real flow without replacing particle state")
	gpu.advance(1.0/60,0)
	await receipt(gpu)
	gpu.snapshot();var out: PackedFloat32Array=await gpu.snapshot_ready
	var expected:=Fixture.advance(data,flow,1.0/60,0)
	expected[8]=8.0 # Pair commit normalizes nutrient diameter from its amount.
	check(Fixture.compare(expected,out).passed,"Updated fluid drives resident transport")
	field[10]=-1
	check(not gpu.environment(flow,field),"Invalid environmental field rejected")
	gpu.close();await gpu.closed


func expanded_inventory() -> void:
	var field:=PackedFloat32Array();field.resize(2560)
	var data:=packet(13,Vector2(300,200),.2)
	data.append_array(packet(22,Vector2(302,200),3))
	data.append_array(packet(20,Vector2(304,200),1))
	data.append_array(packet(11,Vector2(400,200),.03))
	var gpu=await setup(data,field)
	var r: Dictionary=gpu.exchange_sync([],[],[],[],{"projection":false,"scope":Vector4(300,200,20,20)})
	check(absf(r.chemistry.material-.23)<.000001,"Spilled ATP/redox carriers carry no represented organic mass")
	check(r.chemistry.visible=={"chemicals":3,"material":1,"signals":0},"GPU census uses the exact viewport and shared material definitions")
	check(gpu.readbacks==0,"On-screen counts use compact receipts without downloading the particle pool")
	gpu.close();await gpu.closed

func tiny_spent_charge() -> void:
	var field:=PackedFloat32Array();field.resize(2560);field.fill(.4)
	for kind in [8,9]:
		var data:=packet(kind,Vector2(96,96),.3,.00000002)
		var gpu=await setup(data,field)
		gpu.advance(1./30,0)
		await receipt(gpu);gpu.snapshot()
		var state: PackedFloat32Array=await gpu.snapshot_ready
		check(state[10]>=0 and state[7]==2,"Sub-ULP spent acid/buffer charge cannot become negative")
		gpu.close();await gpu.closed
	var sim=preload("res://scripts/simulation.gd")
	var small: Dictionary={"kind":2,"capacity":-.00000002421439,"amount":.18}
	check(sim.repair_spent_charge(small) and small.capacity==0 and small.amount==.18,"Known saved roundoff is repaired without changing chemical material")
	check(not sim.repair_spent_charge({"kind":0,"capacity":-.00000002}) and not sim.repair_spent_charge({"kind":2,"capacity":-.1}),"Negative nutrient fuel or substantive corruption is not silently repaired")
