extends RefCounted
const Sim=preload("res://scripts/simulation.gd")
const Cues=preload("res://tests/pheromones.gd")
const Policy=preload("res://scripts/cell_behavior.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Perception=preload("res://scripts/resident_perception.gd")
const DT:=1.0/60
static func run(check: Callable) -> void:
	var sim=Cues.isolated();var cell=sim.player
	cell.add_organ("feeding",PI,"graze",false);cell.add_organ("propulsion",1,"graze",false)
	var prey=sim._make_cell(cell.position+Vector2(100,0),"grazer")
	Cues.deliver(sim,prey)
	sim.spawn_particle(Sim.NUTRIENT,cell.position-Vector2(100,0),Vector2.ZERO,1,77)
	sim.grid.rebuild(sim.particles)
	cell.energy=10;Cues.listen(sim)
	check.call(cell.target_mode=="graze" and cell.target.x<0,"Low ATP chooses actual food over a local prey report")
	cell.energy=25;Cues.listen(sim)
	check.call(cell.target_mode=="graze","Energy recovery uses hysteresis instead of flickering at one threshold")
	cell.energy=100;Cues.listen(sim)
	check.call(cell.target_mode=="hunt","A healthy hunter follows available prey rather than a forced exploration cycle")
	cell.biomass=1;Cues.listen(sim)
	check.call(cell.target_mode=="graze","Low biomass prioritizes accessible food before a hunt")
	sim.particles=sim.particles.filter(func(p):return p.kind==Sim.PHEROMONE);sim.grid.rebuild(sim.particles)
	Cues.listen(sim,2)
	check.call(cell.target_mode=="hunt" and cell.target_memory>0,"A hungry cell can hunt when its only usable local cue is prey")
	# Own physiology, never role/player identity, determines the common policy.
	var duplicate=Sim.Cell.clone_state(cell);duplicate.role="producer"
	Policy.update(duplicate)
	check.call(Policy.priority(duplicate,"hunt")==Policy.priority(cell,"hunt"),"Role labels and ownership cannot grant a different behavior tree")
	cell.biomass=20;cell.energy=5;cell.substrate=4
	sim.particles.clear();sim.grid.clear();cell.signals.clear();cell.target_memory=0
	Cues.listen(sim)
	check.call(cell.target==Vector2.ZERO and cell.state.contains("DIGESTING"),"Low ATP and actual stored food select recovery without paid swimming")
	var energy: float=cell.energy
	sim.fluid.set_camera(cell.position,sim.view_half)
	sim._motion_cell(cell,DT)
	check.call(cell.energy==energy,"Recovery does not spend propulsion ATP or manufacture energy")
	cell.substrate=0;Cues.listen(sim)
	check.call(cell.target.length_squared()>.99 and cell.state.contains("SEARCHING"),"A starving cell with no received food cue searches instead of inventing a remote target")
	var heading: Vector2=cell.target
	cell.angle+=2;sim._sense(cell,DT)
	check.call(cell.target==heading,"Search direction is independent of body rotation")
	cell.age+=DT;sim._sense(cell,DT)
	check.call(cell.target.distance_to(heading)<.03,"Automatic search turns smoothly, without timed heading jumps")
	var old_organs: Array=cell.organs.duplicate(true)
	cell.exploration=4;cell.response_cycle=8
	for organ in cell.organs:organ["steering"]=0;organ["output"]=4
	var legacy: Array=cell.organs.duplicate(true)
	check.call(not sim.edit("steering",{"id":cell.organs[0].id,"value":4}) and not sim.edit("exploration",{"value":0}) and not sim.edit("cycle",{"value":2}),"All retired tuning commands are rejected")
	check.call(cell.organs==legacy and cell.exploration==4 and cell.response_cycle==8,"Retired commands leave saved anatomy and old fields untouched")
	var restored=Codec.new().restore(Codec.new().capture(sim))
	check.call(restored.player.organs==legacy and restored.player.behavior==cell.behavior and restored.player.exploration==4,"Checkpoint retains actual anatomy and bounded behavior memory exactly")
	check.call(cell.organs.size()==old_organs.size(),"Introducing instincts never adds or removes existing organs")
	# Actual attacks + locally received family chemistry; source bodies may be absent.
	sim=Cues.isolated();cell=sim.player;cell.organs.clear()
	cell.add_organ("sensing",0,"flee",false);cell.add_organ("propulsion",PI,"graze",false)
	var sibling=Sim.Cell.new(888,cell.position+Vector2(-50,70));sibling.lineage=cell.lineage_id()
	var packet: Dictionary=Cues.deliver(sim,sibling)
	sibling.position+=Vector2(2000,1000)
	cell.damage(1,0,999);Cues.listen(sim)
	check.call(cell.target_mode=="evade" and cell.target.x<0 and cell.target.y<0,"After an attack, escape also separates from locally reported family")
	check.call(cell.facing==cell.target and cell.threat==Vector2.ZERO,"The actual steering turn follows the family-separating escape heading")
	check.call(cell.target_id==-1 and not sim.cells.has(sibling),"Family separation does not target a relative or look up a live source")
	packet.expires_at=sim.time
	cell.behavior["escape_expires_at"]=sim.time
	cell.sense_clock=10;sim._sense(cell,DT)
	check.call(absf(cell.target.y)<.0001,"Family separation ends at the received report deadline, even during a held escape")
	cell.target_memory=0;cell.signals.clear();cell.sense_clock=0;Cues.listen(sim)
	check.call(absf(cell.target.y)<.0001 and cell.target.x<0,"An expired family report cannot steer an escape")
	cell.age+=4;cell.sense_clock=0;Cues.listen(sim,2)
	check.call(cell.target_mode!="evade" or cell.target_memory==0,"Wound escape has a bounded lifetime")
	# Harmful acid uses samples at the working flight receptor, not the whole pond.
	for i in sim.acidity.values.size():
		var x: float=(i%Sim.Medium.COLS+.5)*Sim.Medium.SIZE
		sim.acidity.values[i]=clampf(.7+(x-cell.position.x)*.002,0,1)
	cell.sense_clock=0;Cues.listen(sim)
	check.call(cell.target_mode=="acid" and cell.target.x<-.99,"A flight receptor chooses the local less-acidic direction before ordinary food/hunting")
	cell.organs[0].hp=0;cell.signals.clear();cell.target_memory=0;cell.sense_clock=0;Cues.listen(sim)
	check.call(cell.target_mode!="acid" or cell.target_memory==0,"A destroyed receptor supplies no acidity gradient or stale acid intention")
	var requests: Array=Perception.requests([cell],.2,sim.time)
	check.call(requests.is_empty(),"Resident scheduling requests no chemical information from a destroyed receptor")
	cell.organs[0].hp=cell.organs[0].max_hp;cell.sense_clock=0
	requests=Perception.requests([cell],.2,sim.time)
	check.call(requests.size()==2 and requests[1].mode=="family","Resident policy obtains family facts through a separate bounded local chemical query")
	# All decisions remain read-only with respect to chemistry and ecology RNG.
	var material: int=hash(sim.particles)
	var states: Array=[sim.rng.state,sim.background_rng.state,sim.ecology_rng.state]
	Cues.listen(sim)
	check.call(material==hash(sim.particles) and states==[sim.rng.state,sim.background_rng.state,sim.ecology_rng.state],"Behavior does not create particles, change mass or consume ecology random streams")
	investment(check)
static func investment(check: Callable) -> void:
	var sim=Sim.new(891,0,false);var policy=sim.Investment
	var seen: Dictionary={}
	var covered: Array=policy.MANUAL_ONLY.duplicate()
	for roles in policy.VARIANTS.values():
		for organs in roles:
			for kind in organs:
				if kind not in covered:covered.append(kind)
	for kind in Sim.Cell.KINDS:
		check.call(kind in covered,"Every organ has an explicit investment role or a deliberate manual-only decision")
	check.call(policy.MANUAL_ONLY.is_empty() and "sanctuary" not in covered,"The removed Sanctuary has no active investment role")
	for role in ["hunter","producer","grazer"]:
		var variants: Dictionary={}
		for id in range(200,210):
			var cell=Sim.Cell.new(id);cell.lineage=id;cell.add_organ("feeding",0,"graze",false)
			sim.cells=[cell];sim.player=cell;sim.lineage.root_id=id;sim.investment.lineages[id]=role
			var rng: int=sim.rng.state
			var organs: Array=cell.organs.duplicate(true)
			var choice: Dictionary=policy.candidate(sim,cell)
			check.call(choice.kind==policy.PRIORITIES[role][0],"Every investment strategy begins with its recognizable core")
			check.call(cell.organs==organs and sim.rng.state==rng,"Investment proposals never spend AP, alter anatomy or consume RNG")
			cell.add_organ(choice.kind,1,"hunt" if choice.kind=="hunting" else "graze",false)
			choice=policy.candidate(sim,cell)
			check.call(choice.kind!=policy.PRIORITIES[role][0],"The next purchase complements the core instead of blindly duplicating it")
			variants[choice.kind]=true;seen[choice.kind]=true
			cell.health=50;cell.acid_stress=.5
			var repair: Dictionary=policy.candidate(sim,cell)
			check.call(not repair.is_empty(),"An injured strategy retains a fitting support-organ purchase")
		check.call(variants.size()>1,"Each role has deterministic, diverse supporting build preferences")
	check.call(seen.size()>=5,"Different roles produce meaningfully different supporting anatomy")

	var injured=Sim.Cell.new(1001)
	injured.add_organ("feeding",0,"graze",false);injured.add_organ("hunting",1,"hunt",false)
	injured.add_organ("toxin",2,"graze",false);injured.add_organ("propulsion",3,"graze",false)
	injured.health=50;sim.cells=[injured];sim.player=injured;sim.lineage.root_id=injured.id
	sim.investment.lineages[injured.id]="hunter"
	check.call(policy.candidate(sim,injured).kind=="regenerative","A complete but injured hunter shifts investment toward repair support")
