extends RefCounted
## Shared authority rules. UI asks for quotes; only authority commits.
const VERSION:=1
const PERIOD:=1.0
const COOLDOWN:=60.0

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
	sim.evolution.points=0
	for ledger in sim.family_ledgers:
		if ledger.progression!=null:ledger.progression.points=0

static func quote(sim,parent,mode: String) -> Dictionary:
	var q={"cell":parent.id,"mode":mode,"ready":false,"progress":0.0,"automatic":parent.automatic_division,"automatic_budding":parent.automatic_budding,"queued":false,"reason":"","cooldown":maxf(0,parent.reproduction_retry_at-sim.time)}
	if mode not in ["mitosis","budding"]:q.reason="Choose Mitosis or Budding.";return q
	q.material=84.0 if mode=="mitosis" else 50.0
	q.energy=56.0 if mode=="mitosis" else 78.0
	q.donation=parent.biomass*.5 if mode=="mitosis" else 42.0
	q.child_biomass=q.donation-30.0
	q.child_atp=(parent.energy-20.0)*.5 if mode=="mitosis" else 40.0
	q.progress=minf(clampf(parent.biomass/q.material,0,1),minf(clampf(parent.energy/q.energy,0,1),clampf(1-q.cooldown/COOLDOWN,0,1)))
	if parent.dead or parent.health<=0:q.reason="Only a living cell can reproduce."
	elif q.cooldown>0:q.reason="Resting: %ds until reproduction." % ceili(q.cooldown)
	elif sim.cells.filter(func(c):return not c.dead).size()>=sim.MAX_LIVE_CELLS and sim.FamilyMerging.living_families(sim).get(parent.lineage_id(),[]).size()<12:q.reason="The pond's population safety limit is reached."
	elif not parent.working("feeding") and not parent.working("photosynthesis"):q.reason="Build an oral groove or leaf first."
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
	var folded=sim.FamilyMerging.fold_newborn(sim,parent,child)
	if follow and not folded:sim.player=child
	ledger.notify(mode.capitalize()+": daughter reabsorbed at the family limit." if folded else mode.capitalize()+": a daughter joined the family.")
	return true

static func step(sim) -> void:
	if sim.remote_client:return
	migrate(sim)
	sim.FamilyMerging.enforce_limit(sim)
	if sim.time<sim.lifecycle_due:return
	sim.lifecycle_due+=floor((sim.time-sim.lifecycle_due)/PERIOD+1)*PERIOD
	for cell in sim.cells.duplicate():
		if cell.dead or cell.health<=0:continue
		crowding(sim,cell)
		if not sim.automatic_reproduction or sim.time<cell.reproduction_retry_at:continue
		var hostile=not cell.behavior.get("weapon_cue",{}).is_empty() or cell.threat.length_squared()>.01
		var mode="budding" if hostile and cell.automatic_budding else "mitosis" if cell.automatic_division else "budding"
		if (mode=="budding" and not cell.automatic_budding) or (mode=="mitosis" and not cell.automatic_division):continue
		if not hostile and (cell.biomass<168 or cell.energy<100):continue
		if sim.ecology_rng.randf()<(.1 if hostile else .01):reproduce(sim,cell,sim._family_ledger(cell),mode)

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
	if cell.unattended_protected:
		cell.behavior.erase("autolysis_at");cell.behavior.erase("stress");cell.holes=cell.holes.filter(func(h):return not h.get("stress",false))
		return
	if cell.behavior.has("autolysis_at") and sim.time>=cell.behavior.autolysis_at:
		cell.health=0;cell.death_hint="Crowding autolysis";return
	var capacity=3000.0
	for organ in cell.organs:
		if organ.kind=="protection":capacity+=1000*organ.scale*organ.scale*organ.hp/organ.max_hp
	var mass=cell.organic_mass()
	if mass>capacity:cell.behavior["stress"]=true
	elif mass<capacity*.9:cell.behavior.erase("stress")
	if not cell.behavior.get("stress",false):
		cell.holes=cell.holes.filter(func(h):return not h.get("stress",false));return
	if not cell.holes.any(func(h):return h.get("stress",false)):cell.holes.append({"a":PI,"size":.15,"stress":true})
	cell.behavior["leak_elapsed"]=float(cell.behavior.get("leak_elapsed",0))+dt
	if cell.behavior.leak_elapsed<.5:return
	var elapsed: float=cell.behavior.leak_elapsed;cell.behavior.leak_elapsed=0.0
	var budget=maxf(0,mass-capacity*.9)*.01*elapsed
	var amount=minf(cell.biomass,budget);cell.biomass-=amount;budget-=amount
	var tissue=minf(maxf(0,cell.body-30),budget);cell.body-=tissue;amount+=tissue;budget-=tissue
	var at=cell.position+Vector2.from_angle(cell.angle+PI)*(cell.extent()+12)
	if amount>0:
		# One finite parcel per batch, rather than a shower of tiny leaks.
		sim.spawn_particle(sim.NUTRIENT,at,Vector2.ZERO,amount,cell.id)
		sim.last_spawn.capacity=amount*cell.Chemistry.TISSUE_FUEL/cell.Chemistry.FOOD_FUEL;sim._commit_spawn_metadata()
	if budget>0 and cell.chemistry.material()>0:
		cell.chemistry.ensure_cpu()
		for packet in cell.chemistry.particles:
			if budget<=0:break
			if not packet.alive or packet.species=="oxygen":continue
			var used=minf(packet.amount,budget)
			var nutrition=float(packet.get("nutrition",0))/maxf(.000000001,packet.amount)
			var fuel=cell.chemistry._consume(packet,used);budget-=used
			var kind={"food":sim.NUTRIENT,"waste":sim.WASTE,"carbon":sim.CARBON}[packet.species]
			sim.spawn_particle(kind,at,Vector2.ZERO,used,cell.id)
			if kind==sim.NUTRIENT:
				sim.last_spawn.capacity=minf(used,fuel/cell.Chemistry.FOOD_FUEL)+used*nutrition;sim._commit_spawn_metadata()
		cell.chemistry.refresh()
	cell.update_geometry()
