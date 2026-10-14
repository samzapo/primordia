extends SceneTree
const Codec=preload("res://scripts/network/state_codec.gd")
const Protocol=preload("res://scripts/network/protocol.gd")
const Columns=preload("res://scripts/network/cytoplasm_codec.gd")
var assertions:=0
var failures:=0
func check(value: bool,message: String) -> void:
	assertions+=1
	if not value:failures+=1;push_error("FAIL: "+message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=preload("res://scripts/simulation.gd").new(0,0,false)
	var particles: Array=[]
	for i in 55000:
		particles.append({"id":9007199254740993+i,"species":"atp" if i%2 else "adp","amount":0.4+i*.00001,"fuel":0.0,"p":Vector2(i%97,i%61),"previous":Vector2(i%43,-i%17),"v":Vector2(2,-3),"angle":i*.123,"source":-1,"compartment":-1,"alive":i%13!=0})
	sim.player.chemistry.particles=particles
	var original:=var_to_bytes(particles)
	var root={"cells":[sim.player],"player":sim.player}
	var legacy={"kind":"snapshot","protocol":Protocol.VERSION,"graph":Codec.new().capture(root)}
	var raw_legacy: int=var_to_bytes(legacy).size()
	check(raw_legacy>Protocol.MAX_FRAME,"Real 55000-particle dictionaries reproduce the inflated-frame limit")
	check(Protocol.pack(legacy).is_empty(),"Sender rejects an inflated oversized frame before gzip can disguise it")
	var projected={"kind":"snapshot","protocol":Protocol.VERSION,"graph":Codec.new().capture(root,{},true)}
	var raw_compact: int=var_to_bytes(projected).size()
	check(raw_compact<Protocol.MAX_FRAME and raw_compact<raw_legacy*.4,"Lossless numeric columns fit the unchanged bounded wire envelope")
	var unpacked:=Protocol.unpack(Protocol.pack(projected))
	check(not unpacked.is_empty(),"Dense world snapshot survives actual gzip protocol packing and decoding")
	var restored=Codec.new().restore(unpacked.graph)
	check(restored.cells[0]==restored.player,"Compact snapshot retains shared cell reference identity")
	check(var_to_bytes(restored.player.chemistry.particles)==original,"All particle fields, 64-bit IDs, finite quantities, positions, sources and compartments survive exactly")
	check(var_to_bytes(sim.player.chemistry.particles)==original,"Presentation encoding never mutates authoritative cytoplasm")
	check(legacy.graph.objects.any(func(record):return record.kind=="chemistry" and record.fields.particles.has("$array")),"Checkpoint capture keeps its existing full dictionary schema")
	var future: Dictionary=particles[0].duplicate();future["future_metadata"]=true
	check(Columns.encode([future])==null,"Unknown future particle metadata cannot be silently discarded")
	print("SNAPSHOT TRANSPORT: %d assertions, %d failures; raw=%d compact=%d" % [assertions,failures,raw_legacy,raw_compact])
	quit(0 if failures==0 else 1)
