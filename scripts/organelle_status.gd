extends RefCounted
## Read-only presentation of real prerequisites and timers, never a work gate.
static func state(sim,cell,organ: Dictionary) -> Dictionary:
 var result: Dictionary={"label":"Ready","depleted":false,"progress":-1.0}
 var kind: String=organ.kind
 if organ.hp<=0:result.label="Damaged";return result
 if kind=="sanctuary":result.label="Protected · growth investment replaces division";return result
 if kind=="photosynthesis":
  if cell.carbon<=.0000001:result.label="Waiting for carbon";return result
  if sim.light_at(cell.organ_position(organ))<=.001:result.label="Waiting for light";return result
  result.label="Collecting light";result.progress=clampf(float(organ.get("photo_elapsed",0))/.25,0,1)
  return result
 if kind=="mitochondrion":
  result.label="Waiting for food" if cell.substrate<=.0000001 else "Waiting for oxygen" if cell.oxygen<=.0000001 else "Making ATP from food and oxygen"
  return result
 if kind in ["toxin","poreforming","counterattack"]:
  var burst: float=organ.scale*organ.scale*cell.Genes.factor(organ,"burst")
  if cell.energy<maxf(12,2*burst*cell.Genes.inefficiency(organ)):
   result.label="Out of ATP · need energy";result.depleted=true;result.progress=clampf(cell.energy/maxf(12,2*burst*cell.Genes.inefficiency(organ)),0,1);return result
  if cell.biomass<.18*burst:result.label="Waiting for biomass";return result
  var clock: float=float(organ.get("burst_clock",0))
  if clock>0:
   result.label="Recharging · %.1fs" % clock
   result.progress=clampf(1-clock/(.75*cell.Genes.factor(organ,"cooldown")),0,1)
   return result
  if kind=="counterattack":
   var cue: Dictionary=organ.get("counter_report",{})
   if cue.is_empty() or cue.expires_at<=sim.time:result.label="Waiting for an armed cell’s chemical signal";return result
  elif cell.target_id<0 or cell.target_memory<=0:result.label="Waiting for a chemical target signal";return result
  result.progress=1
 elif kind in ["acidifying","neutralizing","regenerative"]:
  if kind=="acidifying" and cell.protected_cell():result.label="Acid paused by Sanctuary";return result
  if cell.energy<12:
   result.label="Low ATP · secretion paused";result.depleted=kind!="regenerative" or cell.energy<=.000001;result.progress=clampf(cell.energy/12,0,1);return result
  if cell.biomass<.06:result.label="Waiting for biomass";return result
 elif kind in ["propulsion","cilia"] and cell.energy<=.000001:
  result.label="Out of ATP · movement paused";result.depleted=true;return result
 if cell.age-float(organ.get("emission_age",-100))<.28:result.label="Producing"
 return result
