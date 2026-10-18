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
	check(changed>0 and peak<30,"Induced currents add bounded local forcing instead of globally accelerating water")
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
	var a:=Currents.sources(17,Currents.PERIOD-.001);var b:=Currents.sources(17,Currents.PERIOD+.001)
	check(float(a[0].envelope)<.0001 and float(b[0].envelope)<.0001,"A relocated source fades out and back in at its cycle boundary")
	var minimum_peak:=1.0;var minimum_active:=Currents.COUNT
	var valid:=true;var moving:=true;var kinds: Dictionary={}
	for seed_number in [17,44,81,123456]:
		for step in 80:
			var instant:=step*.25
			var events:=Currents.sources(seed_number,instant)
			var future:=Currents.sources(seed_number,instant+.001)
			var strongest:=0.0;var active:=0
			for i in events.size():
				var event: Dictionary=events[i]
				strongest=maxf(strongest,event.envelope)
				if event.envelope>.1:active+=1
				kinds[event.kind]=true
				var diameter: float=event.radius*2/Currents.UNITS_PER_UM
				var speed: float=event.migration.length()/Currents.UNITS_PER_UM
				valid=valid and diameter>=29.999 and diameter<=100.001 and speed>=9.999 and speed<=50.001 and event.duration>=1 and event.duration<=20
				if event.age<19.999:
					moving=moving and Sim.Medium.offset(event.p,future[i].p).distance_to(event.migration*.001)<.002
			minimum_peak=minf(minimum_peak,strongest);minimum_active=mini(minimum_active,active)
	check(minimum_peak>.99,"Every sampled time and seed has a fully active event, including lifetime boundaries")
	check(minimum_active>=4,"Several staggered short events remain active across the pond")
	check(valid,"All events are30–100um across, migrate10–50um/s and last1–20seconds")
	check(moving,"Spiral and directional event centers really migrate at their authored velocities")
	check(kinds.has("spiral") and kinds.has("directional"),"Both spiral eddies and directional currents are present")
	var spiral: Dictionary=items.filter(func(event):return event.kind=="spiral")[0].duplicate()
	spiral.envelope=1.0
	var swirl:=Currents.forcing(spiral.p+Vector2(spiral.radius*.5,0),[spiral])
	check(swirl.x<0 and swirl.y*float(spiral.spin)>0,"Spiral events combine inward motion with their chosen rotation direction")
	var directional: Dictionary=items.filter(func(event):return event.kind=="directional")[0].duplicate()
	directional.envelope=1.0
	var ahead:=Currents.forcing(directional.p+Vector2(directional.radius*.5,0),[directional])
	var behind:=Currents.forcing(directional.p-Vector2(directional.radius*.5,0),[directional])
	check(ahead.dot(behind)>0 and ahead.normalized().dot(directional.heading)>.999,"Directional events push the whole local patch along their migration heading")
	var raster_error:=0.0
	for i in tide.size():
		var at:=Vector2(i%Sim.Medium.COLS+.5,int(i/Sim.Medium.COLS)+.5)*Sim.Medium.SIZE
		raster_error=maxf(raster_error,tide[i].distance_to(sim.fluid.current(at)+Currents.forcing(at,items)))
	check(raster_error<.0001,"Sparse local rasterization matches the authoritative wrapped event field")
	print("CURRENT_EVENTS minimum_active_peak=%.4f minimum_active_count=%d sources=%d" % [minimum_peak,minimum_active,Currents.COUNT])
	var cell=sim.player;var assembly={"a":.4,"units":3,"capped":false}
	var state: Array=cell.surface_complexes.duplicate(true)
	var pose:=preload("res://scripts/pore_art.gd").layout(cell,assembly)
	check((pose.at-cell.local_point(.4)).dot(cell.local_normal(.4))>0 and pose.units==3,"Pore assemblies attach to the actual membrane with their retained part count")
	check(cell.surface_complexes==state,"Pore presentation cannot add material or change chemistry")
	# An existing saved weather sample upgrades its target without resetting water.
	var weather=preload("res://scripts/environment_cycle.gd")
	var saved_flow=Sim.new(17,0,false);saved_flow.time=123
	var now:=1792324800.0
	weather.update(saved_flow,now)
	var stronger: PackedVector2Array=saved_flow.fluid.tide.duplicate()
	check(saved_flow.environment.flow_strength>=1.3 and saved_flow.environment.flow_strength<=2.6,"Hourly broad forcing is twice the former range")
	var retained_velocity: PackedVector2Array=saved_flow.fluid.velocity.duplicate()
	saved_flow.environment.flow_version=3;saved_flow.fluid.induced_base_key="stale"
	check(weather.update(saved_flow,now) and saved_flow.fluid.velocity==retained_velocity and saved_flow.fluid.tide==stronger,"Saved weather upgrades within the hour without resetting physical flow")
	check(saved_flow.fluid.induced_base_key=="","A flow upgrade invalidates derived induced-current bases")
	print("INDUCED CURRENTS: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
