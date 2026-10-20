extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Score = preload("res://scripts/music_score.gd")
static func area(cell) -> float:
	var result := 0.0
	for i in cell.membrane.COUNT:
		result += cell.membrane.points[i].cross(cell.membrane.points[(i+1)%cell.membrane.COUNT])*0.5
	return result

static func run(check: Callable) -> void:
	var sim = Sim.new(42)
	sim.habitat_geometry.enabled = false
	for member in sim.cells:
		check.call(member.count("feeding")==1 and member.organs.filter(func(o):return o.kind=="feeding")[0].material==8,"Starter cells own one optional material-bearing oral groove")
	var cell=sim.player
	var mouth: Dictionary=cell.organs.filter(func(o):return o.kind=="feeding")[0]
	cell.damage(5,mouth.a+cell.angle)
	check.call(cell.health==95 and cell.organs.has(mouth),"An oral opening does not act as free armor")
	cell.health=100;cell.holes.clear();cell.update_geometry()
	for i in 120:cell.membrane.step(1.0/60,cell.radius,Vector2.ZERO,0)
	check.call(cell.local_point(mouth.a).length()<cell.radius,"The oral tether and membrane create an inward mouth")
	check.call(absf(area(cell)-(cell.body+cell.biomass+cell.brood_mass+cell.chemistry.reactor_mass+cell.chemistry.amount("catalyst"))*cell.TISSUE_AREA)<0.002,"Physical volume uses the same tissue-area unit as the cost blob")
	var original_area := area(cell)
	var original_volume: float = cell.body+cell.biomass+cell.brood_mass+cell.chemistry.reactor_mass+cell.chemistry.amount("catalyst")
	cell.biomass += 40
	cell.update_geometry()
	for i in 120: cell.membrane.step(1.0/60,cell.radius,Vector2.ZERO,0)
	check.call(absf(area(cell)/original_area-(original_volume+40)/original_volume) < 0.0001,"Added biomass maps one-to-one to enclosed area, including groove displacement")
	check.call(Geometry2D.triangulate_polygon(cell.membrane.outline()).size() > 0,"Indented anatomy remains renderable")
	cell.energy = cell.energy_reference()
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
