extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Interior = preload("res://scripts/interior_ecology.gd")
const Score = preload("res://scripts/music_score.gd")
static func area(cell) -> float:
	var result := 0.0
	for i in cell.membrane.COUNT:
		result += cell.membrane.points[i].cross(cell.membrane.points[(i+1)%cell.membrane.COUNT])*0.5
	return result

static func run(check: Callable) -> void:
	var sim = Sim.new(42)
	sim.habitat_geometry.enabled = false
	for cell in sim.cells:
		var mouths: Array = cell.organs.filter(func(o): return cell.inherent(o))
		check.call(mouths.size() == 1 and mouths[0].kind == "feeding" and mouths[0].material == 0,"Every generated creature has one structural oral groove")
	var crowded = sim._make_cell(Vector2(1400,1000),"grazer")
	crowded.organs.reverse()
	for organ in crowded.organs:
		if not crowded.inherent(organ): organ.scale = 30
	sim._biology_after_feed(crowded,1.0/60)
	check.call(crowded.count("feeding") == 1 and crowded.organs.all(func(o):return crowded.inherent(o)),"Shrinkage sheds crowded attachments but never sheds inherent membrane anatomy")
	var cell = sim.player
	var mouth: Dictionary = cell.organs[0]
	var before: Array = [cell.organic_mass(),cell.biomass,sim.evolution.points]
	check.call(not sim.install("feeding",1) and not sim.remove(0) and not cell.move_organ(mouth.id,PI) and not cell.specialize(mouth.id,"wide_pore"),"The membrane groove cannot be bought, recycled, detached or specialized")
	check.call(before == [cell.organic_mass(),cell.biomass,sim.evolution.points],"Rejected membrane transactions spend no tissue or AP")
	cell.damage(5,mouth.a+cell.angle)
	check.call(cell.health == 95 and cell.organs.has(mouth) and not cell.holes.is_empty(),"Oral membrane is vulnerable tissue, not free armor")
	cell.health = 100
	cell.holes.clear()
	cell.membrane.skeleton.links.clear()
	for i in 120: cell.membrane.step(1.0/60,cell.radius,Vector2.ZERO,0)
	check.call(cell.local_point(mouth.a).length() < cell.radius*0.75,"Oral groove is an inward physical dent")
	check.call(absf(area(cell)-(cell.body+cell.biomass+cell.brood_mass+cell.chemistry.reactor_mass+cell.chemistry.amount("catalyst"))*cell.TISSUE_AREA)<0.002,"Physical volume uses the same tissue-area unit as the cost blob")
	var original_area := area(cell)
	var original_volume: float = cell.body+cell.biomass+cell.brood_mass+cell.chemistry.reactor_mass+cell.chemistry.amount("catalyst")
	cell.biomass += 40
	cell.update_geometry()
	for i in 120: cell.membrane.step(1.0/60,cell.radius,Vector2.ZERO,0)
	check.call(absf(area(cell)/original_area-(original_volume+40)/original_volume) < 0.0001,"Added biomass maps one-to-one to enclosed area, including groove displacement")
	check.call(Geometry2D.triangulate_polygon(cell.membrane.outline()).size() > 0,"Indented anatomy remains renderable")
	cell.energy = cell.energy_reference()
	cell.chemistry.assign("adp",0)
	cell.chemistry.emit("adp",cell.energy_reference()*9,cell.chemistry.site(cell.chemistry.node_at(cell.chemistry.find_module("respiration"))))
	cell.gain_energy(cell.energy_reference()*9)
	check.call(cell.energy > cell.energy_reference()*9,"ATP has no old storage ceiling")
	var full_rate: float = cell.atp_decay_rate()
	cell.energy *= 0.5
	check.call(is_equal_approx(full_rate,cell.atp_decay_rate()*4),"Doubling ATP concentration quadruples turnover")
	var a = Sim.Cell.clone_state(cell)
	var b = Sim.Cell.clone_state(cell)
	a.decay_energy(1)
	for i in 60: b.decay_energy(1.0/60)
	check.call(absf(a.energy-b.energy) < 0.00001 and a.energy > 0,"ATP decay is positive and agrees between coarse and fine intervals")
	var interior := Interior.new()
	cell.substrate = 13.5;cell.waste = 2.2
	interior.sync(cell,7)
	var stock: Array = [cell.organic_mass(),cell.energy,cell.health,cell.age,sim.time,sim.rng.state,sim.ecology_rng.state]
	var initial: Array = interior.parcels.map(func(p): return p.p)
	for i in 180: interior.step(1.0/60,cell)
	check.call(initial != interior.parcels.map(func(p): return p.p),"Intracellular parcels circulate independently of the paused outside")
	check.call(stock == [cell.organic_mass(),cell.energy,cell.health,cell.age,sim.time,sim.rng.state,sim.ecology_rng.state],"Editing circulation cannot create energy, material, elapsed ecology or random draws")
	check.call(cell.chemistry.amount("food")==13.5 and cell.chemistry.amount("waste")==2.2 and interior.amount("ap")==7,"Chemical quantities derive from physical particles; AP remains edit currency")
	cell.substrate = 0
	interior.sync(cell,2)
	check.call(interior.amount("food") == 0 and interior.amount("ap") == 2,"Consumed food and spent AP disappear from internal stocks immediately")
	# Stronger suction is measured in the local body frame and conserves momentum.
	var water = Sim.Medium.new()
	water.driven = false;water.activity.fill(1);water.active_indices = PackedInt32Array(range(water.COLS*water.ROWS))
	cell.velocity = Vector2.ZERO;cell.angular_velocity = 0
	water.velocity.fill(Vector2.ZERO)
	var momentum: Vector2 = water.momentum()+cell.velocity*cell.mass
	water.suction(cell,cell.pore_center(mouth),cell.ORAL_REACH,cell.ORAL_FLOW,1.0/60)
	check.call((water.momentum()+cell.velocity*cell.mass-momentum).length() < 0.002,"Oral suction returns equal and opposite fluid momentum")
	var moving = Sim.Cell.clone_state(cell)
	var static_body = Sim.Cell.clone_state(cell)
	var x = Sim.Medium.new();var y = Sim.Medium.new()
	x.activity.fill(1);y.activity.fill(1)
	x.active_indices = water.active_indices;y.active_indices = water.active_indices
	x.velocity.fill(Vector2.ZERO);y.velocity.fill(Vector2(200,-100))
	static_body.velocity=Vector2.ZERO;moving.velocity=Vector2(200,-100)
	static_body.angular_velocity=0;moving.angular_velocity=0
	x.suction(static_body,cell.pore_center(mouth),170,64,1.0/60)
	y.suction(moving,cell.pore_center(mouth),170,64,1.0/60)
	check.call((moving.velocity-static_body.velocity-Vector2(200,-100)).length()<0.0001,"A common frame velocity cannot change suction")
	var score := Score.new()
	score.observe(sim,cell.position,Vector2(900,600),false)
	for source in score.sources:
		if source.id == cell.id: continue
		check.call(score.channels[source.lane].gain <= 0.09,"Other organisms are substantially quieter than the player's voice")
	for note in score.events(0,100000):
		check.call(note.has("source") and (note.kind == "nucleus" or note.organ_id != -1),"Every note identifies a nucleus or a real intracellular/membrane instrument")
		check.call(note.instrument not in [1,2,3,14,15],"No anonymous hats, claps, bass or pad backing track remains")
	score.sources.clear();score.channels[0].gain=0
	check.call(score.events(100001,100000).is_empty(),"No visible sound source means no synthesized notes")
	check.call(Score.note_color(60) == Score.note_color(72) and Score.note_color(60) != Score.note_color(61),"Wave hue identifies pitch class consistently across octaves")
