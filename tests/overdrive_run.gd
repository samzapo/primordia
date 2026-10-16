extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Cell = Sim.Cell
var assertions := 0
var failures := 0
class FixedEvents:
	extends "res://scripts/simulation.gd"
	func _event_count(rate: float,dt: float) -> int: return roundi(rate*dt)
	func _secretion_needed(_cell,_organ: Dictionary,_kind: int) -> bool: return true

func check(ok: bool,text: String) -> void:
	assertions += 1
	if not ok: failures += 1; push_error(text)
func _initialize() -> void: run.call_deferred()
func fixture(kind: String,output: float,fixed: bool=false):
	var sim = FixedEvents.new(833) if fixed else Sim.new(833)
	sim.cells = [sim.player]; sim.particles.clear(); sim.grid.clear()
	sim.player.organs.clear(); sim.player.body = 70; sim.player.biomass = 100; sim.player.energy = 100
	sim.player.velocity = Vector2.ZERO; sim.player.angular_velocity = 0; sim.player.angle = 0
	sim.player.target = Vector2.RIGHT; sim.player.facing = Vector2.RIGHT; sim.player.target_mouth = 0
	sim.player.update_geometry(); sim.player.add_organ(kind,0,"graze",false)
	sim.player.set_output_strength(sim.player.organs[0].id,output)
	sim.fluid.velocity.fill(Vector2.ZERO); sim.fluid.activity.fill(1); sim.fluid.driven = false
	sim.habitat_geometry.enabled = false
	return sim
func material(sim) -> float:
	var result: float = sim.player.organic_mass()
	for packet in sim.particles:
		if packet.alive: result += packet.amount*Sim.Catalog.material(packet.kind)
	return result
