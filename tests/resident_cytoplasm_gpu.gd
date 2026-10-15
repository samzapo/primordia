extends SceneTree
const Cell=preload("res://scripts/cell.gd")
const GPU=preload("res://scripts/resident_particles.gd")
const Cytoplasm=preload("res://scripts/resident_cytoplasm.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var beacon:=ColorRect.new();beacon.size=Vector2(8,8);root.add_child(beacon)
	await process_frame;await process_frame
	var gpu=GPU.new();gpu.rd=RenderingServer.get_rendering_device()
	var cell=Cell.new(42);cell.energy=0;cell.chemistry.receive(0,8,6,cell.local_point(0))
	var cpu=Cell.clone_state(cell)
	var matter: float=cell.organic_mass()
	check(Cytoplasm.new().attach(gpu,cell.chemistry,cell),"Resident backend owns visible food/waste")
	check(cell.chemistry.particles.is_empty(),"GPU authority leaves no CPU pose mirror")
	for i in 60:
		cell.chemistry.advance(cell,1.0/60);cpu.chemistry.advance(cpu,1.0/60)
	check(absf(cell.energy-cpu.energy)<.000001 and absf(cell.biomass-cpu.biomass)<.000001,"CPU/GPU digestion credits identical numeric resources")
	check(absf(cell.organic_mass()-matter)<.000001,"Resident digestion conserves finite material")
	check(cell.chemistry.accelerator.exports==0,"Fine digestion uses compact receipts without full exports")
	var copy=preload("res://scripts/network/state_codec.gd").new().restore(preload("res://scripts/network/state_codec.gd").new().capture(cell))
	check(absf(copy.organic_mass()-matter)<.000001 and copy.energy==cell.energy,"Detached checkpoint preserves resident resources")
	cell.chemistry.advance(cell,8)
	check(cell.substrate>0 and cell.chemistry.vacuoles.filter(func(v):return v.get("species","carrier")=="carrier").size()==1 and cell.chemistry.vacuoles[0].age>8.99,"Resident digestion retains one moving food/waste carrier for at least ten seconds")
	var sim=preload("res://scripts/simulation.gd").new(41,0,false);sim.cells=[cell];sim.player=cell;sim.particles=[]
	for i in 300:
		cell.chemistry.advance(cell,.1);cell.chemistry.excrete(sim,cell,.1)
	var released:=0.0
	for packet in sim.particles:released+=packet.amount
	check(cell.substrate<.0000001 and cell.waste<.0000001 and released>0 and sim.particles.all(func(packet):return packet.kind in [2,5]),"Resident food finishes as waste and exits through the cytoproct")
	check(absf(cell.organic_mass()+released-matter)<.000001,"Resident expulsion transfers every represented material unit exactly once")
	for i in 100:cell.chemistry.emit("food",.1,Vector2.from_angle(i)*30)
	check(cell.chemistry.particle_count()<=cell.chemistry.MAX_PACKETS,"Resident carrier count remains bounded under dense intake")
	check(cell.chemistry.particles.is_empty(),"Intake never creates a CPU mirror")
	cell.chemistry.ensure_cpu();check(cell.chemistry.accelerator==null and cell.chemistry.particles.size()<=cell.chemistry.MAX_PACKETS,"Coarse handoff exports finite vacuoles once")
	var transient_cell=Cell.new();transient_cell.chemistry.emit("food",.1,Vector2(30,0))
	check(Cytoplasm.new().attach(gpu,transient_cell.chemistry,transient_cell),"Inspection topology fixture owns resident material")
	transient_cell.chemistry.particle_snapshots(true)
	transient_cell.chemistry.advance(transient_cell,10.0)
	check(transient_cell.chemistry.particle_snapshots(true).any(func(stock):return stock.species=="waste"),"A food-to-waste identity change invalidates the optical snapshot immediately")
	transient_cell.chemistry.ensure_cpu()
	var wide=Cell.new()
	var wide_comp: int=(1<<53)+(1<<31)+17
	var wide_source: int=(1<<53)+5
	wide.chemistry.emit("food",1,Vector2(30,0),wide_source,wide_comp)
	check(Cytoplasm.new().attach(gpu,wide.chemistry,wide),"A full-width compartment can enter the resident device")
	wide.chemistry.advance(wide,1)
	var wide_packets: Array=wide.chemistry.particle_snapshots()
	check(wide_packets.filter(func(stock):return stock.species in ["food","waste"]).all(func(stock):return stock.compartment==wide_comp and stock.source==wide_source) and wide.chemistry.vacuoles.any(func(v):return v.id==wide_comp),"Food/waste carrier identity and compact picking preserve all 64 bits, including a signed low word")
	wide.chemistry.ensure_cpu()
	var invalid=Cell.new()
	for i in 25:invalid.chemistry.particles.append(cell.chemistry.particles[0].duplicate(true))
	var rejected=Cytoplasm.new()
	check(not rejected.attach(gpu,invalid.chemistry,invalid) and invalid.chemistry.particles.size()==25 and invalid.chemistry.accelerator==null,"Oversized handoff fails without truncating finite CPU inventory")
	var breathing=Cell.new(73);breathing.chemistry.emit("food",2,Vector2(30,0));breathing.chemistry.emit("oxygen",2,Vector2(30,0),-1,-1,0)
	var breathing_cpu=Cell.clone_state(breathing)
	check(Cytoplasm.new().attach(gpu,breathing.chemistry,breathing),"Resident gas intake owns finite oxygen")
	for i in 60:
		breathing.chemistry.advance(breathing,1.0/60);breathing_cpu.chemistry.advance(breathing_cpu,1.0/60)
	check(absf(breathing.energy-breathing_cpu.energy)<.000001 and absf(breathing.biomass-breathing_cpu.biomass)<.000001 and absf(breathing.oxygen-breathing_cpu.oxygen)<.000001,"Local oxygen-dependent respiration matches the CPU reference")
	check(breathing.chemistry.particles.is_empty() and breathing.chemistry.accelerator.exports==0,"Respiration needs no CPU particle mirror or full export")
	breathing.chemistry.ensure_cpu()
	var plant=Cell.new(74);plant.add_organ("photosynthesis",0,"graze",false);plant.chemistry.emit("carbon",2,plant.local_point(0)*.72,-1,-1,0)
	var plant_cpu=Cell.clone_state(plant)
	sim.player=plant
	check(Cytoplasm.new().attach(gpu,plant.chemistry,plant),"Resident photosynthesis owns carbon particles")
	plant.chemistry.photosynthesize(sim,plant,plant.organs[0],1);plant_cpu.chemistry.photosynthesize(sim,plant_cpu,plant_cpu.organs[0],1)
	check(plant.fixed_carbon>0 and absf(plant.fixed_carbon-plant_cpu.fixed_carbon)<.000001 and absf(plant.energy-plant_cpu.energy)<.000001 and absf(plant.oxygen-plant_cpu.oxygen)<.000001 and absf(plant.organic_mass()-plant_cpu.organic_mass())<.000001,"Resident photosynthesis produces the same finite food, oxygen and body resources")
	check(absf(plant.chemistry.solar_work-plant_cpu.chemistry.solar_work)<.000001,"Resident solar input is explicitly accounted")
	plant.chemistry.ensure_cpu()
	print("CYTOPLASM GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
