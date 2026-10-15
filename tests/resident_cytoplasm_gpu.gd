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
	var sim=preload("res://scripts/simulation.gd").new(41,0,false);sim.cells=[cell];sim.player=cell;sim.particles=[]
	for i in 120:
		cell.chemistry.advance(cell,.1);cell.chemistry.excrete(sim,cell,.1)
	var released:=0.0
	for packet in sim.particles:released+=packet.amount
	check(cell.chemistry.particle_count()==0 and released>0 and sim.particles.all(func(packet):return packet.kind==2),"Resident food finishes as waste and exits through the cytoproct")
	check(absf(cell.organic_mass()+released-matter)<.000001,"Resident expulsion transfers every represented material unit exactly once")
	for i in 100:cell.chemistry.emit("food",.1,Vector2.from_angle(i)*30)
	check(cell.chemistry.particle_count()<=24,"Resident carrier count remains bounded under dense intake")
	check(cell.chemistry.particles.is_empty(),"Intake never creates a CPU mirror")
	cell.chemistry.ensure_cpu();check(cell.chemistry.accelerator==null and cell.chemistry.particles.size()<=24,"Coarse handoff exports finite vacuoles once")
	var invalid=Cell.new()
	for i in 25:invalid.chemistry.particles.append(cell.chemistry.particles[0].duplicate(true))
	var rejected=Cytoplasm.new()
	check(not rejected.attach(gpu,invalid.chemistry,invalid) and invalid.chemistry.particles.size()==25 and invalid.chemistry.accelerator==null,"Oversized handoff fails without truncating finite CPU inventory")
	print("CYTOPLASM GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
