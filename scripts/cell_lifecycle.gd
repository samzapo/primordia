extends RefCounted
## Shared authority rules. UI asks for quotes; only authority commits.
const VERSION:=1
const PERIOD:=1.0
const COOLDOWN:=60.0
const VENT_BIOMASS:=500.0
const VENT_RATE:=0.01
const VENT_NUTRIENT_SHARE:=0.7

static func migrate(sim,accounts: Dictionary={}) -> void:
	for cell in sim.cells:
		cell.ap=0
		if cell.lifecycle_version>=VERSION:continue
		cell.biomass+=cell.brood_mass;cell.energy+=cell.brood_energy
		cell.brood_mass=0;cell.brood_energy=0;cell.ap=0;cell.division_requested=false
		cell.automatic_budding=cell.automatic_division
		cell.reproduction_retry_at=maxf(cell.reproduction_retry_at,sim.time+COOLDOWN)
		for organ in cell.organs:
			if organ.kind=="feeding" and organ.get("inherent",false):
				organ.material=cell.organ_cost("feeding",organ.scale);organ.max_material=organ.material
				organ["paid_material"]=0.0;sim.external_input+=organ.material
			organ.erase("inherent")
			if not organ.has("paid_material"):organ["paid_material"]=float(organ.material)
		cell.lifecycle_version=VERSION;cell.update_geometry()
	for account in accounts.values():
		if not account.has("favorite_id"):account.favorite_id=account.selected
	retire_objectives(sim.evolution)
	for ledger in sim.family_ledgers:
		if ledger.progression!=null:retire_objectives(ledger.progression)
	for account in accounts.values():
		if account.get("evolution")!=null:retire_objectives(account.evolution)
	sim.pending_replacements=sim.pending_replacements.filter(func(item):return int(item.get("id",-1))>=0)

static func retire_objectives(progression) -> void:
	progression.points=0;progression.chosen=true;progression.offers.clear()
	progression.status="growing";progression.ending="";progression.light_factor=1.0;progression.tide=0
	progression.challenge="";progression.challenge_result="";progression.completed.clear()
	progression.viable_seconds=0;progression.offspring_id=-1
	progression.arrival_budget=0;progression.counter_budget=0;progression.resistance="";progression.resistance_clock=0

static func population(sim) -> Dictionary:
	var census: Dictionary={"living":0,"families":{}}
	for cell in sim.cells:
		if cell.dead or cell.health<=0:continue
		census.living+=1
		var root: int=cell.lineage_id()
		census.families[root]=int(census.families.get(root,0))+1
	return census

static func quote(sim,parent,mode: String,census: Dictionary={}) -> Dictionary:
	var q={"cell":parent.id,"mode":mode,"ready":false,"progress":0.0,"automatic":parent.automatic_division,"automatic_budding":parent.automatic_budding,"queued":false,"reason":"","cooldown":maxf(0,parent.reproduction_retry_at-sim.time)}
	if mode not in ["mitosis","budding"]:q.reason="Choose Mitosis or Budding.";return q
	q.material=84.0 if mode=="mitosis" else 50.0
	q.energy=56.0 if mode=="mitosis" else 78.0
	q.donation=parent.biomass*.5 if mode=="mitosis" else 42.0
	q.child_biomass=q.donation-30.0
	q.child_atp=(parent.energy-20.0)*.5 if mode=="mitosis" else 40.0
	q.progress=minf(clampf(parent.biomass/q.material,0,1),minf(clampf(parent.energy/q.energy,0,1),clampf(1-q.cooldown/COOLDOWN,0,1)))
	if census.is_empty():census=population(sim)
	if parent.dead or parent.health<=0:q.reason="Only a living cell can reproduce."
	elif q.cooldown>0:q.reason="Resting: %ds until reproduction." % ceili(q.cooldown)
	elif int(census.families.get(parent.lineage_id(),0))>=sim.FamilyMerging.MAX_FAMILY_CELLS:q.reason="Family full: %d living cells. Division waits for room." % sim.FamilyMerging.MAX_FAMILY_CELLS
	elif census.living>=sim.MAX_LIVE_CELLS:q.reason="Pond full: %d living cells. Division waits for room." % sim.MAX_LIVE_CELLS
	elif not parent.working("feeding") and not parent.working("photosynthesis") and not parent.working("proboscis"):q.reason="Build an oral groove, proboscis or leaf first."
	elif parent.biomass<q.material or parent.energy<q.energy:q.reason="%s needs %.0f biomass and %.0f ATP, including survival reserves." % [mode.capitalize(),q.material,q.energy]
	else:q.ready=true;q.reason="%s ready. No clear water is required." % mode.capitalize()
	return q

static func reproduce(sim,parent,ledger,mode: String,follow: bool=false) -> bool:
	if sim.remote_client:return false
	var q=quote(sim,parent,mode)
	if not q.ready:return false
	var child=sim.Cell.new(sim.next_id)
	child.body=30.0;child.biomass=q.child_biomass;child.energy=q.child_atp;child.ap=0
	child.role="descendant";child.generation=parent.generation+1;child.lineage=parent.lineage_id()
	child.lifecycle_version=VERSION
	child.add_organ("feeding",0,"graze",false);child.add_organ("photosynthesis",PI,"graze",false)
	child.automatic_division=parent.automatic_division;child.automatic_budding=parent.automatic_budding
	child.reproduction_retry_at=sim.time+COOLDOWN;parent.reproduction_retry_at=sim.time+COOLDOWN
	child.position=sim._birth_position(parent,child);child.previous_position=child.position
	child.angle=parent.angle;child.previous_angle=child.angle
	child.chemistry.partition(parent.chemistry,.5 if mode=="mitosis" else .25)
	parent.biomass-=q.donation;parent.spend_energy(20.0+q.child_atp,{},"reproduction")
	parent.division_requested=false;parent.update_geometry();child.update_geometry()
	parent.render_revision+=1;sim.external_input+=20.0 # Explicit two-place starter material grant.
	sim.Investment.inherit_strategy(sim,parent,child)
	sim.inherited_lineages[child.id]=child.lineage_id();sim.next_id+=1
	ledger.births+=1;ledger.register(child,parent.id,child.generation,"living",sim.time)
	if ledger.progression!=null:ledger.progression.divided(parent)
	sim.cells.append(child);sim._record_sound("division",parent.position,parent.id)
	sim.events.append({"type":"division","id":child.id,"parent":parent.id,"mode":mode,"time":sim.time})
	if sim.events.size()>128:sim.events.pop_front()
	if follow:sim.player=child
	ledger.notify(mode.capitalize()+": a daughter joined the family.")
	return true

