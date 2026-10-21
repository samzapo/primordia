extends SceneTree
## Owner-requested finite 36-cell food chain. No rescue stock or replacement.
const Sim=preload("res://scripts/simulation.gd")
var founders: Dictionary={}
func option(key: String,fallback: String) -> String:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with(key+"="):return arg.substr(key.length()+1)
 return fallback
func _initialize() -> void:run.call_deferred()
func fixture(seed_value: int):
 var sim=Sim.new(seed_value,0,false)
 sim.cells.clear();sim.particles.clear();sim.pheromones.clear();sim.pending_replacements.clear()
 sim.server_mode=true;sim.evolution.enabled=false;sim.evolution.sandbox=true
 sim.habitat_geometry=Sim.Habitat.new(seed_value,[]);sim.habitat_geometry.enabled=false;sim.camera_follows_player=false;sim.camera_position=Vector2.ZERO;sim.view_half=Vector2(40,40)
 sim.enable_ambient_carbon();sim.particle_limit=5000
 var kinds_by_role={
  "pore_hunter":["hunting","propulsion","feeding","poreforming"],
  "parasite":["hunting","sensing","propulsion","proboscis"],
  "grazer":["feeding","cilia"],
  "producer":["photosynthesis","photosynthesis","mitochondrion"]}
 var roles: Array=[]
 for role in Sim.Investment.MIX:
  for i in Sim.Investment.MIX[role]:roles.append("pore_hunter" if role=="hunter" else role)
 # Interleave roles spatially, using a deterministic shuffle.
 var order: Array=range(36)
 var rng:=RandomNumberGenerator.new();rng.seed=seed_value
 for i in range(35,0,-1):
  var j:=rng.randi_range(0,i);var swap=order[i];order[i]=order[j];order[j]=swap
 for i in 36:
  var role: String=roles[i];var k: int=order[i]
  var cell=Sim.Cell.new(i,Vector2(1400+(k%6)*210,650+int(k/6)*210))
  cell.role="ancestor";cell.body=60;cell.biomass=40;cell.energy=72;cell.resource_effects_enabled=false;cell.angle=rng.randf()*TAU
  cell.update_geometry();cell.membrane=Sim.Cell.Membrane.new(cell.radius,seed_value*100+i)
  var kinds: Array=kinds_by_role[role]
  for j in kinds.size():
   var mounted: float=PI/2 if kinds[j]=="hunting" else PI if kinds[j] in ["propulsion","cilia"] else 0.0 if kinds[j] in ["feeding","proboscis"] else -PI/2 if kinds[j]=="poreforming" else TAU*j/kinds.size()
   if not cell.add_organ(kinds[j],mounted,"graze",false):push_error("Minimum anatomy does not fit "+role+" "+kinds[j])
  cell.update_geometry();sim.cells.append(cell);founders[cell.id]=role
  # Lock the minimal adult builds; descendants can mature through that same role's policy.
  cell.investment_retry_at=INF
  sim.investment.lineages[cell.lineage_id()]="hunter" if "hunter" in role else role
  for leaf in cell.organs:
   if leaf.kind=="photosynthesis":cell.chemistry.emit("carbon",5,cell.local_point(leaf.a)*.72)
  cell.oxygen=14
 sim.next_id=36;sim.player=sim.cells[0];sim.lineage=sim._family_ledger(sim.player)
 sim.cell_index.rebuild(sim.cells);sim.grid.rebuild(sim.particles)
 if option("--pool","on")=="on" and not sim.enable_particle_pool():push_error("Native trial could not acquire particle ownership")
 return sim
func organic(sim) -> float:
 var result: float=sim.respiration_loss-sim.external_input
 for cell in sim.cells:
  if not cell.dead:result+=cell.organic_mass()
 var packets: Array=sim.kernels.pool_snapshots() if sim.particle_pool else sim.particles
 for packet in packets:
  if packet.alive:result+=packet.amount*Sim.Catalog.material(packet.kind)
 return result

func sample(sim) -> Dictionary:
 var groups: Dictionary={};var stores: Dictionary={};var anatomy: Dictionary={};var starved:=0;var food:=0.0;var mass:=0.0;var captured:=0.0;var fixed:=0.0
 for cell in sim.cells:
  if cell.dead:continue
  var role: String=founders.get(cell.lineage_id(),"untracked")
  groups[role]=int(groups.get(role,0))+1
  if not stores.has(role):stores[role]={"biomass":0.0,"food":0.0,"ATP":0.0}
  stores[role].biomass+=cell.biomass;stores[role].food+=cell.substrate;stores[role].ATP+=cell.energy
  var phenotype: String=cell.synergy()
  anatomy[phenotype]=int(anatomy.get(phenotype,0))+1
  if cell.starvation_seconds>0:starved+=1
  food+=cell.substrate;mass+=cell.biomass;captured+=cell.eaten;fixed+=cell.fixed_carbon
 return {"time":sim.time,"lineages":groups,"stores":stores,"adult_anatomy":anatomy,"starving":starved,"food":food,"biomass":mass,"eaten":captured,"fixed":fixed,"external":sim.habitat_census().external,"death_causes":sim.events.filter(func(e):return e.type=="death").map(func(e):return e.get("cause",e.get("reason","unspecified"))),"births":sim.events.filter(func(e):return e.type=="division").size(),"deaths":sim.events.filter(func(e):return e.type=="death").size()}
func run() -> void:
 var seconds:=float(option("--seconds","900"));var dt:=1.0/float(option("--hz","60"))
 var sim=fixture(int(option("--seed","9601")));var started:=Time.get_ticks_msec()
 print("FOOD_CHAIN_START ",JSON.stringify(sample(sim)))
 var next:=60.0
 var initial_mass:=organic(sim)
 for i in roundi(seconds/dt):
  sim.step(dt)
  if sim.time>=next:
   print("FOOD_CHAIN ",JSON.stringify(sample(sim)));next+=60
   await process_frame
  for cell in sim.cells:
   if not is_finite(cell.energy) or not is_finite(cell.biomass):push_error("Non-finite cell physiology");quit(1);return
 var material_error:=organic(sim)-initial_mass
 if absf(material_error)>.05:push_error("Food chain material imbalance: "+str(material_error))
 print("FOOD_CHAIN_FINAL ",JSON.stringify({"result":sample(sim),"material_error":material_error,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"hz":1/dt,"seed":sim.seed_value,"replacement":false,"initial_external_food":0,"adult_investment":"minimal anatomy held","descendant_investment":"inherited role","test_world":"finite synthetic pond; not production"}))
 sim.disable_particle_pool();quit(1 if absf(material_error)>.05 else 0)
