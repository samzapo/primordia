extends RefCounted
const VERSION := 1
const MAX_FRAME := 8388608
static func pack(value: Dictionary) -> PackedByteArray:
	return var_to_bytes(value).compress(FileAccess.COMPRESSION_GZIP)
static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_FRAME: return {}
	var raw := bytes.decompress_dynamic(MAX_FRAME,FileAccess.COMPRESSION_GZIP)
	var value = bytes_to_var(raw)
	return value if value is Dictionary and value.get("protocol",0) == VERSION else {}
