extends SceneTree
const Delivery=preload("res://scripts/network/camera_delivery.gd")
const Streaming=preload("res://scripts/particle_streaming.gd")
const Sim=preload("res://scripts/simulation.gd")
class Device:
	extends RefCounted
	var calls: Array=[]
	func publish_views(regions: Array) -> bool:calls=regions.duplicate();return true
class Bridge:
	extends RefCounted
	var pending: Array=[]
	var streaming
	var gpu=Device.new()
	var preparations:=0
	var admitted: Array=[]
	func prepare_publication() -> bool:
		preparations+=1;admitted.append_array(pending);pending.clear()
		return true
class HostProbe:
	extends "res://scripts/network/world_host.gd"
	var delivered: Array=[]
	func _send_snapshot(_peer: Dictionary,_records: PackedByteArray,frame: Dictionary={}) -> void:delivered.append(frame)
	func _frame(peer: Dictionary,coverage: Vector4=Vector4.ZERO) -> Dictionary:
		return {"coverage":coverage,"camera":peer.view}
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var view:=Vector4(1000,1000,200,150)
	var expanded:=Delivery.expanded(view)
	check(expanded==Vector4(1000,1000,584,534),"Delivery prepares a real384-unit border without changing the actual view")
	check(Delivery.covers(expanded,Vector4(1300,1000,200,150)),"Ordinary camera movement remains covered by particles already delivered")
	check(not Delivery.covers(expanded,Vector4(2000,1000,200,150)),"A distant jump cannot be mislabeled as covered")
	check(Delivery.covers(Vector4(4090,1000,500,400),Vector4(60,1000,200,150)),"Prepared coverage crosses the wrapped pond seam")
	check(Delivery.covers(Vector4(1000,1000,2048,1280),Vector4(3500,2300,2048,1280)),"A full-axis buffer remains complete after its center moves")
	check(Delivery.expanded(Vector4(100,100,2000,1200)).z==2048 and Delivery.expanded(Vector4(100,100,2000,1200)).w==1280,"Overscan never exceeds one whole pond")
	var bridge=Bridge.new();var stream=Streaming.new()
	stream._owner=weakref(bridge);stream.cold.dimensions=Vector2i(16,10)
	bridge.streaming=stream
	var far={"p":Vector2(3000,1000),"kind":0,"amount":.3,"alive":true}
	stream.cold.put(far,0);stream.queue_depth=900;stream.eviction_deferred=800
	check(stream.region_ready(expanded),"Unrelated cold particles and outgoing transfers cannot stall a ready view")
	check(not stream.region_ready(Vector4(3000,1000,200,150)),"Cold particles inside a new view block complete-particle claims")
	bridge.pending=[{"p":Vector2(1100,1000),"alive":true}]
	check(not stream.region_ready(view),"Visible admission escrow cannot be presented as a complete GPU view")
	bridge.pending.clear()
	stream.multiview=true;stream.regions=[Vector4(2048,1280,2048,1280)]
	stream.cold.put({"p":Vector2(1080,1020),"kind":0,"amount":.2,"alive":true},0)
	stream.priority_views=[view]
	var state: int=stream.random.state
	var before:=var_to_bytes(stream.cold.snapshots())
	var keys:=stream.admission_keys()
	check(keys[0]==stream.cold.key(Vector2(1080,1020)),"Newly visible chunks are admitted before distant overscan")
	check(var_to_bytes(stream.cold.snapshots())==before and stream.random.state==state,"Admission ordering cannot remove material, change identity or draw random numbers")
	# Restore only the distant cold packet, then exercise actual publication selection.
	stream.cold=preload("res://scripts/particle_regions.gd").new();stream.cold.dimensions=Vector2i(16,10);stream.cold.put(far,0)
	var host=HostProbe.new();host.world=Sim.new(1,0,false);host.world.resident=bridge
	host.world.revision=10;host.world.camera_views=[view,Vector4(3000,1000,200,150)]
	host.peers={1:{"account":"ready","view":view,"view_tick":0},2:{"account":"loading","view":Vector4(3000,1000,200,150),"view_tick":0}}
	stream.cold.put({"p":Vector2(1500,1000),"kind":0,"amount":.1,"alive":true},0)
	var smaller: Vector4=host._delivery_coverage(host.peers[1])
	check(smaller!=Vector4.ZERO and smaller.z<expanded.z and Delivery.covers(smaller,view),"Incomplete overscan falls back to a smaller genuinely prepared border")
	stream.cold=preload("res://scripts/particle_regions.gd").new();stream.cold.dimensions=Vector2i(16,10);stream.cold.put(far,0)
	# Reproduce post-tick air emissions on every publication. A ready camera
	# must first admit the actual escrow, never ignore it or wait for a tick gap.
	bridge.pending=[{"p":Vector2(1100,1000),"alive":true}]
	check(not stream.region_ready(view),"Late emissions genuinely block complete coverage before admission")
	host._publish()
	check(bridge.preparations==1 and bridge.admitted.size()==1 and bridge.pending.is_empty(),"Publication admits late paid emissions before checking camera readiness")
	check(bridge.gpu.calls.size()==1 and host.pending_frame.frames.has(1) and not host.pending_frame.frames.has(2),"The actual host publishes a ready observer while another observer is loading")
	check(bridge.gpu.calls[0]==expanded,"The GPU gathers the captured padded region rather than only the current viewport")
	host.peers[1].view=Vector4(1300,1000,200,150)
	host._publication_done({"bytes":PackedByteArray()})
	check(host.delivered.size()==1 and host.delivered[0].coverage==expanded,"An in-flight GPU gather survives camera movement inside its captured buffer")
	host.world.resident=null;host.free()
	print("CAMERA DELIVERY: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
