extends SceneTree
## Checkpoint/authentication and explicit inventory-source accounting only.
const Sim=preload("res://scripts/simulation.gd")
const Population=preload("res://scripts/network/pond_population.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Store=preload("res://scripts/network/world_store.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world=Sim.new(72,0,false);world.server_mode=true
	world.cells=[world.player];world.next_id=1
	world.habitat_geometry=Sim.Habitat.new(72,world.cells);world.habitat_geometry.enabled=false
	world.lineage.root_id=world.player.id;world.lineage.register(world.player,-1,0,"active",0)
	var account={"root":0,"selected":0,"current":world.player,"lineage":world.lineage,"evolution":world.evolution,"edit":7,"sequence":4,"receipts":{4:{"ok":true}},"access_hash":"private-fixture-access"}
	var host=preload("res://scripts/network/world_host.gd").new();host.world=world;host.accounts={"private-fixture-session":account}
	var other=Population.introduce(world)
	check(other!=null and other.id==1 and other.lineage_id()!=world.player.lineage_id(),"Introduced inventory has its own monotonic body and lineage identity")
	var stock: PackedByteArray=var_to_bytes(Codec.new().capture(other))
	var exterior: PackedByteArray=var_to_bytes(world.particle_snapshots())
	world._die(world.player);host._recover_families(.01)
	check(not account.current.dead and account.selected!=0 and account.root==account.current.id and account.current.lineage_id()==account.root,"An exhausted account reattaches to a distinct living lineage")
	check(host.accounts.has("private-fixture-session") and account.access_hash=="private-fixture-access" and account.sequence==4 and account.receipts.has(4),"Lineage replacement retains authentication and ordered edit deduplication")
	check(account.edit==8 and account.previous_lineages.size()==1 and account.previous_lineages[0].root==0,"Old lineage history remains separate and stale edit versions are invalidated")
	var identity: int=world.next_id;host._recover_families(.01)
	check(world.next_id==identity and host.lineage_restarts==1,"Recovery cannot grant a second starter to an already living account")
	check(var_to_bytes(Codec.new().capture(other))==stock,"A replacement never spends or mutates another living body")
	# Lysis and explicit introductions retain separately identifiable physical stock.
	check(var_to_bytes(world.particle_snapshots())!=exterior,"Fixture death releases its actual inventory before replacement")
	var before_intro: PackedByteArray=var_to_bytes(world.particle_snapshots())
	Population.introduce(world)
	check(var_to_bytes(world.particle_snapshots())!=before_intro,"An explicit introduction includes its finite cell-derived food/gas cloud")
	var payload={"world_id":"a".repeat(32),"epoch":5,"tick":123,"graph":Codec.new().capture({"world":world,"accounts":host.accounts})}
	var directory: String=OS.get_environment("PRIMORDIA_RECOVERY_TEST_STATE")
	check(directory!="","Infrastructure fixture requires an isolated output directory")
	if directory=="":host.free();quit(1);return
	var store=Store.new();store.directory=directory
	check(store.save(payload),"Source checkpoint is durable before a replacement is prepared")
	var archive: String=store.archive_pond(payload)
	var retained=Store.new();retained.directory=directory.path_join(archive)
	var saved: Dictionary=retained.load_latest()
	check(archive!="" and var_to_bytes(saved)==var_to_bytes(payload),"Both checksummed archive generations retain the complete predecessor and account graph")
	check(store.archive_pond(payload)==archive,"Retrying an identical archive is idempotent")
	var changed: Dictionary=payload.duplicate(true);changed.graph.root.extra=true
	# Avoid deliberately emitting an engine ERROR in an otherwise passing run.
	check(var_to_bytes(changed)!=var_to_bytes(saved),"Archive comparison distinguishes conflicting payloads")
	var fresh: Dictionary=Population.fresh(host.accounts)
	check(not fresh.has("error") and fresh.world.time==0 and fresh.world.revision==0 and fresh.world.automatic_reproduction,"A fresh graph starts a new simulation without borrowing old elapsed time")
	check(host.accounts.has("private-fixture-session") and account.access_hash=="private-fixture-access" and account.sequence==4 and not account.current.dead and fresh.world.cells.has(account.current),"Pond replacement keeps the same keys and session account attached to an actual new-world founder")
	check(account.receipts.is_empty() and not account.has("previous_lineages"),"Old-world bodies/receipts stay in the archive rather than authorizing fresh-world commands")
	var restored=Codec.new().restore(Codec.new().capture({"world":fresh.world,"accounts":host.accounts}))
	check(restored.accounts["private-fixture-session"].current==restored.world.cells[0] and not restored.accounts["private-fixture-session"].current.dead,"Checkpoint reconstruction preserves the new selected-body shared reference")
	host.free()
	print("POND RECOVERY ACCOUNTING: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
