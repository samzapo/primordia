extends RefCounted
## Optional local history, not a world save or a source of material/stat bonuses.
const Genes = preload("res://scripts/mutations.gd")
var persist := false
var path := "user://lineage_history.json"
var discovered: Array[String] = []
var expeditions: Array = []
var next_id := 0
var current := -1
var observed := ""
var last_error := ""
var retry_at := 0

func load_history() -> void:
	if not persist or not FileAccess.file_exists(path): return
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 4194304: return
	var value = JSON.parse_string(file.get_as_text())
	if not value is Dictionary or value.get("version",0) != 1: return
	var genes = value.get("discovered",[])
	if genes is Array:
		for gene in genes:
			if gene is String and Genes.DATA.has(gene) and gene not in discovered: discovered.append(gene)
	var entries = value.get("expeditions",[])
	if entries is Array:
		for item in entries.slice(-64):
			if not item is Dictionary or not item.get("family") is Array: continue
			var entry := {"id":int(number(item,"id")),"status":words(item,"status"),"seconds":number(item,"seconds"),"seed":int(number(item,"seed")),"crises":[],"family":[]}
			var crises = item.get("crises",[])
			if crises is Array:
				for done in crises.slice(0,3): entry.crises.append(done == true)
			for member in item.family.slice(-128):
				if not member is Dictionary: continue
				var record := {}
				for key in ["id","parent","generation"]: record[key] = int(number(member,key,-1 if key == "parent" else 0))
				for key in ["born","ended","food","fixed"]: record[key] = number(member,key)
				for key in ["state","cause"]: record[key] = words(member,key)
				entry.family.append(record)
			expeditions.append(entry)
			next_id = maxi(next_id,entry.id+1)

static func number(item: Dictionary, key: String, fallback: float = 0.0) -> float:
	var value = item.get(key,fallback)
	return clampf(float(value),-1,1e12) if (value is float or value is int) and is_finite(float(value)) else fallback

static func words(item: Dictionary, key: String) -> String:
	var value = item.get(key,"")
	return value.substr(0,240) if value is String else ""

func begin() -> void:
	current = next_id
	next_id += 1
	observed = ""

func sync(sim) -> void:
	var key := "%d:%d:%d:%s" % [sim.lineage.serial,sim.evolution.learned.size(),sim.evolution.tide,sim.evolution.status]
	if key == observed or Time.get_ticks_msec() < retry_at: return
	for gene in sim.evolution.learned:
		if gene not in discovered: discovered.append(gene)
	var entry := {"id":current,"seed":sim.seed_value,"status":sim.evolution.status,"seconds":sim.time,
		"crises":sim.evolution.completed.duplicate(),"family":sim.lineage.records.duplicate(true)}
	var replaced := false
	for i in expeditions.size():
		if expeditions[i].id == current: expeditions[i] = entry; replaced = true; break
	if not replaced: expeditions.append(entry)
	if expeditions.size() > 64: expeditions.pop_front()
	if save_history(): observed = key
	else: retry_at = Time.get_ticks_msec()+5000

func recall(run, gene: String) -> bool:
	if run.terminal() or run.chosen or gene not in discovered or gene in run.learned: return false
	if gene not in run.offers: run.offers.append(gene)
	return run.choose(gene)

func save_history() -> bool:
	if not persist: return true
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		last_error = "Could not write lineage history."
		return false
	file.store_string(JSON.stringify({"version":1,"discovered":discovered,"expeditions":expeditions}))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Could not finish writing lineage history."
		return false
	var error := DirAccess.rename_absolute(path+".tmp",path)
	last_error = "" if error == OK else "Could not replace lineage history."
	return error == OK
