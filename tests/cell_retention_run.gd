extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Retention=preload("res://scripts/network/cell_retention.gd")
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var sim=Sim.new(28,0,false);sim.cells=[sim.player]
 var npc=Sim.Cell.new(78,Vector2(200,100));npc.biomass=29;npc.energy=33;sim.cells.append(npc)
 var dormant=Sim.Cell.new(79);dormant.age=83;sim.lineage.dormant.append(dormant)
 sim.player.chemistry.emit("food",3,Vector2(4,2))
 sim.player.add_organ("toxin",1,"graze",false)
 var saved: Dictionary={"world_id":"fixture","tick":0,"graph":Codec.new().capture({"world":sim})}
 var before:=Retention.manifest(saved)
 check(before.cells.size()==3,"Guard includes NPCs and dormant successors as well as the player")
 var restored=Codec.new().restore(saved.graph)
 var next: Dictionary={"world_id":"fixture","tick":0,"graph":Codec.new().capture(restored)}
 check(Retention.compare(before,Retention.manifest(next)).ok,"Codec reload preserves every durable cell field independent of graph reference order")
 restored.world.cells[1].energy-=1
 next.graph=Codec.new().capture(restored)
 var changed:=Retention.compare(before,Retention.manifest(next))
 check(not changed.ok and changed.changed.has("78") and "energy" in changed.changed["78"],"A single lost ATP in an NPC rejects the boundary")
 restored.world.cells[1].energy+=1;restored.world.cells.erase(restored.world.cells[1])
 next.graph=Codec.new().capture(restored)
 check(not Retention.compare(before,Retention.manifest(next)).ok,"A missing NPC rejects the boundary")
 restored=Codec.new().restore(saved.graph);restored.world.lineage.dormant.clear()
 next.graph=Codec.new().capture(restored)
 check(not Retention.compare(before,Retention.manifest(next)).ok,"A missing dormant successor rejects the boundary")
 restored=Codec.new().restore(saved.graph);restored.world.player.chemistry.particles[0].fuel-=.1
 next.graph=Codec.new().capture(restored)
 check(not Retention.compare(before,Retention.manifest(next)).ok,"Lost vacuole fuel rejects the boundary")
 restored=Codec.new().restore(saved.graph);restored.world.player.organs[0].hp-=1
 next.graph=Codec.new().capture(restored)
 check(not Retention.compare(before,Retention.manifest(next)).ok,"Changed organelle anatomy rejects the boundary")
 # Actual host startup saves and checks before its first physics tick.
 var rejected=preload("res://scripts/network/world_host.gd").new();rejected.world=sim;rejected.world_id="fixture"
 rejected.retention_before=before
 sim.cells[1].energy-=1
 check(not rejected.checkpoint() and rejected.store.sequence==0,"Failed cell validation never rotates a durable checkpoint")
 sim.cells[1].energy+=1
 rejected.world=null;rejected.free()
 var host=preload("res://scripts/network/world_host.gd").new();host.cpu=true
 host.port=21000+OS.get_process_id()%10000
 host.store.directory=ProjectSettings.globalize_path("res://build/retention-"+str(OS.get_process_id()))
 var store=preload("res://scripts/network/world_store.gd").new();store.directory=host.store.directory
 sim.habitat_geometry=Sim.Habitat.new(28,sim.cells)
 sim.enable_perception_domains()
 saved={"world_id":"0123456789abcdef0123456789abcdef","epoch":1,"tick":sim.revision,"food_vacuole_version":1,"biochemistry_version":1,"food_supply_version":1,"particle_resolution_version":preload("res://scripts/network/particle_resolution.gd").VERSION,"graph":Codec.new().capture({"world":sim,"accounts":{}})}
 check(store.save(saved),"Retained fixture checkpoint is durable")
 root.add_child(host)
 check(host.running and host.cell_retention.get("ok",false),"Actual startup verifies all saved bodies before accepting clients")
 if not host.running:print(host.startup_error)
 host.set_process(false);host.set_physics_process(false);host.listener.stop();host.world=null;host.queue_free();await process_frame
 for name in ["world-0.pworld","world-1.pworld","health.json"]:DirAccess.remove_absolute(store.directory.path_join(name))
 DirAccess.remove_absolute(store.directory)
 print("CELL RETENTION: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
