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
		particles.append({"age":i*.0001,"id":9007199254740993+i,"species":"atp" if i%2 else "adp","amount":0.4+i*.00001,"fuel":0.0,"p":Vector2(i%97,i%61),"previous":Vector2(i%43,-i%17),"v":Vector2(2,-3),"angle":i*.123,"source":-1,"compartment":-1,"alive":i%13!=0})
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
	if unpacked.is_empty():quit(1);return
	var restored=Codec.new().restore(unpacked.graph)
	check(restored.cells[0]==restored.player,"Compact snapshot retains shared cell reference identity")
	check(var_to_bytes(restored.player.chemistry.particles)==original,"All particle fields, 64-bit IDs, finite quantities, positions, sources and compartments survive exactly")
	check(var_to_bytes(sim.player.chemistry.particles)==original,"Presentation encoding never mutates authoritative cytoplasm")
	check(legacy.graph.objects.any(func(record):return record.kind=="chemistry" and record.fields.particles.has("$array")),"Checkpoint capture keeps its existing full dictionary schema")
	var old_wire: Dictionary=Columns.encode([particles[0]],1)
	check(old_wire["$cytoplasm"]==1 and Columns.decode(old_wire)[0].amount==particles[0].amount,"Legacy clients keep receiving their negotiated layout with unchanged finite stock")
	var current: Dictionary=Columns.encode([particles[0]])
	var legacy_columns={"$cytoplasm":1,"species":current.species,"bytes":current.bytes.slice(0,80)}
	check(Columns.decode(legacy_columns)[0].age==0 and Columns.decode(legacy_columns)[0].id==particles[0].id,"Legacy wire columns acquire an empty residence clock while retaining full-width identity")
	var future: Dictionary=particles[0].duplicate();future["future_metadata"]=true
	check(Columns.encode([future])==null,"Unknown future particle metadata cannot be silently discarded")
	print("SNAPSHOT TRANSPORT: %d assertions, %d failures; raw=%d compact=%d" % [assertions,failures,raw_legacy,raw_compact])
	quit(0 if failures==0 else 1)
