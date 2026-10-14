extends SceneTree
## Read an immutable retained checkpoint; never starts, steps or saves a world.
const Resolution=preload("res://scripts/network/particle_resolution.gd")
const Chemistry=preload("res://scripts/cell_chemistry.gd")
func _initialize() -> void:
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint="):path=arg.trim_prefix("--checkpoint=")
	if path=="":quit(1);return
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>268435456:quit(1);return
	var digest:=file.get_line();var bytes:=file.get_buffer(file.get_length()-file.get_position());file.close()
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	if hash.finish().hex_encode()!=digest:quit(1);return
	var record=bytes_to_var(bytes)
	if not record is Dictionary:quit(1);return
	var graph: Dictionary=record.payload.graph;var objects: Array=graph.objects
	var world: Dictionary=fields(graph.root.world,objects);var reports: Array=[]
	var before_total:=0;var after_total:=0;var conserved:=true
	for reference in world.get("cells",{}).get("$array",[]):
		var body:=fields(reference,objects)
		if body.get("dead",true):continue
		var source:=fields(body.chemistry,objects);var chem=Chemistry.new()
		chem.nodes=source.nodes["$array"].duplicate(true);chem.particles=source.particles["$array"].duplicate(true)
		var before:=inventory(chem.particles);var count: int=chem.particles.size()
		var reduced: Dictionary=Resolution._internal_tenth(chem.particles,float(body.radius))
		chem.particles=reduced.particles
		chem._coalesce_retired_catalysts();chem.particles=chem.particles.filter(func(packet):return packet.alive)
		var after:=inventory(chem.particles);var same:=true
		for kind in before:
			if not after.has(kind) or absf(before[kind].amount-after[kind].amount)>.00001 or absf(before[kind].fuel-after[kind].fuel)>.00001:same=false
		conserved=conserved and same;before_total+=count;after_total+=chem.particles.size()
		reports.append({"before":count,"after":chem.particles.size(),"conserved":same})
	print("DENSITY_PREVIEW "+JSON.stringify({"checkpoint_tick":record.payload.tick,"living_cells":reports.size(),"internal_before":before_total,"internal_after":after_total,"conserved":conserved,"cells":reports,"mode":"read-only retained v2 input; no world step or save"}))
	quit(0 if conserved else 1)
static func fields(reference,objects: Array) -> Dictionary:
	if not reference is Dictionary:return {}
	var index: int=reference.get("$ref",-1)
	return objects[index].get("fields",{}) if index>=0 and index<objects.size() else {}
static func inventory(packets: Array) -> Dictionary:
	var totals: Dictionary={}
	for packet in packets:
		if packet.alive:
			if not totals.has(packet.species):totals[packet.species]={"amount":0.0,"fuel":0.0}
			totals[packet.species].amount+=packet.amount;totals[packet.species].fuel+=packet.fuel
	return totals
