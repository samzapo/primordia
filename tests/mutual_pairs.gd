extends RefCounted
const Sim=preload("res://scripts/simulation.gd")
static func run(check: Callable) -> void:
	var native=preload("res://scripts/backend.gd").create()
	if native==null: return
	closed_accounting(check)
	for kinds in [[6,2],[7,4],[8,9],[2,1],[0,4],[0,0]]:
		for reversed_order in [false,true]:
			for acid in [0.4,0.95]:
				var sims: Array=[]
				for matching in [false,true]:
					var sim=Sim.new(847)
					sim.particles.clear();sim.grid.rebuild(sim.particles)
					var pair: Array=kinds.duplicate()
					if reversed_order: pair.reverse()
					sim.spawn_particle(pair[0],Vector2(4094,900),Vector2.ZERO,0.3,0)
					sim.spawn_particle(pair[1],Vector2(2,900),Vector2.ZERO,0.3,1)
					sim.particles[0].direction=Vector2.RIGHT
					sim.particles[1].direction=Vector2.LEFT
					sim.acidity.values.fill(acid);sim.rng.seed=781
					sim.camera_follows_player=false;sim.camera_position=Vector2(4094,900)
					sim.grid.rebuild(sim.particles)
					sim.enable_particle_pool();sim.kernels.pair_matching_configure(matching)
					sim.revision+=1
					sim.kernels.packet_begin(sim.particles)
					sim._chemistry(0.0000001)
					sim.kernels.packet_end()
					sims.append(sim)
				var a: Array=sims[0].particle_snapshots();var b: Array=sims[1].particle_snapshots()
				for i in 2:
					check.call(a[i].kind==b[i].kind and a[i].alive==b[i].alive,"Mutual pair species/alive result")
					check.call(absf(a[i].amount-b[i].amount)<0.000001 and absf(a[i].capacity-b[i].capacity)<0.000001,"Mutual pair finite amount/charge")

static func material(sim) -> float:
	var total: float=sim.lineage.stored_material()
	for cell in sim.cells:
		if not cell.dead: total+=cell.organic_mass()
	for p in sim.particle_snapshots():
		if p.alive and p.kind not in [Sim.OXYGEN,Sim.PHEROMONE]: total+=p.amount+p.get("product",0.0)
	return total
static func closed_accounting(check: Callable) -> void:
	for seed in [41,847,3307,9821]:
		var sim=Sim.new(seed)
		sim.cells=[sim.player];sim.pending_replacements.clear()
		sim.particles.clear();sim.grid.rebuild(sim.particles)
		sim.player.add_organ("regenerative",2.1,"graze",false)
		sim.player.waste+=sim.player.damage(25,-PI*0.5)
		for i in 40:
			for kind in [Sim.OXYGEN,Sim.NUTRIENT,Sim.WASTE,Sim.ENZYME,Sim.TOXIN,Sim.ANTITOXIN]:
				sim.spawn_particle(kind,sim.player.position+Vector2.from_angle(i)*70,Vector2.ZERO,0.1)
		sim.grid.rebuild(sim.particles);sim.enable_particle_pool()
		sim.kernels.pair_matching_configure(true)
		var before:=material(sim)
		for tick in 180: sim.step(1.0/60)
		check.call(absf(material(sim)+sim.respiration_loss-before-sim.external_input)<0.01,"Mutual closed ecosystem accounts for every material unit")
