extends RefCounted
## Snapshot-only lossless columns. Checkpoints retain the full dictionary graph.
const STRIDE := 80
const KEYS := ["id","species","amount","fuel","p","previous","v","angle","source","compartment","alive"]
static func encode(particles: Array):
	var species:=PackedStringArray();var indices: Dictionary={}
	var bytes:=PackedByteArray();bytes.resize(particles.size()*STRIDE)
	for i in particles.size():
		var p: Dictionary=particles[i]
		# Unknown future metadata keeps the ordinary lossless graph representation.
		if p.size()!=KEYS.size() or not KEYS.all(func(key):return p.has(key)):return null
		if not indices.has(p.species):indices[p.species]=species.size();species.append(p.species)
		var at:=i*STRIDE
		bytes.encode_s64(at,p.id);bytes.encode_s64(at+8,p.source);bytes.encode_s64(at+16,p.compartment)
		bytes.encode_double(at+24,p.amount);bytes.encode_double(at+32,p.fuel)
		for pair in [[40,p.p],[48,p.previous],[56,p.v]]:
			bytes.encode_float(at+pair[0],pair[1].x);bytes.encode_float(at+pair[0]+4,pair[1].y)
		bytes.encode_double(at+64,p.angle);bytes.encode_u32(at+72,indices[p.species]);bytes.encode_u32(at+76,int(p.alive))
	return {"$cytoplasm":1,"species":species,"bytes":bytes}
static func decode(data: Dictionary) -> Array:
	var bytes: PackedByteArray=data.get("bytes",PackedByteArray());var species: PackedStringArray=data.get("species",PackedStringArray())
	if data.get("$cytoplasm",0)!=1 or bytes.size()%STRIDE!=0:return []
	var result: Array=[];result.resize(bytes.size()/STRIDE)
	for i in result.size():
		var at:=i*STRIDE;var index:=bytes.decode_u32(at+72)
		if index>=species.size():return []
		result[i]={"id":bytes.decode_s64(at),"species":species[index],"amount":bytes.decode_double(at+24),"fuel":bytes.decode_double(at+32),"p":Vector2(bytes.decode_float(at+40),bytes.decode_float(at+44)),"previous":Vector2(bytes.decode_float(at+48),bytes.decode_float(at+52)),"v":Vector2(bytes.decode_float(at+56),bytes.decode_float(at+60)),"angle":bytes.decode_double(at+64),"source":bytes.decode_s64(at+8),"compartment":bytes.decode_s64(at+16),"alive":bytes.decode_u32(at+76)!=0}
	return result