func run() -> void:
	for kind in Cell.KINDS:
		var sim = fixture(kind,1)
		var organ: Dictionary = sim.player.organs[0]
		var before: Array = [sim.player.energy,sim.player.biomass,sim.player.organic_mass()]
		check(sim.edit("output",{"id":organ.id,"value":2}) and Sim.Genes.output(organ)==2,"Every organ accepts an independent output percentage")
		check(before == [sim.player.energy,sim.player.biomass,sim.player.organic_mass()],"Adjusting output itself grants and consumes no stock")
		check(not sim.edit("output",{"id":organ.id,"value":100}) and not sim.edit("output",{"id":organ.id,"value":NAN}),"Output commands reject invalid and nonfinite percentages")
		var codec = preload("res://scripts/network/state_codec.gd").new()
		var restored = codec.restore(codec.capture(sim.player))
		check(restored.organs[0].output==2,"Output survives checkpoint recovery")
	for kind in ["propulsion","cilia"]:
		var a = fixture(kind,1); var b = fixture(kind,2)
		a._motion_cell(a.player,.01); b._motion_cell(b.player,.01)
		check(b.player.velocity.distance_to(a.player.velocity*2)<.001,"200% propulsion produces twice the actual body impulse")
		check(absf((100-b.player.energy)/(100-a.player.energy)-2.1)<.00001,"200% propulsion spends 210% ATP")
	for kind in ["feeding","cilia"]:
		var a = fixture(kind,1); var b = fixture(kind,2)
		a._suction_cell(a.player,.01); b._suction_cell(b.player,.01)
		var worst := 0.0
		for i in a.fluid.velocity.size(): worst = maxf(worst,b.fluid.velocity[i].distance_to(a.fluid.velocity[i]*2))
		check(worst<.001,"200% pumping doubles actual water forcing")
		check(absf((100-b.player.energy)/(100-a.player.energy)-2.1)<.00001,"200% pumping spends 210% ATP")
	for kind in ["toxin","poreforming","acidifying","neutralizing","regenerative"]:
		var a = fixture(kind,1,true); var b = fixture(kind,2,true)
		for sim in [a,b]:
			sim.player.target_id = 999; sim.player.target_memory = 1; sim.player.target_mode = "hunt"
			sim.player.target_position = sim.player.position+Vector2(100,0)
		var mass_a := material(a); var mass_b := material(b)
		a._emit_and_attack(a.player,1); b._emit_and_attack(b.player,1)
		check(absf((100-b.player.biomass)/(100-a.player.biomass)-2)<.00001,"200% glands release twice the represented material")
		check(absf((100-b.player.energy)/(100-a.player.energy)-2.1)<.00001,"200% glands pay the extra ATP inefficiency")
		check(absf(material(a)-mass_a)<.0001 and absf(material(b)-mass_b)<.0001,"Overdriven secretion retains finite represented material")
	var normal = fixture("protection",1); var boosted = fixture("protection",2)
	normal.player.damage(30,0); boosted.player.damage(30,0)
	check(absf((70-boosted.player.organs[0].hp)*2-(70-normal.player.organs[0].hp))<.00001 and boosted.player.energy<100,"ATP-funded cortex overdrive halves tissue damage at 200%")
	var empty = fixture("protection",2); empty.player.energy = 0; empty.player.damage(30,0)
	check(empty.player.organs[0].hp==normal.player.organs[0].hp,"Unfunded protective overdrive falls back to ordinary protection")
	var receptor = fixture("hunting",2)
	var organ: Dictionary = receptor.player.organs[0]
	check(receptor.player.sensory_output(organ,true)==2 and receptor.player.energy<100,"Overdriven sensing pays ATP for increased sampling reach")
	receptor.player.energy = 0
	check(receptor.player.sensory_output(organ,true)==1,"Normal sensing remains available without ATP")
	var stale = fixture("hunting",2)
	stale.player.energy = 0; stale.player.sense_clock = 0
	var stale_id: int = stale.player.organs[0].id
	var queries: Array = preload("res://scripts/resident_perception.gd").requests([stale.player],.15,stale.time)
	check(queries.size()==1 and queries[0].output==1,"GPU sensing requests use only currently affordable reach")
	var received: Dictionary = {stale_id:{"food":{},"reports":{},"patch":{"at":stale.player.position+Vector2(100,0)},"output":2.0}}
	stale._sense(stale.player,.01,received)
	check(received[stale_id].patch.is_empty() and not stale.player.sensed,"A stale GPU query cannot grant now-unfunded extended perception")
	var base = fixture("sensing",1); var repair_a = fixture("regenerative",1); var repair_b = fixture("regenerative",2)
	for sim in [base,repair_a,repair_b]: sim.player.health = 30; sim.player.heal(.01)
	check(absf((repair_b.player.health-base.player.health)-2*(repair_a.player.health-base.player.health))<.00001,"A regenerative gland doubles its actual added repair contribution")
	check((100-repair_b.player.energy)>(100-repair_a.player.energy)*1.6,"Extra actual repair spends more ATP with an inefficiency")
	var gpu := "--gpu" in OS.get_cmdline_user_args()
	var resident
	if gpu:
		resident = preload("res://scripts/resident_particles.gd").new()
		resident.rd = RenderingServer.get_rendering_device()
		check(resident.rd!=null,"GPU correctness requires a real rendering device")
	for output in [1.0,2.0]:
		var sim = fixture("photosynthesis",output)
		var leaf: Dictionary = sim.player.organs[0]
		var site: Vector2 = sim.player.local_point(leaf.a)*.72
		sim.player.chemistry.emit("carbon",20,site)
		if gpu: check(preload("res://scripts/resident_cytoplasm.gd").new().attach(resident,sim.player.chemistry,sim.player),"Photosynthesis shares the resident intracellular owner")
		var carbon_before: float = sim.player.carbon; var biomass_before: float = sim.player.biomass
		var expected: float = 3.5*sim.light_at(sim.player.organ_position(leaf))*.1*output
		sim._photosynthesize(sim.player,.1)
		var consumed: float = carbon_before-sim.player.carbon
		check(absf(consumed-expected)<.00001,"Photosynthesis consumes actual local carbon at selected output")
		check(absf(sim.player.biomass-biomass_before-consumed*.35)<.00001,"Photosynthetic tissue matches actual consumed carbon")
		if output>1: check(sim.player.energy_budget.rates(sim.player.age).categories.get("photosynthesis",0)>0,"Extra fixation records actual ATP expense")
		sim.player.chemistry.ensure_cpu()
	var photo = fixture("photosynthesis",4); photo.player.energy = 0
	photo.player.chemistry.emit("carbon",20,photo.player.local_point(0)*.72)
	var baseline: float = 3.5*photo.light_at(photo.player.organ_position(photo.player.organs[0]))*.1
	var carbon: float = photo.player.carbon
	photo._photosynthesize(photo.player,.1)
	check(absf(carbon-photo.player.carbon-baseline)<.00001 and photo.player.energy>0,"An empty ATP reserve permits baseline photosynthesis without free overdrive")
	print("OVERDRIVE: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
