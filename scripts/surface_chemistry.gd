extends RefCounted
## Finite membrane assemblies. Contact, not a remote target, supplies material.
const TAG := 11
const SUBUNIT := 12
const INHIBITOR := 7
const REQUIRED := 4
const MAX_COMPLEXES := 64

static func bind(cell, kind: int, amount: float, world_angle: float, source: int = -1) -> bool:
	if amount <= 0 or cell.dead: return false
	var a: float = cell.surface_parameter(world_angle-cell.angle)
	var closest := {}
	var best := 0.30
	for complex in cell.surface_complexes:
		var gap: float = absf(wrapf(complex.a-a,-PI,PI))
		if gap < best: closest = complex; best = gap
	if kind == TAG:
		if closest.is_empty():
			if cell.surface_complexes.size() >= MAX_COMPLEXES: return false
			cell.surface_complexes.append({"a":a,"material":amount,"units":0,"age":0.0,"capped":false,"repair":0.0,"source":source})
		else: closest.material += amount
	elif kind == SUBUNIT:
		if closest.is_empty() or closest.capped: return false
		closest.material += amount
		closest.units = mini(REQUIRED,closest.units+1)
	elif kind == INHIBITOR:
		if closest.is_empty() or closest.units >= REQUIRED: return false
		closest.material += amount
		closest.capped = true
	else: return false
	cell.render_revision += 1
	return true

static func advance(cell, dt: float, sim = null) -> void:
	var remaining: Array = []
	for complex in cell.surface_complexes:
		complex.age += dt
		var cleared: bool = complex.capped or complex.age >= 20
		if complex.units >= REQUIRED and not complex.capped:
			var angle: float = cell.angle+complex.a
			var debris: float = cell.damage(float(preload("res://scripts/chemistry_catalog.gd").data().combat.pore_damage_per_second)*dt,angle,int(complex.get("source",-1)))
			cell.waste += debris
			if sim != null and complex.get("source",-1)==sim.player.id: sim.evolution.record("pore",float(preload("res://scripts/chemistry_catalog.gd").data().combat.pore_damage_per_second)*dt)
			cell.death_hint = "Membrane failed after assembled chemical pores"
			var repair: float = cell.count("regenerative")
			if repair > 0:
				var spent: float = cell.spend_energy_at(dt*0.25*repair,cell.local_point(complex.a)*0.9,maxf(12,cell.radius*0.35),"pore removal")
				complex.repair += spent/0.25
				if complex.repair >= 2: cleared = true
		if cleared: cell.waste += complex.material
		else: remaining.append(complex)
	cell.surface_complexes = remaining
