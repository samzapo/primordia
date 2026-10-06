extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const DT := 1.0/60
static func isolated():
	var sim = Sim.new(13013)
	sim.cells = [sim.player]
	sim.pending_replacements.clear()
	sim.particles.clear()
	sim.grid.rebuild(sim.particles)
	sim.player.organs.clear()
	sim.player.activity = 1
	sim.player.add_organ("hunting",0,"hunt",false)
	return sim
static func listen(sim, seconds: float = 0.5) -> void:
	for i in ceili(seconds/DT): sim._sense(sim.player,DT)
static func deliver(sim, source) -> Dictionary:
	var p: Dictionary = sim._emit_pheromone(source)
	p.p = sim.player.organ_position(sim.player.organs[0])+Vector2(30,0)
	p.previous = p.p
	p.expires_at = sim.time+10
	sim.grid.rebuild(sim.particles)
	return p
static func run(check: Callable) -> void:
	var sim = isolated()
	var prey = sim._make_cell(sim.player.position+Vector2(100,0),"grazer")
	listen(sim)
	check.call(sim.player.target_id == -1,"A nearby visible cell cannot be sensed without a pheromone")
	var p := deliver(sim,prey)
	var report: Dictionary = p.report.duplicate(true)
	prey.position += Vector2(600,80)
	prey.body = 900
	prey.add_organ("offensive",2,"graze",false)
	listen(sim)
	check.call(sim.player.target_id == prey.id and sim.player.target_position == report.at,"Pursuit uses the emitted location and size, never the live source")
	check.call(p.report == report and not report.hostile,"Emission metadata remains immutable when the creature changes")
	sim.cells.erase(prey)
	listen(sim)
	check.call(sim.player.target_id == prey.id,"A detached source's trail remains legible until decay, without a source lookup")
	sim.time = 1
	deliver(sim,prey)
	listen(sim,1.6)
	check.call(sim.player.target_id == -1,"A newer local report supersedes older lower-biomass bait from the same source")
	# Expired reports and signals cannot revive a target, even while offscreen.
	sim = isolated()
	prey = sim._make_cell(sim.player.position+Vector2(600,0),"grazer")
	p = deliver(sim,prey)
	listen(sim)
	check.call(sim.player.target_id == prey.id,"A distant creature is discoverable only after its plume reaches the receptor")
	p.expires_at = sim.time+0.01
	sim.player.signals.clear()
	sim.player.target_expires_at = p.expires_at
	sim.time = 20
	listen(sim)
	check.call(sim.player.target_id == -1 and sim.player.signals.is_empty(),"Global expiry clears pending and remembered reports")
	p.p = Vector2(50,50)
	sim._expire_pheromones()
	check.call(not p.alive,"Offscreen pheromones decay on the simulation clock")
	# Locality, periodic seams, own lineage and receptor occupation.
	sim = isolated()
	prey = sim._make_cell(sim.player.position+Vector2(600,0),"grazer")
	p = sim._emit_pheromone(prey)
	p.expires_at = 10
	listen(sim)
	check.call(sim.player.target_id == -1,"A remote pheromone cannot be read across the old long-range sensing radius")
	p.p = sim.player.organ_position(sim.player.organs[0])+Vector2(80,0)
	p.report.lineage = sim.player.lineage_id()
	sim.grid.rebuild(sim.particles)
	listen(sim)
	check.call(sim.player.target_id == -1,"Own-lineage reports are recognized from metadata")
	p.report.lineage = prey.lineage_id()
	sim.player.organs[0].blocked = 1
	listen(sim)
	check.call(sim.player.target_id == -1,"Decoy occupation reduces the local pheromone sampling reach")
	sim._clear_receptors(sim.player,10)
	listen(sim)
	check.call(sim.player.target_id == prey.id,"Receptor cleaning restores reception without consuming the pheromone")
	sim.player.position = Vector2(4090,1280)
	sim.player.target_memory = 0
	sim.player.signals.clear()
	p.p = Sim.Medium.wrap_position(sim.player.organ_position(sim.player.organs[0])+Vector2(30,0))
	p.report.at = Vector2(40,1280)
	sim.grid.rebuild(sim.particles)
	listen(sim)
	check.call(sim.player.target_id == prey.id and sim.player.facing.x > 0.9,"Sensing and reported coordinates wrap across the world seam")
	# Hostility is encoded from functional weapon anatomy, not a role label.
	sim = isolated()
	sim.player.organs.clear()
	sim.player.add_organ("sensing",0,"flee",false)
	prey = sim._make_cell(sim.player.position+Vector2(180,0),"grazer")
	prey.organs.clear()
	p = deliver(sim,prey)
	listen(sim)
	check.call(sim.player.target_id == -1,"Flight ignores a smaller unarmed reported creature")
	prey.add_organ("toxin",0,"graze",false)
	sim.time += 0.1
	p = deliver(sim,prey)
	prey.organs.clear()
	listen(sim)
	check.call(p.report.hostile and sim.player.target_mode == "flee" and sim.player.target.x < 0,"Flight responds to reported hostile anatomy even after the source disarms")
	sim.time += 0.1
	prey.body = 800
	p = deliver(sim,prey)
	check.call(not p.report.hostile,"Hostility is independent of body size and occupation label")
	listen(sim)
	check.call(sim.player.target_mode == "flee","An unarmed larger reported creature can also motivate explicit flight")
	# Chemistry and collision must not alter signal paths or payloads.
	sim = isolated()
	p = deliver(sim,sim.player)
	p.p = sim.player.position
	p.previous = p.p
	var before: Dictionary = p.duplicate(true)
	sim.spawn_particle(Sim.WASTE,p.p,Vector2(4,5),0.3,77)
	sim._chemistry(0.000001)
	check.call(p.p == before.p and p.v == before.v and p.report == before.report and p.alive,"Pheromones have no chemical reaction or particle collision")
	sim._exclude_particles()
	check.call(p.p == before.p and p.previous == before.previous,"Membrane exclusion does not shunt pheromones to the cell edge")
	var h = sim.habitat_geometry
	h.forms = [{"branches":[{"a":Vector2(-50,0),"b":Vector2(50,0),"r":5.0,"depth":2}]}]
	h.plants = [{"p":Vector2(2048,1280),"radius":100.0,"form":0,"angle":0.0}]
	h.rebuild()
	p.previous = Vector2(2048,1180)
	p.p = Vector2(2048,1380)
	p.updated = sim.revision
	h.move_particles(sim.particles,[0],sim.revision,sim.grid,sim.native_particles)
	check.call(p.p == Vector2(2048,1380) and p.previous == Vector2(2048,1180),"Pheromones cross solid reef branches without swept collision")
	# Every cell emits without needing energy, a sensing organ or a weapon.
	sim = isolated()
	for role in ["grazer","hunter"]:
		var source = sim._make_cell(sim.player.position+Vector2(120,0),role)
		source.organs.clear()
		source.energy = 0
		var start: int = sim.particles.size()
		sim._emit_and_attack(source,0.5)
		var count := 0
		for i in range(start,sim.particles.size()):
			if sim.particles[i].kind == Sim.PHEROMONE and sim.particles[i].owner == source.id: count += 1
		check.call(count >= 4,"Every creature emits pheromones without ATP or dedicated anatomy")
	_distribution(check)
	_backend(check)

