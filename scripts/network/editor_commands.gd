extends RefCounted
## Allowed live editor commands. No stock/pose setters or arbitrary field writes.
static func execute(sim, action: String, args: Dictionary):
	for key in ["id","to","value","angle"]:
		if args.has(key) and not (args[key] is int or args[key] is float): return false
		if args.has(key) and not is_finite(float(args[key])): return false
	for key in ["kind","gene","module","species","scope","mode"]:
		if args.has(key) and not args[key] is String: return false
	for key in ["dormant","active","automatic"]:
		if args.has(key) and not args[key] is bool: return false
	var cell = sim.player
	if cell.dead: return false
	var identity: int = int(args.get("id",-1))
	var value: float = float(args.get("value",0))
	if not is_finite(value): return false
	match action:
		"merge": return sim.FamilyMerging.request(sim,identity)
		"division_request":return false
		"reproduce":return sim.divide_lineage(false,false,str(args.get("mode","mitosis")))
		"division_policy":
			if not args.get("automatic") is bool or args.get("scope","cell") not in ["cell","lineage"] or args.get("mode","mitosis") not in ["mitosis","budding"]:return false
			for member in sim.cells:
				if member==cell or (args.get("scope","cell")=="lineage" and member.lineage_id()==cell.lineage_id()):
					if args.get("mode","mitosis")=="budding":member.automatic_budding=args.automatic
					else:member.automatic_division=args.automatic
			return true
		"investment_template":return sim.Investment.save_template(sim,str(args.get("scope","lineage")),identity)
		"investment": return sim.Investment.set_strategy(sim,str(args.get("scope","")),str(args.get("kind","")))
		"install": return sim.install(str(args.get("kind","")),float(args.get("angle",0)))
		"remove":
			var organ: Dictionary = cell.organ_by_id(identity)
			return sim.remove(cell.organs.find(organ)) if not organ.is_empty() else false
		"move": return false # Installed organs cannot be relocated.
		"mutate": return sim.mutate_organ(identity,str(args.get("gene","")))
		"choose_mutation": return sim.evolution.accept_division_offer(str(args.get("gene","")))
		"restore": return sim.restore(identity)
		"steering","exploration","cycle": return false # Retired tuning; the shared behavior tree decides.
		"output": return false # Retired command; never alter a saved organ.
		"reserve": return false # Growth is automatic; old manual banking controls are retired.
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