static func step(sim) -> void:
	if sim.remote_client:return
	if sim.time<sim.lifecycle_due:return
	sim.FamilyMerging.enforce_limit(sim)
	sim.lifecycle_due+=floor((sim.time-sim.lifecycle_due)/PERIOD+1)*PERIOD
	var census:=population(sim)
	for cell in sim.cells.duplicate():
		if cell.dead or cell.health<=0:continue
		crowding(sim,cell)
		if not sim.automatic_reproduction or sim.time<cell.reproduction_retry_at:continue
		var hostile=not cell.behavior.get("weapon_cue",{}).is_empty() or cell.threat.length_squared()>.01
		var mode="budding" if hostile and cell.automatic_budding else "mitosis" if cell.automatic_division else "budding"
		if (mode=="budding" and not cell.automatic_budding) or (mode=="mitosis" and not cell.automatic_division):continue
		if not quote(sim,cell,mode,census).ready:continue
		if sim.ecology_rng.randf()<(.1 if hostile else .05) and reproduce(sim,cell,sim._family_ledger(cell),mode):
			census.living+=1
			census.families[cell.lineage_id()]=int(census.families.get(cell.lineage_id(),0))+1

static func crowding(sim,cell) -> void:
	if cell.unattended_protected or sim.FamilyMerging.managed(sim,cell) or cell.behavior.has("autolysis_at"):return
	var reports={}
	for collection in [cell.behavior.get("family_cues",{}),cell.behavior.get("merge_cues",{})]:
		for id in collection:
			var cue=collection[id]
			var report=cue.get("report",{})
			if cue.get("expires_at",0)>sim.time and int(id)!=cell.id and int(report.get("id",-1))==int(id) and int(report.get("lineage",-1))==cell.lineage_id():reports[id]=true
	if reports.size()<=6:cell.behavior.erase("crowded_since");return
	if not cell.behavior.has("crowded_since"):cell.behavior["crowded_since"]=sim.time
	if sim.time-cell.behavior.crowded_since<10 or sim.time<float(cell.behavior.get("autolysis_check",0)):return
	var due: float=cell.behavior.get("autolysis_check",cell.behavior.crowded_since+10)
	cell.behavior["autolysis_check"]=due+floor((sim.time-due)/5+1)*5
	var key=cell.lineage_id()
	if sim.time<float(sim.autolysis_after.get(key,0)):return
	if sim.ecology_rng.randf()<minf(.01,.002*(reports.size()-6)):
		cell.behavior["autolysis_at"]=sim.time+3;sim.autolysis_after[key]=sim.time+60

static func physiology(sim,cell,dt: float) -> void:
	# This is surplus-reserve release, not a limit on food, anatomy or cell life.
	if cell.unattended_protected:
		cell.behavior.erase("autolysis_at")
	elif cell.behavior.has("autolysis_at") and sim.time>=cell.behavior.autolysis_at:
		cell.health=0;cell.death_hint="Crowding autolysis";return
	var surplus: float=maxf(0,cell.biomass-VENT_BIOMASS)
	if cell.unattended_protected or surplus<=0:
		cell.behavior.erase("stress");cell.behavior.erase("leak_elapsed")
		cell.holes=cell.holes.filter(func(h):return not h.get("stress",false))
		return
	cell.behavior["stress"]=true
	if not cell.holes.any(func(h):return h.get("stress",false)):cell.holes.append({"a":PI,"size":.15,"stress":true})
	cell.behavior["leak_elapsed"]=float(cell.behavior.get("leak_elapsed",0))+dt
	if cell.behavior.leak_elapsed<.5:return
	var elapsed: float=cell.behavior.leak_elapsed;cell.behavior.leak_elapsed=0.0
	# Exact decay of the surplus: finite even after a late/coarse update and
	# never below the threshold. Higher biomass gives a larger outward flux.
	var amount: float=surplus*(1-exp(-VENT_RATE*elapsed))
	if amount<=0:return
	cell.biomass-=amount
	var normal: Vector2=cell.local_normal(PI).rotated(cell.angle)
	var at: Vector2=cell.position+cell.local_point(PI).rotated(cell.angle)+normal*12
	var nutrients: float=amount*VENT_NUTRIENT_SHARE
	var waste: float=amount-nutrients
	sim.spawn_particle(sim.NUTRIENT,at,cell.velocity+normal*18,nutrients,cell.id)
	# Nutrient fuel comes from the tissue actually lost, not fresh-food fuel.
	sim.last_spawn.capacity=minf(nutrients,amount*cell.Chemistry.TISSUE_FUEL/cell.Chemistry.FOOD_FUEL)
	sim._commit_spawn_metadata()
	sim.spawn_particle(sim.WASTE,at+normal*3,cell.velocity+normal*14,waste,cell.id)
	cell.update_geometry()
