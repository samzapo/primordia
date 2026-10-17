extends RefCounted
## Allowed live editor commands. No stock/pose setters or arbitrary field writes.
static func execute(sim, action: String, args: Dictionary):
	for key in ["id","to","value","angle"]:
		if args.has(key) and not (args[key] is int or args[key] is float): return false
		if args.has(key) and not is_finite(float(args[key])): return false
	for key in ["kind","gene","module","species","scope"]:
		if args.has(key) and not args[key] is String: return false
	for key in ["dormant","active"]:
		if args.has(key) and not args[key] is bool: return false
	var cell = sim.player
	if cell.dead: return false
	var identity: int = int(args.get("id",-1))
	var value: float = float(args.get("value",0))
	if not is_finite(value): return false
	match action:
		"investment": return sim.Investment.set_strategy(sim,str(args.get("scope","")),str(args.get("kind","")))
		"install": return sim.install(str(args.get("kind","")),float(args.get("angle",0)))
		"remove":
			var organ: Dictionary = cell.organ_by_id(identity)
			return sim.remove(cell.organs.find(organ)) if not organ.is_empty() else false
		"move": return cell.move_organ(identity,float(args.get("angle",0)))
		"mutate": return sim.mutate_organ(identity,str(args.get("gene","")))
		"choose_mutation": return sim.evolution.accept_division_offer(str(args.get("gene","")))
		"restore": return sim.restore(identity)
		"steering","exploration","cycle": return false # Retired tuning; the shared behavior tree decides.
		"output": return false # Retired command; never alter a saved organ.
		"reserve":
			if value not in [-10.0,10.0]: return false
			cell.reserve(value,sim.offspring_quote().material); return true
		"divide": return sim.divide_lineage(bool(args.get("dormant",false)),false)
		"follow": return sim.follow_family(identity)
		"module_add","module_remove","module_config","route_add","route_remove","configuration": return false
		"tension","link_remove","link_add": return false # Procedural cell anatomy is not player-editable.

	return false

static func _anchor(value, cell) -> Dictionary:
	if not value is Dictionary: return {}
	var anchor: Dictionary = value.duplicate()
	if anchor.get("kind","") == "point":
		if anchor.get("p") is Array:
			if anchor.p.size()!=2 or not anchor.p[0] is float and not anchor.p[0] is int or not anchor.p[1] is float and not anchor.p[1] is int: return {}
			anchor.p = Vector2(anchor.p[0],anchor.p[1])
		if not anchor.get("p") is Vector2 or not anchor.p.is_finite() or anchor.p.length()>cell.extent()*1.5: return {}
	return anchor if cell.membrane.skeleton.valid(anchor) else {}
