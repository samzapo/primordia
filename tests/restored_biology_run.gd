extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Cell=preload("res://scripts/cell.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Weather=preload("res://scripts/environment_cycle.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=Sim.new(51)
	sim.cells=[sim.player];sim.automatic_reproduction=false
	var parent=sim.player
	var quote: Dictionary=sim.offspring_quote()
	parent.brood_mass=quote.material;parent.brood_energy=quote.energy
	var ap: int=sim.player.ap
	check(sim._divide_paid(parent,sim.lineage,false,false,true),"A paid division succeeds")
	check(sim.player.ap==ap+1 and sim.evolution.division_count==1,"One AP goes to each body at a committed division")
	check(not sim._divide_paid(parent,sim.lineage,false,false,true) and sim.player.ap==ap+1,"Failed division cannot award AP")
	var saved=Codec.new().restore(Codec.new().capture(sim))
	check(saved.player.ap==ap+1 and saved.lineage.progression==saved.evolution,"Checkpoint keeps reward totals and shared account progression")
	var mixed=Cell.new(99);mixed.chemistry.emit("food",1,Vector2(30,0),-1,-1,0);mixed.chemistry.emit("food",1,Vector2(-30,0),-1,-1,7.5);mixed.chemistry.solar_work=8
	var mixed_copy=Cell.clone_state(mixed)
	check(mixed_copy.chemistry.particles==mixed.chemistry.particles and mixed_copy.chemistry.solar_work==8,"Editor cloning preserves individual finite fuel and solar accounting")
	var offers:=0
	for seed_number in 1000:
		var run=Sim.Evolution.new(seed_number)
		run.divided(parent)
		if not run.division_offers.is_empty():offers+=1
	check(offers>=65 and offers<=135,"Seeded division samples follow the ten percent offer probability")
	sim.evolution.division_offers.assign(["economical_flagellum"])
	check(sim.edit("choose_mutation",{"gene":"economical_flagellum"}),"An offered mutation is free to acquire")
	check(not sim.edit("choose_mutation",{"gene":"economical_flagellum"}),"Replayed acquisition cannot duplicate an offer")
	parent.add_organ("propulsion",PI,"graze",false)
	var organ: Dictionary=parent.organs[-1]
	sim.player.ap=0;parent.biomass=0
	check(sim.mutate_organ(organ.id,"economical_flagellum") and parent.biomass==0 and sim.player.ap==0,"Applying a mutation costs neither biomass nor AP")
	check(not sim.mutate_organ(organ.id,"economical_flagellum"),"An organ accepts its mutation once")
	for action in ["tension","link_add","link_remove"]:
		check(sim.edit(action,{"id":0,"value":.8})==false,"Live commands cannot edit procedural microtubules")
	var first:=1792065600.0 # Fixed calendar input, never the test machine clock.
	check(Weather.update(sim,first),"Hourly conditions initialize")
	var environment: Dictionary=sim.environment.duplicate(true)
	var tide: PackedVector2Array=sim.fluid.tide.duplicate()
	check(not Weather.update(sim,first+300) and sim.environment==environment and sim.fluid.tide==tide,"Conditions are fixed within the hour")
	# Upgrade the reduced-current revision without replacing any actual velocity.
	sim.environment.flow_version = 1
	for i in sim.fluid.tide.size(): sim.fluid.tide[i] *= .35
	var water_before: PackedVector2Array = sim.fluid.velocity.duplicate()
	check(Weather.update(sim,first+300) and sim.fluid.tide==tide and sim.environment==environment,"The reduced-current save refreshes to the original ambient strength within the same hour")
	check(sim.fluid.velocity==water_before,"Restoring the ambient target preserves every saved water velocity")

	var recovered=Codec.new().restore(Codec.new().capture(sim))
	check(not Weather.update(recovered,first+600) and recovered.environment==environment,"Saved conditions do not reroll on restart")
	check(Weather.update(sim,first+3600) and int(sim.environment.hour)==int(environment.hour)+1,"A new hour resamples calendar-derived conditions")
	Weather.update(recovered,first+3600)
	check(recovered.environment==sim.environment and recovered.fluid.tide==sim.fluid.tide,"Same pond and calendar hour produce identical conditions")
	var aerobic=Cell.new(10);var anaerobic=Cell.new(11)
	for cell in [aerobic,anaerobic]:
		cell.chemistry.emit("food",2,Vector2(30,0))
	aerobic.chemistry.emit("oxygen",2,Vector2(30,0),-1,-1,0)
	var mass_a: float=aerobic.organic_mass();var mass_b: float=anaerobic.organic_mass()
	var potential_a: float=aerobic.biomass*7.5+aerobic.energy+aerobic.raw_fuel
	for cell in [aerobic,anaerobic]:cell.chemistry.advance(cell,1)
	check(aerobic.oxygen<2 and anaerobic.fermented>0,"Local oxygen is consumed; no oxygen triggers fermentation")
	check(aerobic.biomass>anaerobic.biomass and aerobic.energy>anaerobic.energy,"Respiration yields more tissue and ATP than fermentation")
	check(absf(aerobic.organic_mass()-mass_a)<.000001 and absf(anaerobic.organic_mass()-mass_b)<.000001,"Both metabolic branches conserve represented material")
	check(absf(aerobic.biomass*7.5+aerobic.energy+aerobic.raw_fuel+aerobic.chemistry.heat-potential_a)<.000001,"Respiration retains finite fuel accounting")
	check(aerobic.carbon>0 and anaerobic.carbon>0,"Carbon byproducts are finite intracellular particles")
	var distant=Cell.new(12);distant.chemistry.emit("food",2,Vector2(30,0));distant.chemistry.emit("oxygen",2,Vector2(-30,0),-1,-1,0)
	distant.chemistry.advance(distant,.1)
	check(distant.oxygen==2 and distant.fermented>0,"Distant oxygen cannot teleport to a food vacuole")
	var plant=Cell.new(13);plant.add_organ("photosynthesis",0,"graze",false)
	var site: Vector2=plant.local_point(0)*.72
	plant.chemistry.emit("carbon",2,site,-1,-1,0)
	var mass: float=plant.organic_mass();var before: float=plant.energy+plant.biomass*7.5+plant.raw_fuel+plant.chemistry.heat
	var exterior_before: float=sim.particle_snapshots().reduce(func(total,p):return total+(p.amount if p.alive and p.kind==Sim.NUTRIENT and p.owner==plant.id else 0.0),0.0)
	plant.chemistry.photosynthesize(sim,plant,plant.organs[0],1)
	check(plant.fixed_carbon>0 and plant.oxygen>0 and plant.substrate>0,"Light and local carbon make food and oxygen particles")
	var shared_food: float=sim.particle_snapshots().reduce(func(total,p):return total+(p.amount if p.alive and p.kind==Sim.NUTRIENT and p.owner==plant.id else 0.0),0.0)-exterior_before
	check(absf(plant.organic_mass()+shared_food-mass)<.000001,"Internal and shared exterior photosynthate conserve carbon material")
	check(absf(plant.energy+plant.biomass*7.5+plant.raw_fuel+plant.chemistry.heat+shared_food*7.5-before-plant.chemistry.solar_work)<.000001,"Photosynthesis records the solar energy input explicitly")
	check(int(plant.organs[0].get("emission_serial",0))>0,"Photosynthetic production triggers gland bounce")
	var starving=Cell.new(15);starving.energy=0
	var stored: float=starving.organic_mass()
	sim._metabolize(starving,1)
	check(starving.reserve_used>0 and starving.substrate>0 and starving.biomass>=8,"Low ATP mobilizes only surplus biomass into finite food fuel")
	check(absf(starving.organic_mass()-stored)<.000001,"Emergency mobilization transfers rather than creates material")
	var outlet=Cell.new(16);outlet.chemistry.emit("carbon",1,outlet.local_point(0)*.92,-1,-1,0)
	sim.particles=[];outlet.chemistry.excrete(sim,outlet,1)
	check(sim.particles.size()==1 and sim.particles[0].kind==5 and outlet.carbon==0,"Carbon leaves through a real membrane crossing once")
	for kind in ["feeding","neutralizing","acidifying","regenerative","toxin","poreforming"]:
		var gland=Cell.new(100);gland.biomass=100;gland.energy=2000;gland.acid_stress=1
		gland.add_organ(kind,0,"graze",false)
		if kind in ["toxin","poreforming"]:
			gland.add_organ("hunting",1,"hunt",false)
			gland.behavior["weapon_cue"]={"at":gland.position+Vector2(100,0),"id":999,"organ_id":gland.organs[-1].id,"expires_at":sim.time+10,"lineage":999}
		gland.target_id=999;gland.target_memory=10;gland.target_position=gland.position+Vector2(100,0);gland.target_mode="hunt"
		sim.cells=[gland];sim.player=gland;sim.particles=[]
		sim.spawn_particle(Sim.WASTE,gland.organ_position(gland.organs[0])+Vector2(15,0),Vector2.ZERO,1,999)
		sim.spawn_particle(Sim.TOXIN,gland.organ_position(gland.organs[0])+Vector2(20,0),Vector2.ZERO,1,999)
		sim.grid.rebuild(sim.particles)
		for i in 5:sim._emit_and_attack(gland,1)
		check(int(gland.organs[0].get("emission_serial",0))>0,"Actual "+kind+" production triggers gland bounce")
	print("RESTORED BIOLOGY: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