static func _distribution(check: Callable) -> void:
	var sim = isolated()
	sim.view_half = Vector2(1500,1100)
	sim.fluid.velocity.fill(Vector2(32,0))
	sim.rng.seed = 711
	# A continuous source creates young upstream specks and old downstream tails.
	for tick in 40:
		for i in 30:
			sim.spawn_particle(Sim.PHEROMONE,sim.player.position)
		sim.time += 0.25
		sim._expire_pheromones()
		sim._move_particles(0.25)
	var upstream := 0
	var downstream := 0
	var far_downstream := 0
	var live := 0
	var average := Vector2.ZERO
	for p in sim.particles:
		if not p.alive: continue
		live += 1
		var d := Sim.Medium.offset(sim.player.position,p.p)
		average += d
		if d.x < 0: upstream += 1
		else: downstream += 1
		if d.x > 150: far_downstream += 1
	average /= live
	check.call(upstream > 0 and downstream > upstream*8,"Diffusion sends some pheromones upstream while advection carries most downstream")
	check.call(far_downstream > live*0.1 and average.x > 60,"A quickly decaying continuous plume still has a long down-current tail")
	check.call(absf(average.y) < 6,"Diffusion has no systematic cross-current direction")
	check.call(sim.particles.all(func(packet): return packet.v == Vector2.ZERO and packet.angle == 0),"Point pheromones have neither ballistic inertia nor a binding orientation")
	print("PHEROMONE_PLUME ",JSON.stringify({"live":live,"upstream":upstream,"downstream":downstream,"beyond_150":far_downstream,"mean_offset":average}))
	sim.particles.clear()
	sim.grid.rebuild(sim.particles)
	sim.time = 0
	for i in 2000: sim.spawn_particle(Sim.PHEROMONE,Vector2(10,10))
	sim.time = 5
	sim._expire_pheromones()
	var survivors: int = sim.particles.filter(func(packet):return packet.alive).size()
	check.call(survivors > 640 and survivors < 830,"Exponential five-second mean lifetime decays independently of view and frame rate")
	sim.time = 25
	sim._expire_pheromones()
	check.call(sim.particles.filter(func(packet):return packet.alive).size() < 35,"Rapid stochastic decay bounds long-lived plume accumulation")

static func _backend(check: Callable) -> void:
	var fast = isolated()
	if fast.kernels == null: return
	fast.view_half = Vector2(1500,1100)
	fast.fluid.velocity.fill(Vector2(24,-7))
	for i in 200:
		fast.spawn_particle(Sim.PHEROMONE if i%2 else Sim.NUTRIENT,fast.player.position+Vector2(i%10,i/10),Vector2(350,-180))
	var slow = isolated()
	slow.native_particles = false
	slow.view_half = fast.view_half
	slow.fluid.velocity = fast.fluid.velocity.duplicate()
	slow.particles = fast.particles.duplicate(true)
	for sim in [fast,slow]:
		sim.grid.rebuild(sim.particles)
		sim.rng.seed = 912
	for tick in 20:
		# Rebuild both grids so RNG draws visit the same ordered inputs. The
		# reference incremental grid otherwise has a different bucket order.
		fast.grid.rebuild(fast.particles)
		slow.grid.rebuild(slow.particles)
		fast._move_particles(DT)
		slow._move_particles(DT)
	var error := 0.0
	for i in fast.particles.size():
		error = maxf(error,Sim.Medium.offset(fast.particles[i].p,slow.particles[i].p).length())
	check.call(error < 0.003,"Native and reference mixed material/pheromone transport agree for the same ordered inputs")
