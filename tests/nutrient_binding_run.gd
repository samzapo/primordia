extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Cell=Sim.Cell
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:
		failures+=1;push_error(text);quit(1)
		assert(ok,text)
func _initialize() -> void:run.call_deferred()
func pair(acid: float,pool: bool=false,mutual: bool=false,background: bool=false) -> Array:
	var sim=Sim.new(902)
	sim.particles=[];sim.grid.clear();sim.revision=1;sim.time=1
	sim.camera_follows_player=false;sim.camera_position=Vector2(100,100)
	for i in 2:
		sim.spawn_particle(0,Vector2(100+i*2,100),Vector2.ZERO,60,i)
		sim.particles[i].angle=acos(.8) if i==0 else PI+acos(.8)
		sim.particles[i].direction=Vector2.from_angle(sim.particles[i].angle)
		sim.particles[i].chemical_at=sim.time-.000001
	sim.acidity.values.fill(acid);sim.grid.rebuild(sim.particles)
	if sim.kernels!=null:sim.kernels.pair_matching_configure(mutual)
	if pool:
		sim.enable_particle_pool()
		check(sim.particle_pool,"The native fixture actually owns a particle pool")
	if sim.kernels!=null:sim.kernels.packet_begin(sim.particles)
	sim._chemistry(.000001,[0,1],background)
	if sim.kernels!=null:sim.kernels.packet_end()
	return sim.particle_snapshots()
func digest(bonus: float,oxygen: bool):
	var cell=Cell.new(78);cell.energy=0;cell.biomass=0
	cell.chemistry.receive(0,8,8*(1+bonus),cell.position+Vector2(30,0))
	if oxygen:cell.chemistry.emit("oxygen",8,cell.chemistry.particles[0].p,-1,-1,0)
	return cell
