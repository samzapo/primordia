extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Host=preload("res://scripts/network/world_host.gd")
const Protocol=preload("res://scripts/network/protocol.gd")
class Client:
	extends "res://scripts/network/network_client.gd"
	func _load_identity() -> void:pass
	func _save_identity() -> void:pass
	func _poll_network() -> void:pass
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=Sim.new(56,0,false);sim.server_mode=true;sim.cells=[sim.player];sim.next_id=1
	sim.player.position=Vector2(800,800);sim.player.previous_position=sim.player.position
	sim.habitat_geometry=Sim.Habitat.new(56,sim.cells)
	sim.lineage.register(sim.player,-1,0,"active",0)
	var account={"selected":sim.player.id,"current":sim.player,"root":sim.player.lineage_id(),"lineage":sim.lineage,"evolution":sim.evolution,"edit":0,"sequence":0}
	var host=Host.new();host.world=sim;host.epoch=7;host.world_id="death-fixture";host.accounts={"fixture":account}
	var peer={"account":"fixture","view":Vector4(800,800,600,450),"death_after":0,"selected_cell":sim.player.id,"followed_cell":sim.player.id}
	var client=Client.new();root.add_child(client);client.set_process(false);client.set_physics_process(false)
	client.music.enabled=false;client.music.player.stop()
	client._welcome({"token":"a".repeat(64),"epoch":7,"sequence":0,"edit":0,"seed":56,"habitat":preload("res://scripts/network/state_codec.gd").new().capture(sim.habitat_geometry),"death_serial":0})
	client._snapshot(host._frame(peer));client._update_world(1)
	var ended=sim.player;var site: Vector2=ended.position
	sim._die(ended)
	# Multiplayer ownership must override the managed simulation's player flag.
	sim.death_bursts[-1].player=false
	host._recover_families(.01)
	check(not account.current.dead and account.current.id!=ended.id,"Authority immediately selects a real successor/new lineage")
	var frame: Dictionary=host._frame(peer);frame.protocol=Protocol.VERSION
	frame=Protocol.unpack(Protocol.pack(frame))
	check(frame.deaths.size()==1 and frame.deaths[0].id==ended.id and frame.deaths[0].player,"Real wire codec carries the correct account's death identity and membrane")
	client._snapshot(frame);client._process(.05)
	check(client.world.player.id==account.current.id and client.death_view.bursts.size()==1,"Browser draws a rupture even after the selected body has already changed")
	check(client.death_focus_age==0 and Sim.Medium.offset(client.render_camera,site).length()<.001,"Browser holds the death site before following its replacement")
	var biology:=var_to_bytes(preload("res://scripts/network/state_codec.gd").new().capture(sim))
	client._snapshot(frame);client._process(.2)
	check(client.death_view.bursts.size()==1 and client.death_focus_age>.1,"Repeated frames do not restart the rupture or death camera")
	client.user_paused=true
	var age: float=client.death_view.bursts[0].age
	client._process(.5)
	check(client.death_view.bursts[0].age==age,"Local Pause freezes existing rupture fragments")
	client.user_paused=false;client._process(2)
	check(client.death_view.bursts.is_empty() and client.death_focus_age>=1.8,"Rupture expires and the new cell becomes the normal follow target")
	check(var_to_bytes(preload("res://scripts/network/state_codec.gd").new().capture(sim))==biology,"Death presentation never changes authority time, resources, or random streams")
	peer.death_after=sim.death_serial
	check(host._frame(peer).deaths.is_empty(),"Already delivered deaths are omitted from later network frames")
	peer.death_after=0;peer.selected_cell=-2;peer.followed_cell=-2
	check(not host._frame(peer).deaths[0].player,"Nearby foreign-cell deaths animate without hijacking the personal camera")
	peer.view=Vector4(2800,1800,50,50)
	check(host._frame(peer).deaths.is_empty(),"Distant deaths do not add invisible presentation work")
	peer.selected_cell=ended.id
	check(host._frame(peer).deaths.size()==1,"Personal death remains visible when succession moves outside the old view")
	sim.time=2
	check(host._frame(peer).deaths.is_empty(),"Expired authority facts cannot replay after a slow snapshot")
	client.death_view.bursts.append({"age":0.0})
	client._welcome({"token":"a".repeat(64),"epoch":8,"sequence":0,"edit":0,"seed":56,"habitat":preload("res://scripts/network/state_codec.gd").new().capture(sim.habitat_geometry),"death_serial":sim.death_serial})
	check(client.world.death_bursts.is_empty() and client.death_view.bursts.is_empty() and client.death_seen==sim.death_serial,"Reconnect resets presentation at the advertised death baseline")
	client.queue_free();host.free();await process_frame
	print("NETWORK DEATHS: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
