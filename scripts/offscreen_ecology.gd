extends RefCounted
## Coarse, resource-conserving ecology. No hidden stat bonuses or live AI target lookup.
const Medium = preload("res://scripts/medium.gd")
const Genes = preload("res://scripts/mutations.gd")
const PERIOD := 1.0
const SUBSTEP := 0.125
const FEED_MARGIN := 70.0
const CONTACT_DUTY := 0.5
# Calibrated swept collection area for unresolved pore motion and fluid delivery.
# This affects encounters with real packets, never cell storage/metabolic stats.
const COLLECTION_SWEEP := 1.7
var period := PERIOD # Independent benchmark switch, not a player stat.
var enabled_hunting := true
var visits := 0
var kills := 0
var intake := 0.0

static func event_count(random: RandomNumberGenerator, mean: float) -> int:
	if mean <= 0: return 0
	# Poisson leaps at ordinary rates; bounded normal approximation for huge bodies.
	if mean > 20: return maxi(0,roundi(random.randfn(mean,sqrt(mean))))
	var product := 1.0
	var limit := exp(-mean)
	var count := 0
	while product > limit:
		product *= maxf(0.000000001,random.randf())
		count += 1
	return count-1

func step(sim, dt: float) -> void:
	visits = 0
	for cell in sim.cells.duplicate():
		if cell.dead: continue
		if cell.activity > 0:
			if cell.coarse_elapsed > 0:
				advance(sim,cell,cell.coarse_elapsed,false)
				cell.coarse_elapsed = 0
				cell.previous_position = cell.position
				cell.previous_angle = cell.angle
			cell.coarse_due = period*(0.25+fposmod(cell.id*0.61803398875,0.75))
			continue
		cell.coarse_elapsed += dt
		cell.coarse_due -= dt
		if cell.coarse_due > 0: continue
		var elapsed: float = cell.coarse_elapsed
		cell.coarse_elapsed = 0
		cell.coarse_due += period
		advance(sim,cell,elapsed,true)
		visits += 1

func advance(sim, cell, elapsed: float, hidden: bool = true) -> void:
	# One serial scope; restore foreground random stream and fluid mask before return.
	var foreground_rng: RandomNumberGenerator = sim.rng
	var prior_activity: float = cell.activity
	var old_mode: bool = sim.coarse_mode
	var old_coupling: bool = sim.fluid.global_coupling
	sim.rng = sim.ecology_rng
	sim.coarse_mode = true
	sim.fluid.global_coupling = true
	cell.activity = 1.0
	var mark := Time.get_ticks_usec() if sim.profiling else 0
	if hidden:
		var patch: Array[int] = []
		if sim.particle_pool:
			patch = sim.kernels.pool_filter(sim.grid.query(cell.position,cell.extent()+FEED_MARGIN+60),-1,true,sim.player.position if sim.camera_follows_player else sim.camera_position,sim.view_half)
		else:
			for index in sim.grid.query(cell.position,cell.extent()+FEED_MARGIN+60):
				var packet: Dictionary = sim.particles[index]
				if packet.alive and sim.activity_at(packet.p) <= 0: patch.append(index)
		# Same oriented contact rules; timestamped unary chemistry prevents two
		# nearby cells from charging the same packet twice for elapsed time.
		sim._chemistry(0,patch,true)
	if sim.profiling: sim.profile_usec["coarse_chemistry"] = sim.profile_usec.get("coarse_chemistry",0)+Time.get_ticks_usec()-mark
	var left := elapsed
	while left > 0.0000001 and not cell.dead:
		var h := minf(SUBSTEP,left)
		left -= h
		sim.coarse_event_at = sim.time-left
		cell.age += h
		cell.coarse_handling = maxf(0,cell.coarse_handling-h)
		cell.animate_resources(h)
		sim._clear_receptors(cell,h)
		sim._sense(cell,h) # Only received particles supply inter-cell information.
		if hidden:
			mark = Time.get_ticks_usec() if sim.profiling else 0
			_feed(sim,cell,h)
			if sim.profiling: sim.profile_usec["coarse_feeding"] = sim.profile_usec.get("coarse_feeding",0)+Time.get_ticks_usec()-mark
			_exposure(sim,cell,h)
		if cell.health <= 0:
			_kill(sim,cell)
			break
		advance_body(sim,cell,h)
		if hidden: _hunt(sim,cell,h)
		if cell.health <= 0 and not cell.dead: _kill(sim,cell)
	cell.previous_position = cell.position
	cell.previous_angle = cell.angle
	cell.render_revision += 1
	cell.activity = prior_activity
	sim.fluid.global_coupling = old_coupling
	sim.coarse_mode = old_mode
	sim.rng = foreground_rng

