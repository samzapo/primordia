extends SceneTree
## Deterministic build input for single-threaded web clients. No generated bank
## belongs in Git; the ordinary web build creates and content-addresses it.
func _initialize() -> void:
	var output:="";var manifest:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):output=arg.trim_prefix("--output-dir=")
		elif arg.begins_with("--manifest="):manifest=arg.trim_prefix("--manifest=")
	if output=="" or manifest=="":quit(1);return
	var synth=preload("res://scripts/music_synth.gd")
	var bank: Array=synth.make_bank();var bytes:=PackedByteArray();bytes.resize(84)
	bytes.encode_u32(0,0x50534d50);bytes.encode_u32(4,1);bytes.encode_u32(8,synth.RATE);bytes.encode_u32(12,bank.size())
	for i in bank.size():bytes.encode_u32(16+i*4,bank[i].size());bytes.append_array(bank[i].to_byte_array())
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	var digest:=hash.finish().hex_encode();var name:="music-bank-"+digest.substr(0,24)+".bin"
	var file:=FileAccess.open(output.path_join(name),FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_buffer(bytes);file.close()
	file=FileAccess.open(manifest,FileAccess.WRITE)
	if file==null:quit(1);return
	var description:=JSON.stringify({"version":1,"file":name,"sha256":digest,"bytes":bytes.size(),"rate":synth.RATE,"base_notes":synth.BASE_NOTE})
	file.store_string(description);file.close()
	file=FileAccess.open(output.path_join("music-bank.json"),FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(description);file.close()
	print("MUSIC_BANK_BUILD "+name+" "+str(bytes.size())+" bytes");quit()
