extends SceneTree
const Currents=preload("res://scripts/induced_currents.gd")
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
var failures:=0
var assertions:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=Sim.new(17,0,false)
	sim.time=913.5
	var random_state: int=sim.rng.state
	var velocity: PackedVector2Array=sim.fluid.velocity.duplicate()
	var items:=Currents.sources(sim.seed_value,sim.time)
	check(items==Currents.sources(sim.seed_value,sim.time),"Current sources are reproducible from retained seed and world time")
	check(items!=Currents.sources(18,sim.time),"Different ponds receive different irregular current sources")
	Currents.update(sim)
	var tide: PackedVector2Array=sim.fluid.tide.duplicate()
	check(sim.fluid.velocity==velocity and sim.rng.state==random_state,"Updating weak forcing never resets physical water or consumes ecology RNG")
	var peak:=0.0;var changed:=0
	for i in tide.size():
		var at:=Vector2(i%Sim.Medium.COLS+.5,int(i/Sim.Medium.COLS)+.5)*Sim.Medium.SIZE
		peak=maxf(peak,(tide[i]-sim.fluid.current(at)).length())
		if tide[i].distance_to(sim.fluid.current(at))>.01:changed+=1
	check(changed>0 and peak<12,"Induced currents add bounded local forcing instead of globally accelerating water")
	var reference=Sim.Medium.new()
	reference.tide=tide;reference.velocity=velocity;reference.activity.fill(1)
	var native: PackedVector2Array=reference.kernels.fluid_step(velocity,reference.activity,tide,.25,true) if reference.kernels!=null else PackedVector2Array()
	reference.step(.25)
	if not native.is_empty():
		var error:=0.0
		for i in native.size():error=maxf(error,native[i].distance_to(reference.velocity[i]))
		check(error<.0001,"Native and reference solvers use the same induced target")
	var graph:=Codec.new().capture(sim)
	var restored=Codec.new().restore(graph)
	restored.fluid.induced_key="";Currents.update(restored)
	check(restored.fluid.tide==tide,"Restart derives the same forcing without rerolling sources")
	var point: Vector2=items[0].p+Vector2(50,20)
	check(Currents.forcing(point,items).distance_to(Currents.forcing(point+Sim.WORLD,items))<.0001,"Current forcing is continuous across the wrapped pond")
	var a:=Currents.sources(17,119.999);var b:=Currents.sources(17,120.001)
	check(float(a[0].envelope)<.000001 and float(b[0].envelope)<.000001,"A relocated source fades out and back in at its cycle boundary")
	var cell=sim.player;var assembly={"a":.4,"units":3,"capped":false}
	var state: Array=cell.surface_complexes.duplicate(true)
	var pose:=preload("res://scripts/pore_art.gd").layout(cell,assembly)
	check((pose.at-cell.local_point(.4)).dot(cell.local_normal(.4))>0 and pose.units==3,"Pore assemblies attach to the actual membrane with their retained part count")
	check(cell.surface_complexes==state,"Pore presentation cannot add material or change chemistry")
	print("INDUCED CURRENTS: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
