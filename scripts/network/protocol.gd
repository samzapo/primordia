extends RefCounted
const VERSION := 1
const MAX_FRAME := 8388608
static func pack(value: Dictionary) -> PackedByteArray:
	var raw:=var_to_bytes(value)
	return raw.compress(FileAccess.COMPRESSION_GZIP) if raw.size()<=MAX_FRAME else PackedByteArray()
static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_FRAME: return {}
	var raw := bytes.decompress_dynamic(MAX_FRAME,FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():return {}
	var value = bytes_to_var(raw)
	return value if value is Dictionary and value.get("protocol",0) == VERSION else {}
