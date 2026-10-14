extends SceneTree
## Read-only bounded selection report. Never restores objects or starts an authority.
func _initialize() -> void:
	var directory:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--state-dir="):directory=arg.trim_prefix("--state-dir=")
	if directory=="":quit(1);return
	var store=preload("res://scripts/network/world_store.gd").new();store.directory=directory
	var saved: Dictionary=store.load_latest()
	if saved.is_empty():print("WORLD_SELECTION "+JSON.stringify({"status":"unavailable","reason":store.last_error}));quit(1);return
	var summary:=selection(saved)
	print("WORLD_SELECTION "+JSON.stringify(summary))
	quit(0)

static func selection(saved: Dictionary) -> Dictionary:
	var graph: Dictionary=saved.get("graph",{});var root: Dictionary=graph.get("root",{});var objects: Array=graph.get("objects",[])
	var world: Dictionary=fields(root.get("world"),objects)
	var cells: Array=world.get("cells",{}).get("$array",[])
	var records: Array=[]
	for account in root.get("accounts",{}).values().slice(0,8):
		var selected: int=account.get("selected",-1)
		var body: Dictionary={};var location:="missing"
		for reference in cells:
			var cell:=fields(reference,objects)
			if cell.get("id",-2)==selected:body=cell;location="world";break
		var ledger:=fields(account.get("lineage"),objects)
		if body.is_empty():
			for reference in ledger.get("dormant",{}).get("$array",[]):
				var cell:=fields(reference,objects)
				if cell.get("id",-2)==selected:body=cell;location="dormant";break
		if body.is_empty():
			var current:=fields(account.get("current"),objects)
			if current.get("id",-2)==selected:body=current;location="retained"
		var at: Vector2=body.get("position",Vector2.ZERO)
		records.append({"selected_location":location,"selected_dead":body.get("dead",true),"retained_cytoplasm_packets":fields(body.get("chemistry"),objects).get("particles",{}).get("$array",[]).size(),"position":[at.x,at.y],"radius":body.get("radius",0),"dormant_count":ledger.get("dormant",{}).get("$array",[]).size(),"living_family_count":cells.filter(func(reference):return not fields(reference,objects).get("dead",true) and lineage(fields(reference,objects))==account.get("root",-1)).size()})
	var living_counts: Array=cells.filter(func(reference):return not fields(reference,objects).get("dead",true)).map(func(reference):return fields(fields(reference,objects).get("chemistry"),objects).get("particles",{}).get("$array",[]).size())
	var details: Array=[]
	for reference in cells.slice(0,8):
		var body:=fields(reference,objects)
		if not body.get("dead",true):details.append(chemistry_summary(body,objects))
	return {"living_cytoplasm_packets":living_counts.reduce(func(total,value):return total+value,0),"largest_living_cytoplasm_packets":living_counts.max() if not living_counts.is_empty() else 0,"status":"ok","world_id":saved.get("world_id",""),"epoch":saved.get("epoch",0),"tick":saved.get("tick",0),"accounts":records,"living_chemistry":details}

static func fields(reference,objects: Array) -> Dictionary:
	if not reference is Dictionary:return {}
	var index: int=reference.get("$ref",-1)
	return objects[index].get("fields",{}) if index>=0 and index<objects.size() else {}

static func lineage(cell: Dictionary) -> int:
	var root: int=cell.get("lineage",-1)
	return root if root>=0 else int(cell.get("id",-2))

static func chemistry_summary(body: Dictionary,objects: Array) -> Dictionary:
	var packets: Array=fields(body.get("chemistry"),objects).get("particles",{}).get("$array",[])
	var species: Dictionary={};var groups: Dictionary={};var extra: Dictionary={}
	for packet in packets:
		var kind: String=packet.get("species","")
		species[kind]=int(species.get(kind,0))+1
		groups[var_to_bytes([kind,packet.get("source",-1),packet.get("compartment",-1)]).hex_encode()]=true
		for key in packet:
			if key not in ["id","species","amount","fuel","p","previous","v","angle","source","compartment","alive"]:extra[key]=int(extra.get(key,0))+1
	return {"radius":body.get("radius",0),"packets":packets.size(),"species":species,"compatible_groups":groups.size(),"extra_facts":extra}
