extends RefCounted
## Two checksummed generations. Restores simulation time; never charges wall downtime.
const SCHEMA := 1
const MAX_BYTES := 268435456
var directory := ""
var sequence := 0
var last_error := ""
var last_saved_tick := -1
var latency_ms := 0.0

func _digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty(): hash.update(bytes)
	return hash.finish().hex_encode()

func save(payload: Dictionary) -> bool:
	var start := Time.get_ticks_usec()
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return _fail("Cannot create world storage")
	var bytes := var_to_bytes({"schema":SCHEMA,"sequence":sequence+1,"payload":payload})
	if bytes.size() > MAX_BYTES: return _fail("World checkpoint exceeds supported size")
	var slot := "world-%d.pworld" % ((sequence+1)%2)
	var temporary := directory.path_join(slot+".tmp")
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return _fail("Cannot write checkpoint")
	file.store_line(_digest(bytes)); file.store_buffer(bytes); file.flush(); file.close()
	var output: Array=[]
	if OS.execute("python3",[ProjectSettings.globalize_path("res://tools/durable_world.py"),temporary,directory.path_join(slot)],output,true)!=0: return _fail("Cannot synchronize/publish checkpoint")
	sequence += 1
	last_saved_tick = payload.get("tick",-1)
	latency_ms = (Time.get_ticks_usec()-start)/1000.0
	last_error = ""
	return true

func load_latest() -> Dictionary:
	var best: Dictionary = {}
	var found := FileAccess.file_exists(directory.path_join("world-0.pworld.tmp")) or FileAccess.file_exists(directory.path_join("world-1.pworld.tmp"))
	for slot in ["world-0.pworld","world-1.pworld"]:
		var path := directory.path_join(slot)
		if not FileAccess.file_exists(path): continue
		found = true
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES: continue
		var digest := file.get_line()
		var bytes := file.get_buffer(file.get_length()-file.get_position())
		if _digest(bytes) != digest: continue
		var record = bytes_to_var(bytes) # allow_objects=false
		if not record is Dictionary or record.get("schema",0) != SCHEMA: continue
		if not record.get("payload") is Dictionary: continue
		if record.get("sequence",0) > best.get("sequence",0): best = record
	if best.is_empty():
		last_error = "No valid checkpoint; refusing to reseed an existing world" if found else ""
		return {}
	sequence = best.sequence; last_saved_tick = best.payload.get("tick",-1); last_error = ""
	return best.payload

func archive_pond(payload: Dictionary) -> String:
	# A complete independent, checksummed pair survives rotating active saves.
	var identity: String=payload.get("world_id","")
	var pattern:=RegEx.new();pattern.compile("^[a-f0-9]{32}$")
	if pattern.search(identity)==null:_fail("Invalid pond archive identity");return ""
	var relative: String="archives/pond-%s--epoch-%d--tick-%d" % [identity,int(payload.get("epoch",0)),int(payload.get("tick",0))]
	var archive=get_script().new();archive.directory=directory.path_join(relative)
	var prior: Dictionary=archive.load_latest()
	if not archive.last_error.is_empty():_fail(archive.last_error);return ""
	if not prior.is_empty():
		if var_to_bytes(prior)!=var_to_bytes(payload):_fail("Pond archive already contains different state");return ""
	if not archive.save(payload) or not archive.save(payload):_fail(archive.last_error);return ""
	return relative

func retain_latest(version: int=1) -> bool:
	# Preserve the validated pre-migration generation outside the rotating pair.
	var target:=directory.path_join("before-particle-resolution-v%d.pworld" % version)
	if FileAccess.file_exists(target):
		var retained:=FileAccess.open(target,FileAccess.READ)
		if retained==null or retained.get_length()>MAX_BYTES: return _fail("Retained checkpoint is unreadable")
		var digest:=retained.get_line()
		var contents:=retained.get_buffer(retained.get_length()-retained.get_position());retained.close()
		if _digest(contents)!=digest: return _fail("Retained checkpoint checksum failed")
		return true
	var source:=FileAccess.open(directory.path_join("world-%d.pworld" % (sequence%2)),FileAccess.READ)
	if source==null: return _fail("Cannot retain checkpoint before resolution migration")
	var bytes:=source.get_buffer(source.get_length());source.close()
	var temporary:=target+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return _fail("Cannot write retained checkpoint")
	file.store_buffer(bytes);file.flush();file.close()
	var output: Array=[]
	if OS.execute("python3",[ProjectSettings.globalize_path("res://tools/durable_world.py"),temporary,target],output,true)!=0: return _fail("Cannot synchronize retained checkpoint")
	return true

func _fail(reason: String) -> bool:
	last_error = reason
	push_error(reason)
	return false
