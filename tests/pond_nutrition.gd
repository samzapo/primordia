extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Population=preload("res://scripts/network/pond_population.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world=Sim.new(57,0,false);world.cells=[world.player];world.server_mode=true
	world.habitat_geometry=Sim.Habitat.new(57,world.cells)
	var cell=world.player;cell.biomass=36
	check(cell.add_organ("propulsion",PI) and cell.add_organ("photosynthesis",1.2),"Player pays ordinary tissue for the reported flagellum/photosynthesizer setup")
	var identity:=var_to_bytes(Codec.new().capture(cell))
	var stock: Dictionary=Population.enrich_existing(world)
	check(var_to_bytes(Codec.new().capture(cell))==identity,"Supply upgrade preserves the actual body, anatomy, ATP, health, lineage and age")
	check(stock.cells==1 and stock.packets<300 and stock.nutrient>=400 and stock.carbon>=200,"A finite rich introduction cloud fits the existing particle-count budget")
	var actual:=0.0
	for packet in world.particles:
		if packet.kind==Sim.NUTRIENT:actual+=packet.amount
	check(absf(actual-stock.nutrient)<.00001 and world.particles.all(func(packet):return packet.owner==cell.id),"All recorded food exists as source-labelled finite external packets")
	world.grid.rebuild(world.particles)
	# The fixture founder has no mouth; add its optional groove without changing the report.
	if cell.count("feeding")==0:cell.add_organ("feeding",0,"graze",false)
	world.particles[0].p=cell.pore_center(cell.organs.filter(func(organ):return organ.kind=="feeding")[0])
	world.grid.rebuild(world.particles);world.camera_position=cell.position;world.camera_follows_player=true
	world.camera_views=[Vector4(cell.position.x,cell.position.y,500,500)]
	if world.kernels!=null:world.kernels.set_activity_views(world.camera_views,true)
	var food_before: float=world.particles.reduce(func(total,packet):return total+(packet.amount if packet.kind==Sim.NUTRIENT and packet.alive else 0.0),0.0)
	world._feed(cell)
	var remaining: float=world.particles.reduce(func(total,packet):return total+(packet.amount if packet.kind==Sim.NUTRIENT and packet.alive else 0.0),0.0)
	check(cell.eaten>0 and cell.substrate>0 and absf(cell.substrate+remaining-food_before)<.00001,"Food is acquired only through ordinary physical intake with a matching external debit")
	var aged=Sim.new(59,0,false);aged.cells=[]
	var ids: Array[int]=[]
	for i in 512:
		aged.spawn_particle(Sim.NUTRIENT,Vector2(100+(i%32)*60,100+(i/32)*60),Vector2.ZERO,9,cell.id);ids.append(i)
	aged.time=1800;aged.revision=1
	aged._chemistry(1800,ids,true)
	var surviving: float=aged.particles.reduce(func(total,packet):return total+(packet.amount if packet.alive else 0.0),0.0)
	check(surviving>512*9*.8,"A half-hour-old finite food patch still contains enough material to forage")
	check(absf(surviving+aged.respiration_loss-512*9)<.000001,"Retained food plus actual unary losses exactly matches the initial stock")
	# This no-fuel fixture cannot create ATP or biomass during its survival grace.
	var hungry=Sim.Cell.new(777);hungry.energy=0;hungry.biomass=0;hungry.substrate=0
	var material: float=hungry.organic_mass()
	for second in 300:world._metabolize(hungry,1)
	check(hungry.health==100 and hungry.energy==0 and hungry.starvation_seconds==300 and hungry.organic_mass()==material,"Five minutes without fuel preserves the body without granting resources")
	for second in 120:world._metabolize(hungry,1)
	check(hungry.health>87 and hungry.health<89 and hungry.energy==0,"Sustained severe starvation gradually damages health after the grace")
	var elapsed: float=hungry.starvation_seconds
	hungry.chemistry.emit("food",8,Vector2(30,0));world._metabolize(hungry,1)
	check(hungry.energy>0 and hungry.starvation_seconds<elapsed,"Actual metabolized food starts recovery from prolonged starvation")
	cell.starvation_seconds=123;cell.age=456;cell.health=64
	var saved:=Codec.new().capture({"world":world,"accounts":{"fixture":{"current":cell,"selected":cell.id,"root":cell.lineage_id(),"lineage":world.lineage,"evolution":world.evolution,"edit":0,"sequence":0,"receipts":{},"access_hash":"kept"}}})
	var restored=Codec.new().restore(saved)
	check(restored.accounts.fixture.current==restored.world.player and restored.world.player.id==cell.id and restored.world.player.age==456 and restored.world.player.starvation_seconds==123 and restored.world.player.health==64,"Checkpoint restores the same player's body and starvation state without wall-downtime charges")
	check(restored.accounts.fixture.access_hash=="kept" and restored.world.player.organs==cell.organs and restored.world.particle_count()==world.particle_count(),"Restart preserves keys, anatomy and finite food rather than reseeding a pond")
	var directory: String=ProjectSettings.globalize_path("res://build/nutrition-upgrade-"+str(OS.get_process_id()))
	var store=preload("res://scripts/network/world_store.gd").new();store.directory=directory
	check(store.save({"world_id":"b".repeat(32),"epoch":3,"tick":world.revision,"food_vacuole_version":1,"biochemistry_version":1,"particle_resolution_version":3,"graph":saved}),"An isolated predecessor checkpoint is durable before upgrading")
	var old_invite:=OS.get_environment("PRIMORDIA_INVITE");OS.set_environment("PRIMORDIA_INVITE","nutrition-upgrade-fixture")
	var packets_after:=-1;var upgrade: Dictionary={}
	for restart in 2:
		var host=preload("res://scripts/network/world_host.gd").new();host.cpu=true;host.port=24000+OS.get_process_id()%15000;host.store.directory=directory
		root.add_child(host);host.set_process(false);host.set_physics_process(false)
		check(host.running and host.world_id=="b".repeat(32) and host.accounts.fixture.current.id==cell.id and host.accounts.fixture.current.age==456 and host.accounts.fixture.current.organs==cell.organs,"Actual authority startup restores the retained player's cell on restart %d" % restart)
		if restart==0:
			packets_after=host.world.particle_count();upgrade=host.food_supply.duplicate(true)
			check(upgrade.cells==1 and upgrade.nutrient>0 and DirAccess.dir_exists_absolute(directory.path_join(upgrade.archive)),"Legacy upgrade archives its predecessor and records actual finite exterior additions")
		else:
			check(host.world.particle_count()==packets_after and host.food_supply==upgrade,"Ordinary authority restart cannot grant the one-time food inventory twice")
		host.running=false;host.listener.stop();host.queue_free();await process_frame
	OS.set_environment("PRIMORDIA_INVITE",old_invite)
	print("POND NUTRITION: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
