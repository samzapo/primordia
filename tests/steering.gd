extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Cues = preload("res://tests/pheromones.gd")
const Family = preload("res://tests/lineage.gd")
const DT := 1.0/60

static func fixture():
	var sim = Cues.isolated()
	sim.habitat_geometry.enabled = false
	sim.player.add_organ("feeding",PI,"graze",false)
	var prey = sim._make_cell(sim.player.position+Vector2(100,0),"grazer")
	Cues.deliver(sim,prey)
	sim.spawn_particle(Sim.NUTRIENT,sim.player.position-Vector2(140,0),Vector2.ZERO,1,prey.id)
	sim.grid.rebuild(sim.particles)
	return sim

static func arrive(sim, organ: Dictionary, mode: String, score: float, identity: int = -1, sampled: float = 0, lineage: int = -1) -> void:
	sim.player.sense_clock = 10
	sim.player.signals.append({"p":Vector2.ZERO,"mode":mode,"score":score,"sample_at":sampled,
		"id":identity,"at":sim.player.position+Vector2(100,0),"organ_id":organ.id,
		"expires_at":sim.time+10,"lineage":lineage})
	sim._sense(sim.player,DT)

static func run(check: Callable) -> void:
	preload("res://tests/behavior_tree.gd").run(check)
	_family(check)

static func _family(check: Callable) -> void:
	var sim = Family.world()
	var parent = sim.player
	parent.organs.clear()
	parent.add_organ("feeding",PI,"graze",false)
	parent.add_organ("hunting",0,"hunt",false)
	parent.add_organ("poreforming",0.5,"graze",false)
	Family.fund(sim)
	check.call(sim.divide_lineage(false,false),"Family safety fixture releases an actual paid child")
	var child = sim.cells[-1]
	check.call(sim._install_for(child,sim.evolution,"hunting",0),"Family safety fixture explicitly buys a hunting receptor for its basic daughter")
	check.call(child.lineage_id() == parent.lineage_id(),"Paid offspring inherit the founder signature independently of role")
	# Read actual emitted snapshots in both directions, including after adoption.
	for adopted in [false,true]:
		if adopted: sim.follow_family(child.id)
		for observer in [parent,child]:
			sim.particles.clear()
			sim.grid.clear()
			var source = child if observer == parent else parent
			var organ: Dictionary = observer.organs.filter(func(item):return item.kind == "hunting")[0]
			var packet: Dictionary = sim._emit_pheromone(source)
			packet.p = observer.organ_position(organ)+Vector2(10,0)
			packet.expires_at = sim.time+10
			sim.grid.rebuild(sim.particles)
			observer.signals.clear()
			observer.target_memory = 0
			observer.sense_clock = 0
			organ["steering"]=4
			for i in 40: sim._sense(observer,DT)
			check.call(observer.target_id == -1,"Parent/child pheromones are ignored at maximum hunting strength before and after succession")
	# A family cue already inside the cell cannot bypass recognition.
	var organ: Dictionary = sim.player.organs.filter(func(item):return item.kind == "hunting")[0]
	arrive(sim,organ,"hunt",1000,parent.id,9,parent.lineage_id())
	check.call(sim.player.target_id == -1 and sim.player.signals.is_empty(),"A delayed internal family signal cannot initiate pursuit")
	sim.player.target_id = parent.id
	sim.player.target_lineage = parent.lineage_id()
	sim.player.target_mode = "hunt"
	sim.player.target_organ_id = organ.id
	sim.player.target_memory = 1
	sim._sense(sim.player,DT)
	check.call(sim.player.target_memory == 0,"A remembered family signal cannot survive a lineage handoff")
	# Family recognition affects targeting, not actual chemical contacts.
	for attacker in [parent,child]:
		var other = child if attacker == parent else parent
		sim.particles.clear()
		sim.grid.clear()
		var at: Vector2 = other.position+Vector2.RIGHT*other.radius
		sim.spawn_particle(sim.TAG,at,Vector2.ZERO,0.03,attacker.id)
		sim.particles[-1].direction=Vector2.LEFT
		var hp: float=other.health+other.organs.reduce(func(total,o):return total+o.hp,0.0)
		sim._surface_contacts()
		check.call(other.surface_complexes.size()==1,"Family tags bind through actual membrane contact in both directions")
		for i in 4:Sim.Cell.Surface.bind(other,sim.PORE_SUBUNIT,.0375,0,attacker.id)
		Sim.Cell.Surface.advance(other,.1,sim)
		check.call(other.health+other.organs.reduce(func(total,o):return total+o.hp,0.0)<hp,"Completed family pores damage the actual contacted membrane or covering organ")