func run() -> void:
	for pool in [false,true]:
		if pool and preload("res://scripts/backend.gd").create()==null:continue
		for mutual in [false,true]:
			for background in [false,true]:
				var plain: Array=pair(0,pool,mutual,background)
				var mild: Array=pair(.25,pool,mutual,background)
				var harsh: Array=pair(.95,pool,mutual,background)
				check(plain.filter(func(p):return p.alive).size()==2 and harsh.filter(func(p):return p.alive).size()==2,"Neutral/excess acid retain narrow nutrient binding faces")
				var living:=mild.filter(func(p):return p.alive)
				check(living.size()==1 and living[0].amount==120,"Mild acid helps real production-sized nutrient parcels combine")
				check(absf(living[0].capacity-168)<.00001,"Mild-acid equal-size join carries40% ATP allocation benefit")
				check(absf(living[0].amount-120)<.000001,"Binding preserves combined material")
	for coarse in [false,true]:uptake(coarse)
	var cap:=1.0;var mass:=1.0
	for i in 20:
		cap=Sim.Catalog.nutrient_capacity(mass,cap,mass,cap);mass*=2
		check(cap<=mass*1.5+.000001,"Repeated joins stay below50% ATP benefit")
	check(Sim.Catalog.nutrient_capacity(1,.9999999,1,1)<2,"Even a tiny fuel deficit cannot be refueled by binding")
	check(Sim.Catalog.nutrient_capacity(2,0,2,0)==0,"Depleted nutrients cannot regain fuel from binding")
	check(Sim.Catalog.nutrient_capacity(2,3,2,0)==2,"Mixing depleted food preserves actual fuel and loses only allocation benefit")
	for oxygen in [false,true]:
		var plain=digest(0,oxygen);var rich=digest(.2,oxygen)
		var before: float=rich.organic_mass()
		plain.chemistry.advance(plain,1);rich.chemistry.advance(rich,1)
		check(absf(rich.energy/plain.energy-1.2)<.000001,"Bound nutrients yield20% more ATP per consumed unit")
		check(absf(rich.organic_mass()-before)<.000001,"Extra ATP does not delete or create material")
		check(absf(rich.energy+rich.biomass*7.5+rich.chemistry.raw_fuel()+rich.chemistry.heat-8*Cell.Chemistry.FOOD_FUEL)<.000001,"Existing fuel pays for ATP, biomass and heat")
		if oxygen:check(absf(rich.biomass-plain.biomass)<.000001 and rich.chemistry.heat<plain.chemistry.heat,"Fresh food quality recovers finite heat without reducing tissue")
		else:check(absf(rich.biomass-plain.biomass)<.000001 and rich.chemistry.heat<plain.chemistry.heat,"Fermentation recovers otherwise dissipated heat first")
		var codec=preload("res://scripts/network/state_codec.gd").new()
		var copy=codec.restore(codec.capture(rich))
		check(copy.chemistry.particles==rich.chemistry.particles,"Nutrition survives exact checkpoint recovery")
	var dying=digest(.2,true);var death_sim=Sim.new(909)
	death_sim.cells=[dying];death_sim.particles=[];death_sim.grid.clear()
	death_sim.evolution.enabled=false;death_sim._die(dying)
	var released=death_sim.particles.filter(func(p):return p.kind==0 and p.get("capacity",0)>p.amount)
	check(released.size()==1 and absf(released[0].capacity/released[0].amount-1.2)<.000001,"Lysis preserves ingested nutrient quality without refueling it")
	if "--gpu" in OS.get_cmdline_user_args():
		await gpu_pairs()
		await gpu_uptake()
		var resident=preload("res://scripts/resident_particles.gd").new();resident.rd=RenderingServer.get_rendering_device()
		for oxygen in [false,true]:
			var gpu=digest(.2,oxygen);var cpu=Cell.clone_state(gpu)
			check(preload("res://scripts/resident_cytoplasm.gd").new().attach(resident,gpu.chemistry,gpu),"Nutrition can enter the resident GPU owner")
			for i in 10:gpu.chemistry.advance(gpu,.1);cpu.chemistry.advance(cpu,.1)
			check(absf(gpu.energy-cpu.energy)<.000001 and absf(gpu.biomass-cpu.biomass)<.000001,"Resident digestion shares the same ATP/biomass tradeoff")
			check(gpu.chemistry.particles.is_empty() and gpu.chemistry.accelerator.exports==0,"Bonus digestion uses no CPU pose mirror")
			var codec=preload("res://scripts/network/state_codec.gd").new()
			var restored=codec.restore(codec.capture(gpu))
			check(absf(restored.chemistry.particles[0].nutrition-cpu.chemistry.particles[0].nutrition)<.000001,"A live GPU checkpoint retains the current bonus, not its admission-time value")
			gpu.chemistry.ensure_cpu()
			check(absf(gpu.chemistry.particles[0].nutrition-cpu.chemistry.particles[0].nutrition)<.000001,"Coarse handoff retains the remaining weighted bonus")
	print("NUTRIENT BINDING: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
func gpu_pairs() -> void:
	var fixture=preload("res://scripts/resident_fixture.gd")
	for acid in [0.0,.25,.95]:
		var data: PackedFloat32Array=fixture.make(2)
		for i in 2:
			var k:=i*12
			data[k]=100+i*2;data[k+1]=100;data[k+2]=acos(.8) if i==0 else PI+acos(.8)
			data[k+7]=0;data[k+8]=8;data[k+9]=60;data[k+10]=60
		var gpu=preload("res://scripts/resident_particles.gd").new()
		gpu.configure_interactions("chemistry",acid);gpu.initialize(data,fixture.flow())
		var status: Array=await gpu.ready;check(status[0],str(status[1]))
		gpu.interact_only();gpu.snapshot()
		var output: PackedFloat32Array=await gpu.snapshot_ready
		check((output[19]<0)==(acid==.25),"Actual GPU nutrient joining uses the acid optimum")
		if acid==.25:check(absf(output[9]-120)<.00001 and absf(output[10]-168)<.00001,"Actual GPU binding preserves amount and creates only allocation benefit")
		gpu.close();await gpu.closed


func uptake(coarse: bool) -> void:
	var sim=Sim.new(903);var cell=sim.player
	sim.cells=[cell];sim.particles=[];sim.grid.clear()
	cell.substrate=cell.gut_capacity()-.5
	var mouth: Dictionary=cell.organs.filter(func(o):return o.kind=="feeding")[0]
	var at: Vector2=cell.pore_center(mouth)
	sim.spawn_particle(0,at,Vector2.ZERO,1);sim.particles[0].capacity=1.2
	sim.grid.rebuild(sim.particles)
	if coarse:
		sim.camera_follows_player=false;sim.camera_position=cell.position+Vector2(1500,1000)
		preload("res://scripts/offscreen_ecology.gd").new()._feed(sim,cell,10000)
	else:sim._feed(cell)
	var bonus:=0.0
	for packet in cell.chemistry.particles:bonus+=float(packet.get("nutrition",0))
	check(absf(bonus-.1)<.000001,"Fine/coarse partial uptake preserves the weighted ATP bonus")
	check(absf(sim.particles[0].amount-.5)<.000001 and absf(sim.particles[0].capacity-.6)<.000001,"Fine/coarse partial uptake leaves the matching external profile")

func gpu_uptake() -> void:
	var cell=Cell.new(77,Vector2(300,300))
	cell.add_organ("feeding",0,"graze",false);cell.substrate=cell.gut_capacity()-.5
	cell.oxygen=cell.oxygen_capacity()
	var at: Vector2=cell.pore_center(cell.organs[0])
	var data:=PackedFloat32Array([at.x,at.y,0,0,0,0,0,0,8,1,1.2,0])
	var gpu=preload("res://scripts/resident_particles.gd").new()
	check(gpu.configure_interactions("chemistry") and gpu.configure_exchange(),"The resident uptake bridge is available")
	gpu.initialize(data,preload("res://scripts/resident_fixture.gd").flow())
	var status: Array=await gpu.ready;check(status[0],str(status[1]))
	check(gpu.exchange([cell]),"The GPU accepts a finite nutrient uptake transaction")
	var receipt: Dictionary=await gpu.exchange_ready
	check(absf(receipt.pores[0]-.5)<.000001 and absf(receipt.pore_fuel[0]-.6)<.000001,"Resident partial uptake transfers the entire food profile")
	gpu.snapshot();var output: PackedFloat32Array=await gpu.snapshot_ready
	check(absf(output[9]-.5)<.000001 and absf(output[10]-.6)<.000001,"Resident partial uptake retains the remaining external food profile")
	gpu.close();await gpu.closed
