extends RefCounted
## Finite organ-local contents. No toxin particles are simulated inside the sac.
const Catalog=preload("res://scripts/chemistry_catalog.gd")
static func capacity(organ: Dictionary) -> float:
	return float(Catalog.data().combat.toxin_sac.capacity)*organ.scale*organ.scale
static func fraction(organ: Dictionary) -> float:
	return clampf(float(organ.get("stored_toxin",0))/maxf(.000001,capacity(organ)),0,1)
static func fill(cell,dt: float) -> void:
	if cell.dead or cell.health<=0 or dt<=0:return
	var rule: Dictionary=Catalog.data().combat.toxin_sac
	for organ in cell.organs:
		if organ.kind!="toxin_sac" or organ.hp<=0:continue
		var amount: float=minf(maxf(0,cell.biomass-float(rule.biomass_floor)),minf(maxf(0,capacity(organ)-float(organ.get("stored_toxin",0))),float(rule.fill_rate)*organ.scale*organ.scale*dt*cell.work_capacity()))
		if amount<=0:continue
		cell.biomass-=amount;organ["stored_toxin"]=float(organ.get("stored_toxin",0))+amount
		cell.spend_energy(amount*float(rule.atp_per_unit),organ,"secretion")
		organ.charge_flash=1
static func release(sim,cell) -> float:
	var total:=0.0
	for organ in cell.organs:
		if organ.kind!="toxin_sac":continue
		var amount: float=float(organ.get("stored_toxin",0))
		if amount<=0:continue
		organ.stored_toxin=0.0;total+=amount
		var count: int=clampi(ceili(amount/.08),1,32)
		for i in count:
			var direction:=Vector2.from_angle(cell.angle+TAU*(i+.5)/count)
			sim.spawn_particle(sim.TOXIN,cell.position+direction*(cell.extent()+12),direction*35+cell.velocity,amount/count,sim._attack_owner(cell))
	return total
