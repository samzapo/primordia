extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Sac=preload("res://scripts/toxin_sac.gd")
var assertions:=0
var failures:=0
func check(ok: bool,why: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func fixture():
	var sim=Sim.new(77,0,false);sim.server_mode=true;sim.evolution.sandbox=true
	sim.player.add_organ("feeding",0,"graze",false);sim.cells=[sim.player]
	sim.habitat_geometry=Sim.Habitat.new(77,sim.cells);sim.habitat_geometry.enabled=false;sim.automatic_reproduction=false
	return sim
func total(sim) -> float:
	var amount:=0.0
	for cell in sim.cells:
		if not cell.dead:amount+=cell.organic_mass()
	for packet in sim.particle_snapshots():
		if packet.alive:amount+=packet.amount*Sim.Catalog.material(packet.kind)
	return amount+sim.build_waste
func run() -> void:
	var sim=fixture();var parent=sim.player;var mass:=0.0
	parent.biomass=50;parent.energy=100
	check(parent.add_organ("toxin_sac",1,"graze",false),"Toxin sac installs with ordinary anatomy and ordinary biomass construction")
	var sac: Dictionary=parent.organs[-1];mass=total(sim)
	var energy: float=parent.energy;Sac.fill(parent,25)
	check(is_equal_approx(sac.stored_toxin,1) and absf(total(sim)-mass)<.00001 and is_equal_approx(parent.energy,energy-1),"Filling converts only paid biomass into one finite unit and charges actual ATP")
	Sac.fill(parent,1000)
	check(is_equal_approx(sac.stored_toxin,2) and absf(total(sim)-mass)<.00001,"Storage is bounded and cannot create material when full")
	var report: Dictionary=sim._emit_pheromone(parent).report
	check(report.defended and not report.hostile,"A filled sac appears as defense in an immutable emitted cue, without a new sense or aggression")
	sac.stored_toxin=0
	check(report.defended and not sim._emit_pheromone(parent).report.defended,"Old cues retain their emission-time defense while new cues see an emptied sac")
	sac.stored_toxin=2
	var restored=Codec.new().restore(Codec.new().capture(sim))
	check(restored.player.organs[-1].stored_toxin==2 and is_equal_approx(restored.player.organic_mass(),parent.organic_mass()),"Actual stored contents survive a checkpoint exactly")
	check(parent.internal_organ("toxin_sac") and parent.organ_local_position(sac).length()<parent.radius,"The sac is placed inside the cell")
	var clone=Sim.Cell.clone_state(parent);clone.energy=0;clone.update_power_state();clone.organs[-1].stored_toxin=0
	var biomass: float=clone.biomass;Sac.fill(clone,10)
	check(is_equal_approx(clone.organs[-1].stored_toxin,.1) and clone.energy==0 and clone.biomass<biomass,"Low ATP gives quarter filling without negative ATP")
	clone.biomass=12;biomass=clone.organs[-1].stored_toxin;Sac.fill(clone,100)
	check(clone.organs[-1].stored_toxin==biomass,"Filling leaves the operating biomass floor")
	var recycle=Sim.Cell.clone_state(parent);mass=recycle.organic_mass();var debris: float=recycle.recycle(recycle.organs.size()-1)
	check(absf(recycle.organic_mass()+debris-mass)<.00001 and recycle.count("toxin_sac")==0,"Recycling safely dismantles every stored unit through ordinary salvage and debris")
	mass=total(sim);sim._die(parent)
	var toxins: Array=sim.particle_snapshots().filter(func(packet):return packet.alive and packet.kind==sim.TOXIN)
	check(toxins.size()==25 and is_equal_approx(toxins.reduce(func(amount,packet):return amount+packet.amount,0.0),2),"Death emits exactly the paid contents as bounded ordinary toxin parcels")
	check(absf(total(sim)-mass)<.0001,"Stored toxin is not duplicated into nutrient lysis")
	var count: int=sim.particle_count();sim._die(parent)
	check(sim.particle_count()==count,"Repeated death cannot release a second toxin cloud")
	var victim=Sim.Cell.new(700,toxins[0].p);var family=Sim.Cell.new(701,toxins[0].p);family.lineage=parent.lineage_id()
	sim.cells=[victim,family];sim.camera_views=[Vector4(parent.position.x,parent.position.y,1500,1000)];sim.grid.rebuild(sim.particles);sim._toxin_contacts()
	check(victim.health<100 and family.health==100,"An overlapping toxin parcel is consumed by one contacted cell only")
	sim.cells=[family];sim.spawn_particle(sim.TOXIN,family.position,Vector2.ZERO,.1,parent.id);sim.grid.rebuild(sim.particles);sim._toxin_contacts()
	check(family.health<100,"A separate actual toxin contact harms the emitting lineage too")
	var bound=Sim.Cell.new(800);bound.add_organ("feeding",0,"graze",false)
	var surface=preload("res://scripts/surface_chemistry.gd")
	check(surface.bind(bound,sim.TAG,.03,0) and surface.bind(bound,sim.PORE_SUBUNIT,.0375,0),"Free pore pieces still bind into existing membrane assembly")
	var complexes: Array=bound.surface_complexes.duplicate(true)
	check(Sim.Catalog.decay(sim.TAG)==.8 and Sim.Catalog.decay(sim.PORE_SUBUNIT)==.8,"Both free pore species share the new short lifetime")
	check(bound.surface_complexes==complexes,"Free-particle lifetime does not rewrite bound complexes")
	print("TOXIN STORAGE: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
