extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Archive = preload("res://scripts/lineage_archive.gd")
const Score = preload("res://scripts/music_score.gd")

static func world():
	var sim = Sim.new(821)
	sim.habitat_geometry.enabled = false
	sim.pending_replacements.clear()
	sim.cells = [sim.player]
	sim.particles.clear()
	sim.pheromones.clear()
	sim.grid.clear()
	return sim

static func mass(sim) -> float:
	var result: float = sim.lineage.stored_material()
	for cell in sim.cells:
		if not cell.dead: result += cell.organic_mass()
	for packet in sim.particles:
		if packet.alive: result += packet.amount*Sim.Catalog.material(packet.kind)
	return result

static func fund(sim) -> void:
	sim.player.biomass=200;sim.player.energy=100;sim.player.reproduction_retry_at=0

static func run(check: Callable) -> void:
	var sim=world();var parent=sim.player
	parent.biomass=200;parent.energy=100;parent.reproduction_retry_at=0
	var learned=["economical_flagellum"];sim.evolution.learned.assign(learned)
	check.call(sim.divide_lineage(false,false),"A direct daughter joins the living family")
	var child=sim.cells[-1];var id=child.id
	check.call(child.generation==1 and child.lineage_id()==parent.lineage_id(),"A real birth retains generation and family identity")
	sim._die(parent)
	check.call(sim.lineage.recover(sim,1) and sim.player.id==id,"Ordinary death hands control to the living daughter")
	check.call(sim.evolution.learned==learned and sim.player.ap==0,"Succession preserves discoveries without an AP refresh")
	var identities=sim.cells.map(func(c):return c.id)
	var original=sim.player.organic_mass()
	check.call(not sim.divide_lineage(true,false) and sim.cells.map(func(c):return c.id)==identities and sim.player.organic_mass()==original,"Retired stored-offspring commands cannot spend or create a body")
	var selected=sim.player
	sim.begin_build();sim.evolution.learned.append("fixture");sim.cancel_build()
	check.call(sim.player==selected and "fixture" not in sim.evolution.learned,"Cancelling a local build restores anatomy and mutation state")
	check.call(sim.lineage.records.all(func(r):return r.state in ["living","active"]),"Family roster contains only living relatives")
