extends SceneTree
const GPU=preload("res://scripts/resident_particles.gd")
const Fixture=preload("res://scripts/resident_fixture.gd")
var checks:=0
func _initialize() -> void: run.call_deferred()
func require(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok,message)
func hash_key(v: int) -> int:
	v=(v^(v>>16))*0x7feb352d&0xffffffff
	v=(v^(v>>15))*0x846ca68b&0xffffffff
	return (v^(v>>16))&0xffffffff
func run() -> void:
	for count in [2,3,129]:
		var data:=Fixture.make(count,"uniform")
		for i in count:
			var k: int=i*12
			data[k]=4095.0 if i%2==0 else 1.0
			data[k+1]=100
			data[k+2]=0 if i%2==0 else PI
			data[k+7]=0;data[k+8]=8;data[k+9]=0.2
		for tick in 8:
			await check_fixture(data,count,tick)
	# Misalignment must suppress reactions, not collisions.
	var data:=Fixture.make(2,"uniform")
	data[0]=100;data[1]=100;data[12]=102;data[13]=100
	data[2]=0;data[14]=0
	data[7]=0;data[19]=0;data[8]=8;data[20]=8;data[9]=0.2;data[21]=0.2
	await check_fixture(data,2)
	for config in [[7,11,0.4,2,-1],[7,12,0.4,2,-1],[6,2,0.4,6,0],[6,2,0.95,6,2],[7,4,0.4,2,-1],[8,9,0.4,2,2],[2,1,0.4,0,5],[0,4,0.4,2,4]]:
		await reaction_case(config)
	await delayed_products()
	print("MATCHING_VALIDATION ",checks," checks")
	quit()
func check_fixture(data: PackedFloat32Array,count: int,tick: int=0) -> void:
	var expected:=PackedInt32Array();expected.resize(count);expected.fill(-1)
	for i in count:
		var best: Array=[]
		for j in count:
			if i==j or data[i*12+9]+data[j*12+9]>float(preload("res://scripts/chemistry_catalog.gd").data().ecology.merge_limit): continue
			var low:=mini(i,j);var high:=maxi(i,j)
			var d:=Vector2(fposmod(data[high*12]-data[low*12]+2048,4096)-2048,
				fposmod(data[high*12+1]-data[low*12+1]+1280,2560)-1280)
			if d.length_squared()>64: continue
			var n:=d.normalized() if d.length_squared()>0.000001 else Vector2.RIGHT
			var alignment:=minf(Vector2.from_angle(data[low*12+2]).dot(n),Vector2.from_angle(data[high*12+2]).dot(-n))
			if alignment<0.5: continue
			var score: Array=[int(clampf(alignment,0,1)*1024),hash_key(low^hash_key(high)^hash_key(tick)),low,high]
			var better:=best.is_empty()
			if not better:
				for k in 4:
					if score[k]!=best[k]:
						better=score[k]>best[k];break
			if better: best=score;expected[i]=j
	var gpu=GPU.new()
	gpu.reaction_tick=tick
	require(gpu.configure_interactions("chemistry"),"Configure")
	gpu.initialize(data,Fixture.flow())
	var status: Array=await gpu.ready
	require(status[0],str(status[1]))
	gpu.interact_only()
	gpu.contact_snapshot()
	var contacts: Dictionary=await gpu.contacts_ready
	gpu.snapshot()
	var output: PackedFloat32Array=await gpu.snapshot_ready
	var reactions:=0
	var total:=0.0
	for i in count:
		require(contacts.choices[i]==expected[i],"Vote mismatch at "+str(i))
		var j:=expected[i]
		var mutual:=j>=0 and expected[j]==i
		if mutual and i<j: reactions+=1
		require(output[i*12+7]==(-1.0 if mutual and i>j else 0.0),"Disjoint consumption")
		require(is_equal_approx(output[i*12+9],0.0 if mutual and i>j else (data[i*12+9]+data[j*12+9] if mutual else data[i*12+9])),"Finite material")
		total+=output[i*12+9]
	require(is_equal_approx(total,count*0.2),"Material conservation")
	require(contacts.stats[4]==reactions,"Reaction count")
	gpu.close();await gpu.closed

func reaction_case(config: Array) -> void:
	var data:=Fixture.make(2,"uniform")
	data[0]=100;data[1]=100;data[12]=102;data[13]=100
	data[2]=0;data[14]=PI;data[8]=8;data[20]=8
	data[7]=config[0];data[19]=config[1];data[9]=0.3;data[21]=0.3
	data[10]=0.2;data[22]=0.2
	var gpu=GPU.new()
	gpu.configure_interactions("chemistry",config[2])
	gpu.initialize(data,Fixture.flow())
	var status: Array=await gpu.ready
	require(status[0],str(status[1]))
	gpu.interact_only();gpu.snapshot()
	var output: PackedFloat32Array=await gpu.snapshot_ready
	require(output[7]==config[3] and output[19]==config[4],"Reaction products "+str(config))
	if config[0]==8: require(absf(output[10])+absf(output[22])<0.000001,"Neutralization charge")
	if config[0]==2: require(is_equal_approx(output[9],0.18) and is_equal_approx(output[21],0.12),"Recycling material")
	gpu.close();await gpu.closed

func delayed_products() -> void:
	var data:=Fixture.make(4,"uniform")
	for i in 4:
		data[i*12]=102 if i==1 else 100
		data[i*12+1]=100
		data[i*12+2]=PI if i==1 else 0
		data[i*12+7]=[6,2,4,3][i]
		data[i*12+8]=8;data[i*12+9]=0.3
	var gpu=GPU.new()
	gpu.configure_interactions("chemistry")
	gpu.initialize(data,Fixture.flow())
	var status: Array=await gpu.ready
	require(status[0],str(status[1]))
	gpu.interact_only();gpu.snapshot()
	var first: PackedFloat32Array=await gpu.snapshot_ready
	require(first[19]==0,"Digested nutrient survives first update")
	require(first[43]==3 and first[40]==data[40] and first[41]==data[41],"Pheromone ignores collisions")
	gpu.interact_only();gpu.snapshot()
	var second: PackedFloat32Array=await gpu.snapshot_ready
	require(second[19]==2,"Product becomes eligible next update")
	gpu.close();await gpu.closed
