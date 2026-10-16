extends RefCounted
## Data-only graph format. Script paths are a fixed allowlist; no executable Objects.
const TYPES := {
	"simulation": preload("res://scripts/simulation.gd"),
	"cell": preload("res://scripts/cell.gd"),
	"chemistry": preload("res://scripts/cell_chemistry.gd"),
	"membrane": preload("res://scripts/membrane.gd"),
	"skeleton": preload("res://scripts/cytoskeleton.gd"),
	"lineage": preload("res://scripts/lineage.gd"),
	"evolution": preload("res://scripts/evolution.gd"),
	"medium": preload("res://scripts/medium.gd"),
	"acidity": preload("res://scripts/acidity.gd"),
	"habitat": preload("res://scripts/habitat.gd"),
	"offscreen": preload("res://scripts/offscreen_ecology.gd"),
	"budget": preload("res://scripts/energy_budget.gd"),
}
const TRANSIENT := ["kernels","native","grid","reaction_grid","cell_index","gpu_transport","resident","experimental_fluid","owner","_owner","build_original","build_state","bins","profile_usec","profile_counts","foreground_particle_ids","last_spawn","accelerator","render_origins","command_sink","interoceptive_cells","resource_effects_enabled","batching","plant_drag","plant_geometry","plant_revision","plant_enabled"]
const DERIVED_CELL := ["raw_fuel","substrate","waste","oxygen","carbon"]
var objects: Array = []
var identities: Dictionary = {}
var overrides: Dictionary = {}
var compact_cytoplasm := false
var cytoplasm_version:=2
var migration_audit: Array=[]

func capture(value, field_overrides: Dictionary = {}, compact: bool = false,columns_version: int=2) -> Dictionary:
	objects.clear(); identities.clear(); overrides = field_overrides;compact_cytoplasm=compact;cytoplasm_version=columns_version
	var root = _encode(value)
	var index := 0
	while index < objects.size():
		var source = objects[index].source
		var kind: String = objects[index].kind
		var fields: Dictionary = {}
		for property in source.get_property_list():
			if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
			var key: String = property.name
			if key in TRANSIENT or (kind == "cell" and key in DERIVED_CELL): continue
			var field = source.get(key)

			if overrides.has(source.get_instance_id()) and overrides[source.get_instance_id()].has(key):
				field = overrides[source.get_instance_id()][key]
			elif kind=="chemistry" and key=="particles":field=source.particle_snapshots()
			var columns=preload("res://scripts/network/cytoplasm_codec.gd").encode(field,cytoplasm_version) if compact_cytoplasm and kind=="chemistry" and key=="particles" else null
			fields[key] = columns if columns!=null else _encode(field)
		objects[index].fields = fields
		index += 1
	var records: Array = []
	for object in objects: records.append({"kind":object.kind,"fields":object.fields})
	return {"format":1,"root":root,"objects":records}

func _encode(value):
	if value is RandomNumberGenerator:
		return {"$rng":PackedInt64Array([value.seed,value.state])}
	if value is Object:
		if value is WeakRef or value.get_script() == null: return null
		var identity: int = value.get_instance_id()
		if identities.has(identity): return {"$ref":identities[identity]}
		var kind := ""
		for name in TYPES:
			if value.get_script() == TYPES[name]: kind = name; break
		if kind == "": push_error("Unsupported checkpoint object"); return null
		identities[identity] = objects.size()
		objects.append({"source":value,"kind":kind,"fields":{}})
		return {"$ref":identities[identity]}
	if value is Array:
		var items: Array = []
		for item in value: items.append(_encode(item))
		return {"$array":items,"builtin":value.get_typed_builtin()}
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _encode(value[key])
		return result
	return value

func restore(document: Dictionary):
	if document.get("format",0) != 1 or not document.get("objects",[]) is Array: return null
	objects.clear();migration_audit.clear()
	for record in document.objects:
		if not record is Dictionary or not TYPES.has(record.get("kind","")): return null
		var object
		if record.kind == "simulation": object = TYPES.simulation.new(0,0,false)
		else: object = TYPES[record.kind].new()
		objects.append({"source":object,"kind":record.kind})
	for i in objects.size():
		var object = objects[i].source
		for key in document.objects[i].fields:
			if key in TRANSIENT: continue
			object.set(key,_decode(document.objects[i].fields[key]))
	for i in objects.size():
		var record: Dictionary=objects[i]
		if record.kind == "cell":
			record.source.chemistry.owner = weakref(record.source)
			var ref: Dictionary=document.objects[i].fields.get("chemistry",{})
			var old: bool=ref.has("$ref") and not document.objects[int(ref["$ref"])].fields.has("model_version")
			if old:
				var audit: Dictionary=preload("res://scripts/network/vacuole_migration.gd").apply(record.source)
				audit["cell_id"]=record.source.id;migration_audit.append(audit)
			record.source.chemistry.bins.clear()
			for packet in record.source.chemistry.particles:
				if not packet.has("age"):packet.age=0.0
				if packet.alive: record.source.chemistry._index(packet)
		elif record.kind == "membrane":
			if record.source.kernels==null:
				record.source.native_constraints=false;record.source.native_outline=false
			record.source.invalidate()
		elif record.kind == "habitat": record.source.rebuild()
	var root = _decode(document.root)
	objects.clear()
	return root

func _decode(value):
	if value is Dictionary:
		if value.has("$cytoplasm"):return preload("res://scripts/network/cytoplasm_codec.gd").decode(value)
		if value.has("$ref"):
			var index: int = value["$ref"]
			return objects[index].source if index >= 0 and index < objects.size() else null
		if value.has("$rng"):
			var random := RandomNumberGenerator.new()
			random.seed = value["$rng"][0]; random.state = value["$rng"][1]
			return random
		if value.has("$array"):
			var result: Array = []
			for item in value["$array"]: result.append(_decode(item))
			var builtin: int = value.get("builtin",TYPE_NIL)
			return Array(result,builtin,&"",null) if builtin != TYPE_NIL else result
		var result: Dictionary = {}
		for key in value: result[key] = _decode(value[key])
		return result
	return value
