extends RefCounted
# Benchmark-only resolution sweep: split initial cell-produced chemical material;
# preserve species, source snapshots and total amount/product/capacity. Placement
# is controlled fixture data, not a new gameplay particle source.
static func packet_material(sim) -> float:
	if sim.particle_pool: return sim.kernels.pool_material()
	var total := 0.0
	for packet in sim.particles:
		if packet.alive and packet.kind not in [sim.OXYGEN,sim.PHEROMONE]:
			total += packet.amount+float(packet.get("product",0))
	return total

static func seed_packets(sim, count: int, distribution: String) -> bool:
	var source: Array = []
	for packet in sim.particles:
		if packet.alive and packet.kind != sim.PHEROMONE: source.append(packet)
	if count < source.size() or source.is_empty() or distribution not in ["uniform","clustered"] or count > 100000:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = 25171
	var expanded: Array = []
	var anchors: Array[Vector2] = []
	for k in 5:
		anchors.append(sim.player.position+Vector2.from_angle(TAU*k/5)*sim.view_half.y*0.55)
	for j in source.size():
		var copies := count/source.size()+(1 if j<count%source.size() else 0)
		for k in copies:
			var item: Dictionary = source[j].duplicate(true)
			for key in ["amount","capacity","product"]:
				if item.has(key): item[key] /= copies
			var at: Vector2
			if distribution == "uniform":
				at = sim.player.position+Vector2(rng.randf_range(-sim.view_half.x,sim.view_half.x),rng.randf_range(-sim.view_half.y,sim.view_half.y))*0.90
			else:
				at = anchors[j%anchors.size()]+Vector2(rng.randfn(0,45),rng.randfn(0,45))
			item.p = sim.Medium.wrap_position(at)
			item.previous = item.p
			expanded.append(item)
	for packet in sim.pheromones:
		if packet.alive: expanded.append(packet)
	sim.particles = expanded
	sim.grid.rebuild(sim.particles)
	return true