func advance_body(sim, cell, h: float) -> void:
	sim._acid_stress(cell,h)
	sim._photosynthesize(cell,h)
	sim._metabolize(cell,h)
	cell.heal(h)
	for leak in cell.leaks:
		var normal := Vector2.from_angle(cell.angle+leak.a)
		sim._emit_material(sim.NUTRIENT,cell.position+cell.local_point(leak.a).rotated(cell.angle)+normal*12,leak.amount,normal*12,cell.id)
	cell.chemistry.excrete(sim,cell,h)
	_resize(cell)
	while cell.occupied() > cell.perimeter() and not cell.organs.is_empty():
		var organ: Dictionary = cell.organs.pop_back()
		var lost: Dictionary=organ.duplicate(true)
		if lost.has("stored_toxin"):lost.stored_toxin=0.0
		cell.lost_organs.append(lost)
		sim.spawn_particle(sim.WASTE,cell.organ_position(organ),Vector2.ZERO,organ.material+float(organ.get("stored_toxin",0)),cell.id)
	sim._emit_and_attack(cell,h)
	sim._suction_cell(cell,h)
	var mark := Time.get_ticks_usec() if sim.profiling else 0
	sim._motion_cell(cell,h)
	if sim.profiling: sim.profile_usec["coarse_motion"] = sim.profile_usec.get("coarse_motion",0)+Time.get_ticks_usec()-mark
	sim._fund_reproduction(cell,h)

static func _resize(cell) -> void:
	var old_radius: float = cell.radius
	cell.update_geometry()
	var factor: float = cell.radius/maxf(0.001,old_radius)
	# Keep the authored tension network and existing shape, without solving every
	# membrane constraint offscreen. Ordinary solver resumes in the outer halo.
	if absf(factor-1) < 0.000001: return
	for i in cell.membrane.COUNT:
		cell.membrane.points[i] *= factor
		cell.membrane.previous[i] = cell.membrane.points[i]
	cell.membrane.maximum_radius *= factor
	cell.membrane.invalidate()

static func _functional(cell, kind: String) -> float:
	var result := 0.0
	for organ in cell.organs:
		if organ.kind == kind: result += organ.scale*organ.scale*organ.hp/organ.max_hp
	return result

static func _swim(cell) -> float:
	var thrust := 0.0
	for organ in cell.organs:
		if organ.kind in ["propulsion","cilia"]:
			thrust += (2600.0 if organ.kind == "propulsion" else cell.CILIA_THRUST)*organ.scale*organ.scale*organ.hp/organ.max_hp*Genes.factor(organ,"thrust")
	return thrust*cell.work_capacity()/(cell.fluid_drag()+cell.mass*0.2)

