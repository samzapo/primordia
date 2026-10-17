extends RefCounted
## Shared priority selector. Only own physiology and received local cues enter it.
## This policy proposes intentions; organs, ATP and physical contact do the work.
const DESCRIPTION:="Escape harmful acid or an attack first. Use only locally received chemical, light and acidity cues. With low ATP, find food or useful light; rest if food is already digesting. With little biomass, forage or follow prey traces. With healthy reserves, hunt when equipped, seek suitable light, or explore. Under attack, nearby family traces help the cell spread out. Organs determine the senses and movement available."
static func update(cell) -> void:
	var scale: float=cell.growth_scale()
	var low_energy: bool=cell.behavior.get("low_energy",false)
	var low_mass: bool=cell.behavior.get("low_mass",false)
	if cell.energy<18*scale:low_energy=true
	elif cell.energy>36*scale:low_energy=false
	if cell.biomass<maxf(4,cell.body*.10):low_mass=true
	elif cell.biomass>maxf(8,cell.body*.22):low_mass=false
	cell.behavior["low_energy"]=low_energy
	cell.behavior["low_mass"]=low_mass

static func priority(cell, mode: String) -> int:
	match mode:
		"acid":return 1000
		"evade":return 950
		"flee":return 900
		"graze":
			if cell.behavior.get("low_energy",false):return 800
			if cell.behavior.get("low_mass",false):return 600
			return 300 if cell.substrate<18*cell.growth_scale() else 0
		"light":return 700 if cell.behavior.get("low_energy",false) else 400 if cell.behavior.get("low_mass",false) else 250
		"hunt":
			if cell.behavior.get("low_energy",false):
				return 0 if cell.energy<12 or digesting(cell) else 350
			return 550 if cell.behavior.get("low_mass",false) else 500
	return 0

static func digesting(cell) -> bool:
	return cell.substrate>maxf(1,2*cell.growth_scale())

static func fallback(cell, seed_value: int) -> Dictionary:
	if cell.behavior.get("low_energy",false) and digesting(cell):
		return {"direction":Vector2.ZERO,"state":"RESTING · DIGESTING FOOD"}
	var phase: float=TAU*posmod(cell.id*19349663 ^ seed_value*83492791,65521)/65521.0
	# Smooth, persistent search; independent of camera, body rotation and RNG.
	var heading: float=phase+cell.age*.045+sin(cell.age*.13+phase)*.65+sin(cell.age*.37+phase*.7)*.35
	var state: String="SEARCHING FOR FOOD" if cell.behavior.get("low_energy",false) else "SEARCHING FOR FOOD OR PREY" if cell.behavior.get("low_mass",false) else "EXPLORING"
	return {"direction":Vector2.from_angle(heading),"state":state}

static func escape(away: Vector2, families: Dictionary, cell, now: float) -> Dictionary:
	var nearest: Dictionary={}
	for detected in families.values():
		var report: Dictionary=detected.report
		if detected.expires_at<=now or report.lineage!=cell.lineage_id() or report.id==cell.id:continue
		if nearest.is_empty() or detected.distance<nearest.distance or (detected.distance==nearest.distance and report.id<nearest.report.id):
			nearest=detected
	if nearest.is_empty():return {"direction":away.normalized(),"expires_at":INF}
	var delta: Vector2=preload("res://scripts/medium.gd").offset(cell.position,nearest.report.at)
	if delta.length_squared()<.0001:return {"direction":away.normalized(),"expires_at":INF}
	# Never let crowd avoidance turn an escape back toward its threat.
	return {"direction":(away.normalized()*2-delta.normalized()).normalized(),"expires_at":nearest.expires_at}

static func summary(cell) -> String:
	return "Current intention: "+cell.state.capitalize()+".\n"+DESCRIPTION
