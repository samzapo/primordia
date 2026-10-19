extends RefCounted
## Authored, versioned chemistry. Runtime/compiler products are never committed.
static var _data: Dictionary = {}
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/chemistry.json"))
		assert(parsed is Dictionary and parsed.get("version",0) == 1,"Invalid chemistry catalog")
		_data = parsed
	return _data
static func module(identity: String) -> Dictionary:
	for item in data().modules:
		if item.id == identity: return item
	return {}
static func radius(kind: int) -> float:
	return float(data().external_species[kind].radius)
static func decay(kind: int) -> float:
	return float(data().external_species[kind].decay)
static func material(kind: int) -> float:
	var key: String = data().external_species[kind].key
	return float(data().species.get(key,{}).get("material",0 if kind in [1,3] else 1))

# Nutrient capacity <= amount is usable fuel fraction. Above amount it carries
# fully fueled food plus a bounded, amount-weighted ATP-allocation bonus.
static func merge_limit(kind: int) -> float:
	return float(data().ecology.nutrient_merge_limit if kind==0 else data().ecology.merge_limit)
static func nutrient_capacity(a: float,ac: float,b: float,bc: float,acid: float=0.0) -> float:
	var total := a+b
	var fuel := minf(a,maxf(0,ac))+minf(b,maxf(0,bc))
	if fuel<total:return fuel # Spent food cannot regain fuel by joining.
	return total+minf(total*float(data().ecology.nutrient_bonus_limit),maxf(0,ac-a)+maxf(0,bc-b)+minf(a,b)*float(data().ecology.nutrient_binding_bonus)*(1+maxf(0,1-absf(acid-.25)/.25)))

static func glsl(source: String) -> String:
	var radii: PackedStringArray = []
	var rates: PackedStringArray = []
	var materials: PackedStringArray = []
	for item in data().external_species:
		radii.append("%.6f" % item.radius)
		rates.append("%.6f" % item.decay)
		materials.append("%.6f" % material(item.id))
	var binding := "const float nutrient_merge_limit=%.6f,nutrient_binding_bonus=%.6f,nutrient_bonus_limit=%.6f;\n" % [data().ecology.nutrient_merge_limit,data().ecology.nutrient_binding_bonus,data().ecology.nutrient_bonus_limit]
	binding += "float nutrient_capacity(float a,float ac,float b,float bc,float acid){float total=a+b;float fuel=min(a,max(0.,ac))+min(b,max(0.,bc));if(fuel<total)return fuel;return total+min(total*nutrient_bonus_limit,max(0.,ac-a)+max(0.,bc-b)+min(a,b)*nutrient_binding_bonus*(1.+max(0.,1.-abs(acid-.25)/.25)));}"
	return source.replace("/*CATALOG_NUTRIENT_BINDING*/",binding).replace("/*CATALOG_MERGE_LIMIT*/","%.6f" % float(data().ecology.merge_limit)).replace("/*CATALOG_RADII*/",("const float radii[%d]=float[%d]("+",".join(radii)+");") % [radii.size(),radii.size()]).replace("/*CATALOG_DECAY*/",("const float rates[%d]=float[%d]("+",".join(rates)+");") % [rates.size(),rates.size()]).replace("/*CATALOG_MATERIAL*/",("const float materials[%d]=float[%d]("+",".join(materials)+");") % [materials.size(),materials.size()])
static func validate() -> String:
	var definitions: Dictionary = data().species
	for item in data().modules:
		if item.has("action"): continue
		var mass := 0.0
		var potential := float(item.atp)
		for key in item.outputs:
			if not definitions.has(key): return "Unknown product: "+key
			mass += float(item.outputs[key])*float(definitions[key].material)
			potential += float(item.outputs[key])*float(definitions[key].potential)
		for key in item.inputs:
			if not definitions.has(key): return "Unknown input: "+key
			mass -= float(item.inputs[key])*float(definitions[key].material)
			potential -= float(item.inputs[key])*float(definitions[key].potential)
		if absf(mass) > 0.000001: return "Unbalanced material: "+item.id
		if potential > 0.000001: return "Unfunded energy: "+item.id
	return ""