static func feeding_request(sim, cell, dt: float, period: float) -> Dictionary:
	# Same unresolved swept collection model as _feed; GPU consumption still
	# competes for actual packets and ordinary storage capacity.
	var capture := 0.0
	var relative: float=(cell.velocity-sim.fluid.sample(cell.position)).length()
	var radius: float=cell.extent()+FEED_MARGIN+minf(60,relative*period)
	for organ in cell.organs:
		if organ.kind!="feeding" or organ.hp<=0: continue
		var pump: float=24*organ.scale*organ.hp/organ.max_hp*Genes.factor(organ,"suction")*cell.work_capacity()
		var center: Vector2=cell.pore_center(organ)
		var arm: Vector2=Medium.offset(cell.position,center)
		var local_flow: float=(cell.velocity+arm.orthogonal()*cell.angular_velocity-sim.fluid.sample(center)).length()
		capture+=2*(cell.pore_radius(organ)+8)*(local_flow+pump+4)
	var area: float=PI*maxf(1,radius*radius-cell.radius*cell.radius)
	return {"dt":dt,"radius":radius,"nutrient":COLLECTION_SWEEP*capture/area,
		"oxygen":COLLECTION_SWEEP*2*(cell.extent()+14)*(relative+4)/area,
		"carbon":COLLECTION_SWEEP*2*(cell.extent()+18)*(relative+4)/area if _functional(cell,"photosynthesis")>0 else 0.0,
		"seed":sim.revision&0xffffff}

func _feed(sim, cell, dt: float) -> void:
	var mouth: Dictionary = {}
	var capture := 0.0
	var relative: float = (cell.velocity-sim.fluid.sample(cell.position)).length()
	var radius: float = cell.extent()+FEED_MARGIN+minf(60,relative*period)
	for organ in cell.organs:
		if organ.kind != "feeding" or organ.hp <= 0: continue
		if mouth.is_empty(): mouth = organ
		var pump: float = 24*organ.scale*organ.hp/organ.max_hp*Genes.factor(organ,"suction")*cell.work_capacity()
		var center: Vector2 = cell.pore_center(organ)
		var arm: Vector2 = Medium.offset(cell.position,center)
		var local_flow: float = (cell.velocity+arm.orthogonal()*cell.angular_velocity-sim.fluid.sample(center)).length()
		capture += 2*(cell.pore_radius(organ)+8)*(local_flow+pump+4)
	var area: float = PI*maxf(1,radius*radius-cell.radius*cell.radius)
	if sim.native_feeding:
		var rates := {"radius":radius,"dt":dt,"intake":intake,
			"nutrient":COLLECTION_SWEEP*capture/area,
			"oxygen":COLLECTION_SWEEP*2*(cell.extent()+14)*(relative+4)/area,
			"carbon":COLLECTION_SWEEP*2*(cell.extent()+18)*(relative+4)/area}
		intake = sim.kernels.coarse_feed(sim.particles,sim.grid.query(cell.position,radius),cell,mouth,rates,
			sim.player.position if sim.camera_follows_player else sim.camera_position,sim.view_half,sim.rng,sim.habitat_geometry)
		return
	for index in sim.grid.query(cell.position,radius):
		var p: Dictionary = sim.particles[index]
		if not p.alive or p.kind not in [sim.NUTRIENT,sim.OXYGEN,sim.CARBON] or sim.activity_at(p.p) > 0: continue
		var distance: float = Medium.offset(cell.position,p.p).length()
		if distance > radius: continue
		var capacity := 0.0
		var rate := 0.0
		if p.kind == sim.NUTRIENT and not mouth.is_empty():
			capacity = maxf(0,cell.gut_capacity()-cell.substrate)
			rate = COLLECTION_SWEEP*capture/area
		elif p.kind == sim.OXYGEN:
			capacity = maxf(0,cell.oxygen_capacity()-cell.oxygen)
			rate = COLLECTION_SWEEP*2*(cell.extent()+14)*(relative+4)/area
		elif p.kind == sim.CARBON and _functional(cell,"photosynthesis") > 0:
			capacity = maxf(0,float(sim.Catalog.data().ecology.carbon_capacity)*cell.growth_scale()-cell.carbon)
			rate = COLLECTION_SWEEP*2*(cell.extent()+18)*(relative+4)/area
		if capacity <= 0 or not sim.chance(rate,dt): continue
		# Dissolved resources permeate stems; legacy barriers are benchmark-only.
		if not sim.habitat_geometry.particles_permeable and not _clear_path(sim,cell.position,p.p): continue
		var amount := minf(p.amount,capacity)
		p.amount -= amount
		if sim.kernels != null: sim.kernels.invalidate_particle_render(index)
		if p.amount <= 0.000001: p.alive = false
		if p.kind == sim.OXYGEN: cell.receive_particle(sim.OXYGEN,amount,amount,p.p)
		elif p.kind == sim.CARBON:
			cell.receive_particle(sim.CARBON,amount,amount,p.p)
			if p.owner != cell.id: cell.foreign_intake += amount
		else:
			var fuel: float = maxf(0,float(p.get("capacity",p.amount+amount)))*amount/maxf(0.000001,p.amount+amount)
			cell.receive_particle(sim.NUTRIENT,amount,fuel,p.p)
			p.capacity=maxf(0,p.get("capacity",p.amount+amount)-fuel)
			cell.eaten += amount
			if p.owner != cell.id: cell.foreign_intake += amount
			cell.consumed(mouth,amount)
			intake += amount

