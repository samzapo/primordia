extends SceneTree
## Finite paid-transfer/ownership checks only; no survival or balance acceptance.
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func fixture():
	var sim=Sim.new(77,0,false);sim.server_mode=true
	sim.player.add_organ("feeding",0,"graze",false);sim.cells=[sim.player];sim.habitat_geometry=Sim.Habitat.new(77,sim.cells);sim.habitat_geometry.enabled=false
	sim.lineage.dormant.clear();return sim
func material(sim) -> float:
	return sim.cells.filter(func(cell):return not cell.dead).reduce(func(total,cell):return total+cell.organic_mass(),0.0)
func adenylate_energy(sim) -> float:
	return sim.cells.filter(func(cell):return not cell.dead).reduce(func(total,cell):return total+cell.energy+cell.brood_energy,0.0)
func prepare(sim,cell) -> void:
	var quote: Dictionary=sim.offspring_quote(cell)
	cell.biomass=quote.material+20;cell.energy=100
	cell.reserve(maxf(60,quote.material),quote.material)
func run() -> void:
	var sim=fixture();var parent=sim.player
	var mass: float=material(sim);var energy: float=adenylate_energy(sim)
	sim._fund_reproduction(parent,.5)
	check(absf(material(sim)-mass)<.000001 and absf(adenylate_energy(sim)-energy)<.000001,"Automatic investment transfers existing tissue and ATP without creating inventory")
	check(parent.brood_energy>0 and parent.energy>=sim.REPRODUCTION_ATP_FLOOR and parent.biomass>=sim.REPRODUCTION_TISSUE_FLOOR,"Investment uses paid numeric ATP reserves and retains the operating inventories")
	parent.biomass=0;parent.energy=0
	var tissue: float=parent.brood_mass;var stored: float=parent.brood_energy
	sim._fund_reproduction(parent,1)
	check(parent.brood_mass==tissue and parent.brood_energy==stored,"An empty parent cannot fund additional reserves")
	prepare(sim,parent);mass=material(sim);energy=adenylate_energy(sim);parent.biomass=0;mass=material(sim)
	var oxygen: float=parent.oxygen
	var exterior: int=sim.particle_count()
	sim._step_reproduction()
	check(sim.particle_count()==exterior,"Paid cell division cannot add an introduction food cloud")
	check(sim.cells.size()==2 and sim.player==parent,"Existing fully paid reserves commit without another investment or selection change")
	check(absf(material(sim)-mass)<.00001 and absf(adenylate_energy(sim)-(energy-20))<.00001 and is_equal_approx(parent.oxygen+sim.cells[-1].oxygen,oxygen),"Automatic paid division conserves tissue/oxygen and spends the existing twenty ATP division cost")
	var identity: int=sim.next_id;sim._step_reproduction()
	check(sim.next_id==identity,"A consumed reserve cannot commit a duplicate birth")
	var host=preload("res://scripts/network/world_host.gd").new();host.world=sim
	host.accounts={"private-fixture":{"selected":parent.id,"current":parent,"root":parent.lineage_id(),"lineage":sim.lineage,"evolution":sim.evolution,"edit":0}}
	sim._die(parent);host._recover_families(.01)
	check(host.accounts["private-fixture"].selected==sim.cells[-1].id and not host.accounts["private-fixture"].current.dead,"Disconnected account succession selects its actual living descendant")
	check(host._family_recovery(host.accounts["private-fixture"]).state=="active","Recovery status reports an actual living selected body")
	host.free()

	sim=fixture();parent=sim.player
	var other=Sim.Cell.new(77,Vector2(1000,1000));other.biomass=500
	check(other.add_organ("photosynthesis",1.5),"Distinct-parent anatomy fixture is paid")
	sim.cells.append(other);sim.next_id=100;prepare(sim,other)
	var original: PackedByteArray=var_to_bytes(Codec.new().capture(parent))
	mass=material(sim);sim._step_reproduction()
	check(sim.cells.size()==3 and sim.cells[-1].lineage_id()==other.lineage_id() and sim.cells[-1].count("photosynthesis")==0 and sim.cells[-1].count("feeding")==1,"Unowned paid reproduction keeps that parent's family without cloning its paid anatomy")
	check(sim.player==parent and var_to_bytes(Codec.new().capture(parent))==original and absf(material(sim)-mass)<.00001,"Another lineage cannot spend, mutate or replace the selected player")
	var ledger=sim._family_ledger(other)
	check(ledger.active_family(sim).size()==2 and sim._family_ledger(sim.cells[-1])==ledger,"An unclaimed family retains a shared ledger before enrollment")

	sim=fixture();parent=sim.player;prepare(sim,parent)
	var blocker=Sim.Cell.new(999,parent.position);blocker.body=10000000;blocker.update_geometry();blocker.membrane=Sim.Cell.Membrane.new(blocker.radius);sim.cells.append(blocker)
	mass=material(sim);energy=adenylate_energy(sim);identity=sim.next_id
	sim._step_reproduction();sim._step_reproduction()
	check(sim.next_id==identity and material(sim)==mass and adenylate_energy(sim)==energy,"Blocked placement preserves the funded transaction without duplicate charges")
	check(parent.reproduction_retry_at>sim.time,"Blocked placement retains a bounded simulation-time retry")
	parent.reproduction_elapsed=.25
	var restored=Codec.new().restore(Codec.new().capture({"world":sim})).world
	check(restored.player.reproduction_elapsed==.25 and restored.player.reproduction_retry_at==parent.reproduction_retry_at,"Investment time and retry state survive a checkpoint")
	print("REPRODUCTION ACCOUNTING: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
