extends RefCounted
## Allowed live editor commands. No stock/pose setters or arbitrary field writes.
static func execute(sim, action: String, args: Dictionary):
	for key in ["id","to","value","angle"]:
		if args.has(key) and not (args[key] is int or args[key] is float): return false
		if args.has(key) and not is_finite(float(args[key])): return false
	for key in ["kind","gene","module","species"]:
		if args.has(key) and not args[key] is String: return false
	for key in ["dormant","active"]:
		if args.has(key) and not args[key] is bool: return false
	var cell = sim.player
	if cell.dead: return false
	var identity: int = int(args.get("id",-1))
	var value: float = float(args.get("value",0))
	if not is_finite(value): return false
	match action:
		"install": return sim.install(str(args.get("kind","")),float(args.get("angle",0)))
		"remove":
			var organ: Dictionary = cell.organ_by_id(identity)
			return sim.remove(cell.organs.find(organ)) if not organ.is_empty() else false
		"move": return cell.move_organ(identity,float(args.get("angle",0)))
		"mutate": return sim.mutate_organ(identity,str(args.get("gene","")))
		"restore": return cell.restore_organ(identity)
		"steering": return cell.set_steering_strength(identity,value)
		"exploration": return cell.set_exploration(value)
		"cycle": return cell.set_response_cycle(value)
		"reserve":
			if value not in [-10.0,10.0]: return false
			cell.reserve(value,sim.offspring_quote().material); return true
		"divide": return sim.divide_lineage(bool(args.get("dormant",false)),false)
		"follow": return sim.follow_family(identity)
		"module_add":
			if sim.evolution.points<1: return -1
			var node: int = cell.chemistry.add_module(str(args.get("module","")),cell)
			if node>=0: sim.evolution.spend(1,"Add chemistry module")
			return node
		"module_remove": return cell.chemistry.remove_module(identity,cell)
		"module_config": return cell.chemistry.configure(identity,value,bool(args.get("active",true)))
		"route_add": return cell.chemistry.connect_route(identity,int(args.get("to",-1)),str(args.get("species","")))
		"route_remove":
			cell.chemistry.disconnect_route(identity,int(args.get("to",-1)),str(args.get("species",""))); return true
		"configuration":
			if not args.get("configuration") is Dictionary: return "Invalid configuration"
			return cell.chemistry.load_configuration(args.configuration)
		"tension":
			if value<0 or value>1: return false
			cell.membrane.skeleton.set_tension(identity,value); cell.membrane.invalidate(); return true
		"link_remove":
			cell.membrane.skeleton.remove_group(identity); cell.membrane.invalidate(); return true
		"link_add":
			if cell.membrane.skeleton.links.size()>=128: return -1
			var start := _anchor(args.get("start",{}),cell)
			var end := _anchor(args.get("end",{}),cell)
			if start.is_empty() or end.is_empty(): return -1
			return cell.membrane.skeleton.connect_points(start,end,value,cell.membrane,cell.radius)
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