static func _clear_path(sim, start: Vector2, end: Vector2) -> bool:
	if not sim.habitat_geometry.enabled: return true
	return not sim.habitat_geometry.move(start,end,Vector2.ZERO,0.0)[2]

func _exposure(sim, cell, dt: float) -> void:
	# Actual toxin/decoy packets pay for offscreen exposure; no free poison DPS.
	var radius: float = cell.extent()+24
	if sim.particle_pool:
		sim.kernels.pool_exposure(sim.grid.query(cell.position,radius),cell,dt,sim.inherited_lineages,sim.player.position if sim.camera_follows_player else sim.camera_position,sim.view_half,sim.rng)
		return
	for index in sim.grid.query(cell.position,radius):
		var p: Dictionary = sim.particles[index]
		if not p.alive or p.kind not in [sim.TOXIN,sim.DECOY,sim.ANTITOXIN,sim.TAG,sim.PORE_SUBUNIT] or sim.activity_at(p.p) > 0: continue
		if p.kind != sim.ANTITOXIN and sim.inherited_lineages.get(p.owner,p.owner) == cell.lineage_id(): continue
		var delta := Medium.offset(cell.position,p.p)
		if delta.length() > radius or not sim.chance(2.0,dt): continue
		if not sim.habitat_geometry.particles_permeable and not _clear_path(sim,cell.position,p.p): continue
		if p.kind in [sim.ANTITOXIN,sim.TAG,sim.PORE_SUBUNIT]:
			if p.direction.dot(-delta.normalized())<0.5 or not cell.accept_surface(p.kind,p.amount,delta.angle(),p.owner): continue
			p.alive=false
			continue
		if p.kind == sim.DECOY:
			var bound := false
			for organ in cell.organs:
				if organ.kind not in ["feeding","sensing","hunting"]: continue
				var contact := Medium.offset(cell.organ_position(organ),p.p)
				if contact.length() > 12*organ.scale+sim.particle_radius(p.kind)*sim.particle_scale(p.amount): continue
				var forward: Vector2 = cell.organ_normal(organ).rotated(cell.angle)
				var normal := contact.normalized()
				if forward.dot(normal) < 0.25 or p.direction.dot(-normal) < 0.5: continue
				organ.blocked = minf(1,organ.blocked+0.65)
				bound = true
				break
			if not bound: continue
		if sim.kernels != null: sim.kernels.invalidate_particle_render(index)
		p.alive = false
		cell.waste += p.amount
		if p.kind == sim.TOXIN:
			cell.waste += cell.damage(p.amount*sim.Catalog.data().combat.toxin_damage_per_unit,delta.angle(),p.owner)
			cell.death_hint = "Membrane failed after toxin exposure"

func _hunt(_sim, _attacker, _dt: float) -> void:
	pass # Predation is paid packet exposure; no statistical offscreen kill.

func _kill(sim, prey) -> void:
	# Lysis releases the complete corpse once. Predators and scavengers must use
	# ordinary feeding pores and the same finite-packet absorption path.
	if not prey.dead: sim._die(prey)
