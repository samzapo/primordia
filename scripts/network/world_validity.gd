extends RefCounted
## Physical/resource state only; intentional unbounded sensing deadlines are valid.
static func error(world) -> String:
 for cell in world.cells:
  for name in ["energy","biomass","body","brood_energy","brood_mass","health","radius","mass","inertia","angle","angular_velocity"]:
   if not is_finite(float(cell.get(name))):return "Nonfinite cell "+str(cell.id)+" "+name
  for name in ["position","previous_position","velocity","shape_acceleration"]:
   if not cell.get(name).is_finite():return "Nonfinite cell "+str(cell.id)+" "+name
  for organ in cell.organs:
   for name in ["hp","max_hp","material","max_material","scale","a"]:
    if not is_finite(float(organ.get(name,0))):return "Nonfinite organ "+str(cell.id)+"/"+str(organ.id)+" "+name
  for point in cell.membrane.points:
   if not point.is_finite():return "Nonfinite cell "+str(cell.id)+" membrane"
  for point in cell.membrane.previous:
   if not point.is_finite():return "Nonfinite cell "+str(cell.id)+" membrane history"
  for value in cell.chemistry.totals.values():
   if not is_finite(float(value)):return "Nonfinite cell "+str(cell.id)+" chemistry"
 for velocity in world.fluid.velocity:
  if not velocity.is_finite():return "Nonfinite water velocity"
 for velocity in world.fluid.tide:
  if not velocity.is_finite():return "Nonfinite water target"
 for value in world.acidity.values:
  if not is_finite(value):return "Nonfinite water acidity"
 return ""
