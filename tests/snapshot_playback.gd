extends SceneTree
const Playback=preload("res://scripts/network/snapshot_playback.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Sim=preload("res://scripts/simulation.gd")
class Client:
	extends "res://scripts/network/network_client.gd"
	func _load_identity() -> void:pass
	func _save_identity() -> void:pass
	func _poll_network() -> void:pass
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error("FAIL: "+message)
func frame(i: int) -> Dictionary:
	return {"tick":i,"time":i*0.04,"presentation_usec":i*100000}
func packet_bytes(at: Vector2) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(32)
	bytes.encode_float(0,at.x);bytes.encode_float(4,at.y)
	bytes.encode_float(12,0);bytes.encode_float(16,1)
	bytes.encode_u32(24,19);bytes.encode_u32(28,0)
	return bytes
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var buffer=Playback.new()
	var arrivals: Array[float]=[]
	for i in 120:
		var jitter: float=[0.03,0.07,0.02,0.16,0.01,0.0,0.08,0.02][i%8]
		arrivals.append(maxf(i*0.1+jitter,arrivals[-1]+0.002 if not arrivals.is_empty() else 0))
	var sent:=0;var previous:=-1.0;var stalls:=0;var backwards:=false;var excessive_step:=false
	var old_origin:=0.0;var old_target:=0.0;var old_arrival:=0.0;var old_pose:=0.0;var old_stalls:=0
	for n in 690:
		var now:=n/60.0
		while sent<arrivals.size() and arrivals[sent]<=now:
			buffer.push(frame(sent),arrivals[sent])
			old_origin=old_pose;old_target=sent*0.1;old_arrival=arrivals[sent]
			sent+=1
		var sample: Dictionary=buffer.sample(now)
		old_pose=lerpf(old_origin,old_target,clampf((now-old_arrival)/0.1,0,1))
		if sample.is_empty():continue
		var pose:=lerpf(sample.before.tick*0.1,sample.after.tick*0.1,sample.alpha)
		if now>1:
			stalls+=int(pose-previous<0.00001)
			backwards=backwards or pose<previous-0.000001
			excessive_step=excessive_step or pose-previous>1.121/60
			old_stalls+=int(now-old_arrival>0.1)
		previous=pose
	check(old_stalls>80,"Deterministic uneven delivery reproduces stop/start motion in the old arrival-reset blend")
	check(stalls==0 and not backwards and not excessive_step,"Buffered constant motion remains monotonic with no holds or large steps under the same delivery jitter")
	check(buffer.frames.size()<=Playback.MAX_FRAMES and buffer.delay<=Playback.MAX_DELAY,"Presentation memory and added delay are bounded")
	check(buffer.cursor>10 and buffer.cursor<11.5,"Playback follows host wall cadence even when authority simulation time advances more slowly")
	var last: float=buffer.cursor;buffer.sample(12.2)
	check(buffer.cursor>=last and buffer.cursor<=11.9,"Missing updates never extrapolate particles or simulate invented chemistry")
	check(not buffer.push(frame(1),12.3),"Late or duplicate snapshots cannot rewind the view")
	for i in range(130,170):buffer.push(frame(i),i*0.1)
	check(buffer.frames.size()==Playback.MAX_FRAMES,"Burst delivery cannot accumulate an unbounded snapshot backlog")
	var resumed: Dictionary=buffer.sample(17.1)
	check(resumed.alpha>=0 and resumed.alpha<=1 and buffer.resyncs>0,"Returning from a suspended tab skips obsolete motion with valid interpolation")
	buffer.reset()
	check(buffer.sample(20).is_empty() and buffer.frames.is_empty(),"Pause/reconnect can discard the old timeline completely")
	# Actual live steady-player sample was about1.7s between captures.
	var sparse=Playback.new();var next_sparse:=0;var last_sparse:=-1.0;var jumped:=false;var reversed:=false;var steady_holds:=0
	for n in 1200:
		var now:=n/60.0
		if now>=next_sparse*1.7:
			sparse.push({"tick":next_sparse,"time":next_sparse*.2,"presentation_usec":next_sparse*1700000},next_sparse*1.7);next_sparse+=1
		var sample: Dictionary=sparse.sample(now)
		if sample.is_empty():continue
		var at: float=lerpf(sample.before.presentation_usec/1000000.0,sample.after.presentation_usec/1000000.0,sample.alpha)
		if now>5 and last_sparse>=0:
			jumped=jumped or at-last_sparse>1.121/60
			reversed=reversed or at<last_sparse
			steady_holds+=int(at-last_sparse<.000001)
		last_sparse=at
	check(not jumped and not reversed and steady_holds==0 and sparse.resyncs==0,"Sparse1.7s authority updates interpolate continuously without periodic hard resets or invented simulation")
	check(sparse.delay<=Playback.MAX_DELAY and sparse.frames.size()<=Playback.MAX_FRAMES,"Sparse recovery retains bounded latency and memory")
	var Host=preload("res://scripts/network/world_host.gd")
	check(Host.publication_deadline(1000000,1000000)==1100000 and Host.publication_deadline(1000000,1250000)==1300000,"Publication resumes at the next original scheduled tick after one late computation")
	check(Host.publication_deadline(1000000,1300000)==1400000,"An execution crossing another boundary drops it rather than firing a catch-up burst")
	var client=Client.new();root.add_child(client);client.set_process(false);client.set_physics_process(false)
	client.music.enabled=false;client.music.player.stop();client.epoch=4
	var sim=Sim.new(18,0,false);sim.cells=[sim.player]
	sim.player.position=Vector2(4090,500);sim.player.previous_position=sim.player.position;sim.player.angle=3.1
	sim.player.chemistry.particles.clear();sim.player.chemistry.emit("food",1,Vector2(10,0))
	var seed: int=sim.rng.state
	var wire={"epoch":4,"tick":1,"time":1.0,"presentation_usec":1000000,"perception":"exteroception","world_id":"playback-fixture","graph":Codec.new().capture({"cells":sim.cells,"player":sim.player,"lineage":sim.lineage,"evolution":sim.evolution}),"flow":sim.fluid.velocity,"acid":sim.acidity.values,"sounds":sim.sound_events,"sound_sequence":0,"sparks":sim.reaction_sparks,"sequence":0,"edit":0,"particles":PackedByteArray()}
	wire.particles=packet_bytes(Vector2(4092,600))
	client._snapshot(wire)
	client.network_alpha=0.25
	sim.player.position=Vector2(6,500);sim.player.previous_position=Vector2(5,500);sim.player.angle=-3.1
	sim.player.chemistry.particles[0].p=Vector2(20,0)
	wire.particles=packet_bytes(Vector2(8,600))
	wire.tick=2;wire.time=1.1;wire.presentation_usec=1100000
	wire.graph=Codec.new().capture({"cells":sim.cells,"player":sim.player,"lineage":sim.lineage,"evolution":sim.evolution})
	client.edit_revision=9
	client._snapshot(wire)
	check(client.edit_revision==9,"Buffered older anatomy cannot rewind a newer command receipt revision")
	check(client.world.player.previous_position==Vector2(4090,500) and client.world.player.position==Vector2(6,500),"Cell interpolation retains actual consecutive server endpoints across the wrapped pond")
	check(client.world.particles[0].previous==Vector2(4092,600) and client.world.particles[0].p==Vector2(8,600),"External particles retain actual endpoints instead of repeatedly easing from partial poses")
	var internal=client.world.player.chemistry.particles[0]
	check(client.world.player.chemistry.render_origins[internal.id].p==Vector2(10,0),"Cytoplasmic particle origins use the same consecutive-frame interval")
	var warming: Dictionary=wire.duplicate();warming.warming=true
	client._receive_snapshot(warming)
	check(not client.loading_world and not client.login.visible,"Preparing another camera region cannot overwrite ready motion or reopen sign-in")
	client.network_alpha=0.5;client.connected=true
	client._toggle_user_pause()
	check(client.user_paused and client.world.player.position==Vector2(0,500),"Pause holds the exact halfway visible wrapped pose without jumping to a buffered target")
	check(client.world.particles[0].p==Vector2(2,600) and internal.p==Vector2(15,0) and absf(absf(client.world.player.angle)-PI)<0.00001,"Pause preserves external/internal positions and shortest-path cell rotation together")
	client._toggle_user_pause()
	check(not client.user_paused and client.playback.frames.is_empty() and client.playback_after_tick==-1,"Resume starts a fresh live buffer instead of replaying paused history")
	check(sim.rng.state==seed and sim.time==0,"Presentation and camera pause never advance authority state or random streams")
	var donor=Sim.Cell.new(501,Vector2(100,500));donor.lineage=sim.player.lineage_id()
	sim.cells.append(donor);sim.lineage.register(donor,sim.player.id,1,"living",0)
	var stale: Dictionary=wire.duplicate()
	stale.graph=Codec.new().capture({"cells":sim.cells,"player":sim.player,"lineage":sim.lineage,"evolution":sim.evolution})
	client._snapshot(stale)
	var merge={"serial":1,"time":client.world.time,"donor":501,"receiver":client.world.player.id,"at":Vector2(100,500),"to":client.world.player.position,"portrait":preload("res://scripts/cell_portrait.gd").capture(client.world.player)}
	var delivery={"epoch":4,"time":client.world.time,"merges":[merge]}
	client._receive_deaths(delivery);client._receive_deaths(delivery)
	check(client.world.merge_bursts.size()==1 and client.received_merge_serial==1,"Side-channel and buffered snapshot duplicates cannot replay a pull-in")
	check(client.cells_by_id[501].dead and client.world.lineage.record_for(501).is_empty(),"The committed fact immediately retires the old donor drawing and family portrait")
	client._snapshot(stale)
	check(client.cells_by_id[501].dead and client.world.lineage.record_for(501).is_empty(),"An older buffered graph cannot resurrect an already consumed donor")
	client.user_paused=true;merge.serial=2;client._receive_deaths(delivery)
	client.user_paused=false;client._receive_deaths(delivery)
	check(client.world.merge_bursts.size()==1 and client.received_merge_serial==2,"A paused merge is consumed without replaying old absorption on resume")
	client.queue_free();await process_frame
	print("SNAPSHOT PLAYBACK: %d assertions, %d failures; old holds=%d new holds=%d" % [assertions,failures,old_stalls,stalls])
	quit(0 if failures==0 else 1)
