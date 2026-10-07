extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
static func fixture(enabled: bool,guard: String = "none"):
	var sim = Sim.new(831)
	sim.particles.clear()
	sim.pheromones.clear()
	sim.grid.rebuild(sim.particles)
	sim.fluid.velocity.fill(Vector2(24,-9))
	for i in 96:
		sim.spawn_particle(Sim.ENZYME if i%3==0 else Sim.ANTITOXIN if i%3==1 else Sim.WASTE,Vector2(2000+i%8,1200+i/8),Vector2(3+i%3,1),0.3,7)
		sim.particles[-1]["capacity"] = 0.6+i*0.001
		sim.particles[-1]["product"] = i*0.002
	sim.spawn_particle(Sim.PHEROMONE,Vector2(2000,1200),Vector2.ZERO,1,9)
	sim.configure_parcels(enabled)
	var centers := PackedVector2Array([Vector2(20,20)])
	var radii := PackedFloat32Array([30])
	if guard == "cell": centers[0] = Vector2(2000,1200)
	if guard == "large": radii[0] = 10000
	if guard == "invalid": radii[0] = -1
	if guard == "shear":
		for y in Sim.Medium.ROWS:
			for x in Sim.Medium.COLS: sim.fluid.velocity[y*Sim.Medium.COLS+x] = Vector2(100*sin(x*1.5),0)
	sim.kernels.parcel_protect(centers,radii)
	return sim

static func run(check: Callable) -> void:
	var probe = Sim.new(31)
	if probe.kernels == null:
		check.call(not probe.configure_parcels(true),"Script fallback rejects native parcels explicitly")
		return
	for guard in ["none","cell","large","invalid","shear"]:
		var individual = fixture(false,guard)
		var grouped = fixture(true,guard)
		var ids: Array[int] = []
		for i in 97: ids.append(i)
		var before := grouped.particle_snapshots()
		for sim in [individual,grouped]:
			sim.kernels.packet_begin([])
			sim.kernels.transport([],ids,sim.fluid.velocity,Vector2.ZERO,Vector2(100,100),0.5,1,sim.background_rng,0.5,true)
		var a := individual.particle_snapshots()
		var b := grouped.particle_snapshots()
		var preserved := true
		var same := true
		for i in a.size():
			same = same and Sim.Medium.offset(a[i].p,b[i].p).length()<0.002 and a[i].v==b[i].v and a[i].angle==b[i].angle and a[i].age==b[i].age
			preserved = preserved and b[i].amount==before[i].amount and b[i].get("product",0)==before[i].get("product",0) and b[i].get("capacity",0)==before[i].get("capacity",0) and b[i].kind==before[i].kind and b[i].owner==before[i].owner and b[i]._handle==before[i]._handle
		check.call(same,"Shared integration matches constant flow, or uses individual fallback: "+guard)
		check.call(preserved and grouped.kernels.pool_material()==individual.kernels.pool_material(),"Parcels retain finite child material, identity, species and ownership")
		check.call(grouped.background_rng.state==individual.background_rng.state,"Parcels keep independent child diffusion/rotation draw order")
		var metrics: Dictionary = grouped.kernels.parcel_metrics()
		check.call((metrics.children>0 if guard=="none" else metrics.children==0),"Protection and shear gates apply before shared transport: "+guard)
		check.call(b[96].p==a[96].p and b[96].angle==0,"Pheromones never enter material parcels")
		check.call(grouped.configure_particle_engine("current") and grouped.integration_half!=Vector2.ZERO,"Selecting current physics preserves parcel zoom isolation")
		var prior: float = grouped.kernels.pool_material()
		check.call(grouped.configure_parcels(false) and grouped.integration_half==Vector2.ZERO and grouped.kernels.pool_material()==prior,"Disabling parcels changes no inventory")

	# Zoom and free-pan are purely display state while grouping is enabled.
	var fixed = fixture(true)
	var zoomed = fixture(true)
	for sim in [fixed,zoomed]: sim.view_half = Sim.VIEW/0.8/2; sim.integration_half = sim.view_half
	for tick in 60:
		zoomed.view_half = Sim.VIEW/(12 if tick%2==0 else 0.8)/2
		zoomed.camera_follows_player = tick%2==0
		zoomed.camera_position = Vector2(2000,1200)
		fixed.step(1.0/60)
		zoomed.step(1.0/60)
	check.call(preload("res://tests/packed_particles.gd").same_packets(fixed.particle_snapshots(),zoomed.particle_snapshots()),"Zoom/pan cannot change parcel transport or reaction state")
	check.call(preload("res://tests/particle_pool.gd").same_cells(fixed,zoomed),"Zoom/pan cannot increase feeding, ATP or tissue with parcels")
	check.call([fixed.rng.state,fixed.background_rng.state,fixed.ecology_rng.state]==[zoomed.rng.state,zoomed.background_rng.state,zoomed.ecology_rng.state],"Parcel experiment preserves zoom-independent random streams")
