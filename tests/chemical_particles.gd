extends RefCounted
const Cell = preload("res://scripts/cell.gd")
const Catalog = preload("res://scripts/chemistry_catalog.gd")
const Surface = preload("res://scripts/surface_chemistry.gd")

static func empty():
	var cell = Cell.new()
	cell.chemistry.particles.clear()
	cell.chemistry.totals.clear()
	cell.chemistry.bins.clear()
	cell.chemistry.vacuoles.clear()
	return cell

static func run(check: Callable) -> void:
	check.call(Catalog.validate()=="","Authored reaction catalog conserves represented material and funds energy")
	var cell = Cell.new()
	var counted := 0.0
	for packet in cell.chemistry.particles:
		if packet.alive and packet.species=="atp": counted += packet.amount
	check.call(is_equal_approx(counted,cell.energy),"ATP is derived from real cytoplasmic particles")
	var before: Array = cell.chemistry.particles.duplicate(true)
	var mass: float = cell.organic_mass()
	cell.chemistry.advance(cell,1.0/60)
	var moved := false
	for i in mini(before.size(),cell.chemistry.particles.size()):
		if before[i].p!=cell.chemistry.particles[i].p: moved=true
	check.call(moved,"Intracellular chemical particles actually advect and diffuse")
	check.call(absf(cell.organic_mass()-mass)<0.0001,"Vacuole creation and intracellular reactions retain material")
	cell = empty()
	var chemistry = cell.chemistry
	var node: Dictionary = chemistry.node_at(chemistry.find_module("glycolysis"))
	var at: Vector2 = chemistry.site(node)
	chemistry.emit("catalyst",0.025,at,node.id,node.id)
	chemistry.emit("glucose",1,at,chemistry.find_module("digestion"))
	chemistry.emit("nad",0.1,at)
	chemistry.emit("adp",2,at)
	var enzyme: Dictionary = chemistry.particles[0]
	chemistry._react(cell,node,enzyme,1)
	check.call(is_equal_approx(chemistry.amount("glucose"),0) and is_equal_approx(chemistry.amount("pyruvate"),1),"Glycolysis consumes nearby glucose particles and produces pyruvate particles")
	check.call(is_equal_approx(cell.energy,2) and is_equal_approx(chemistry.amount("adp"),0),"ATP production converts actual nearby ADP particles")
	check.call(is_equal_approx(chemistry.amount("nad"),0) and is_equal_approx(chemistry.amount("nadh"),0.1),"Redox-carrier particles cycle without duplication")
	cell = empty()
	chemistry = cell.chemistry
	node = chemistry.node_at(chemistry.find_module("glycolysis"))
	at = chemistry.site(node)
	chemistry.emit("catalyst",0.025,at,node.id,node.id)
	chemistry.emit("glucose",1,Vector2(-45,-40),chemistry.find_module("digestion"))
	chemistry.emit("nad",0.1,at)
	chemistry.emit("adp",2,at)
	chemistry._react(cell,node,chemistry.particles[0],1)
	check.call(cell.energy==0 and chemistry.amount("glucose")==1,"Connected pathways cannot consume spatially distant reactant particles")
	var snapshot: Array = chemistry.particles.duplicate(true)
	chemistry.disconnect_route(chemistry.find_module("digestion"),node.id,"glucose")
	chemistry.connect_route(chemistry.find_module("digestion"),node.id,"glucose")
	check.call(chemistry.particles==snapshot,"Rewiring never transports or changes particles")
	var config: Dictionary = chemistry.configuration()
	config.nodes[0].allocation = 5
	var accepted: Dictionary = chemistry.configuration()
	check.call(chemistry.load_configuration(config)!="" and chemistry.configuration()==accepted,"Invalid blueprint leaves the last valid configuration intact")
	cell = empty()
	chemistry=cell.chemistry
	chemistry.emit("atp",5,Vector2(40,0))
	var spent: float = chemistry.spend_atp(1,Vector2(-40,0),8)
	check.call(spent==0 and cell.energy==5,"A chemical consumer cannot spend distant ATP")
	var total_carrier: float = chemistry.amount("atp")+chemistry.amount("adp")
	chemistry.spend_atp(1,Vector2(40,0),8)
	check.call(is_equal_approx(chemistry.amount("atp")+chemistry.amount("adp"),total_carrier),"ATP spending returns real ADP without losing carriers")
	cell = empty()
	chemistry=cell.chemistry
	at=cell.local_point(0)*0.70
	chemistry.emit("food",1,at)
	chemistry.emit("atp",8,at)
	for i in 180: chemistry.advance(cell,1.0/60)
	check.call(chemistry.amount("food")<1 and chemistry.amount("glucose")>0,"Food-vacuole acidification and local enzymes digest real particles")
	cell=empty()
	chemistry=cell.chemistry
	at=cell.local_point(0)*0.70
	chemistry.emit("food",1,at,-1,-1,0)
	chemistry.emit("atp",8,at)
	for i in 180: chemistry.advance(cell,1.0/60)
	check.call(chemistry.amount("glucose")==0 and chemistry.amount("salvage")>0,"Oxidized recycled material does not regain free fuel")
	cell=empty()
	chemistry=cell.chemistry
	cell.biomass=20
	var prior: float=cell.organic_mass()
	var id: int=chemistry.add_module("autocatalysis",cell)
	check.call(id>=0 and absf(cell.organic_mass()-prior)<0.0001,"Installing an experimental catalyst transfers paid tissue into real proteins")
	check.call(chemistry.amount("catalyst_a")>0 and chemistry.amount("catalyst_b")>0,"Autocatalytic seed is represented by actual particles")
	var before_recycle: float=cell.organic_mass()
	chemistry.remove_module(id,cell)
	check.call(absf(cell.organic_mass()-before_recycle)<0.0001,"Recycling retains reactor material and experimental particles")
	cell=empty()
	check.call(not cell.add_organ("offensive",0),"Removed spikes cannot be constructed")
	check.call(cell.add_organ("poreforming",0,"graze",false),"Chemical gland is an available paid anatomy type")
	var initial: float=cell.organic_mass()
	check.call(Surface.bind(cell,11,0.03,0),"A surface tag binds locally")
	for i in 4: check.call(Surface.bind(cell,12,0.0375,0),"Aligned pore subunit adds finite bound material")
	check.call(is_equal_approx(cell.surface_material(),0.18),"Surface complex retains all incoming material")
	cell.energy=0
	var hp: float=cell.health
	Surface.advance(cell,0.1)
	check.call(cell.health<hp or cell.organs[0].hp<cell.organs[0].max_hp,"A completed chemical pore damages the ordinary membrane/armor")
	cell=empty()
	Surface.bind(cell,11,0.03,0)
	Surface.bind(cell,12,0.0375,0)
	check.call(Surface.bind(cell,7,0.06,0),"Inhibitor caps an unfinished pore")
	Surface.advance(cell,0.1)
	check.call(cell.surface_complexes.is_empty() and is_equal_approx(cell.waste,0.1275),"Inhibition returns every bound packet's material to waste")

	cell=empty()
	chemistry=cell.chemistry
	chemistry.emit("atp",4,Vector2(30,0))
	var carriers: float=chemistry.amount("atp")+chemistry.amount("reserved_atp")+chemistry.amount("adp")
	chemistry.reserve_atp(2,true)
	check.call(is_equal_approx(cell.energy,2) and is_equal_approx(cell.brood_energy,2),"Offspring ATP reserves consist of physical particles")
	chemistry.reserve_atp(2,false)
	check.call(is_equal_approx(cell.energy,4) and is_equal_approx(chemistry.amount("atp")+chemistry.amount("reserved_atp")+chemistry.amount("adp"),carriers),"Reserve release neither duplicates nor hydrolyzes carrier particles")
	var parent=empty()
	parent.chemistry.emit("pyruvate",1,Vector2(20,0))
	var child=empty()
	var transferred: float=child.chemistry.partition(parent.chemistry,0.25)
	check.call(is_equal_approx(transferred,0.25) and is_equal_approx(parent.chemistry.amount("pyruvate")+child.chemistry.amount("pyruvate"),1),"Division partitions actual metabolites exactly once")
	cell=empty()
	chemistry=cell.chemistry
	at=Vector2(0.02,0.62)*cell.radius
	chemistry.emit("water",0.2,at)
	chemistry.emit("atp",1,at)
	var water_before: float=chemistry.amount("water")
	chemistry._osmosis(cell,0.1,100)
	check.call(chemistry.amount("water")<water_before and chemistry.expelled>0 and cell.energy<1,"Contractile vacuoles consume local water particles and pay actual ATP")
	var sim=preload("res://tests/pheromones.gd").isolated()
	cell=sim.player
	cell.chemistry.emit("pyruvate",1,Vector2(12,4))
	cell.chemistry.emit("nad",2,Vector2(10,5))
	var matter: float=cell.organic_mass()
	sim._die(cell)
	var released:=0.0
	var pyruvate:=0.0
	var atp:=0.0
	for packet in sim.particles:
		if packet.alive:
			released+=packet.amount*Catalog.material(packet.kind)
			if packet.kind==14: pyruvate+=packet.amount
			if packet.kind==22: atp+=packet.amount
	check.call(absf(released-matter)<0.0001 and cell.chemistry.particles.is_empty(),"Lysis releases tissue and physical chemicals once with correct material weights")
	check.call(is_equal_approx(pyruvate,1) and atp>0,"Lysis retains metabolite identity instead of turning every chemical into food")
	var released_count: int=sim.particles.size()
	sim._die(cell)
	check.call(sim.particles.size()==released_count,"Repeated lysis cannot release duplicate chemical particles")

	for pooled in [false,true]:
		sim=preload("res://tests/pheromones.gd").isolated()
		if pooled and sim.kernels==null: continue
		var prey=Cell.new(42,sim.player.position+Vector2(180,0))
		prey.activity=1
		sim.cells.append(prey)
		var contact: Vector2=prey.position+prey.local_point(0)
		if pooled: sim.enable_particle_pool()
		for kind in [11,12,12,12,12]:
			sim._emit_aimed(kind,contact,Vector2.LEFT,0,0.03 if kind==11 else 0.0375,sim.player.id)
		sim._surface_contacts()
		check.call(prey.surface_complexes.size()==1 and prey.surface_complexes[0].source==sim.player.id,"Surface assembly preserves secretion owner in both CPU ownership paths")
		Surface.advance(prey,0.1,sim)
		check.call(sim.evolution.exposures.pore>0,"Actual pore damage credits the chemical source for adaptive responses")

	for pooled in [false,true]:
		sim=preload("res://tests/pheromones.gd").isolated()
		if pooled and sim.kernels==null: continue
		cell=sim.player
		sim.camera_follows_player=false
		sim.camera_position=Vector2.ZERO
		sim.view_half=Vector2(10,10)
		cell.activity=0
		Surface.bind(cell,11,0.03,0,999)
		Surface.bind(cell,12,0.0375,0,999)
		if pooled: sim.enable_particle_pool()
		sim._emit_aimed(7,cell.position+cell.local_point(0),Vector2.LEFT,0,0.06,cell.id)
		sim.offscreen_ecology._exposure(sim,cell,100)
		check.call(cell.surface_complexes[0].capped,"Own-family inhibitors protect a hidden cell in both ownership paths")

	cell=empty()
	chemistry=cell.chemistry
	node=chemistry.node_at(chemistry.find_module("glycolysis"))
	at=chemistry.site(node)
	chemistry.emit("catalyst",0.025,at,node.id,node.id)
	chemistry.emit("glucose",1,at,chemistry.find_module("digestion"))
	chemistry.emit("nad",0.1,at)
	chemistry.emit("adp",2,at)
	chemistry.advance(cell,0.5,100)
	check.call(is_equal_approx(chemistry.flux.get(node.id,0),cell.processed/0.5),"Coarse graph rate reports actual reaction throughput over the whole biology interval")

	cell=empty()
	chemistry=cell.chemistry
	chemistry.emit("glucose",0.1,Vector2(-40,0),1)
	var remote: Dictionary=chemistry.particles[0]
	var position_before: Vector2=remote.p
	chemistry.emit("glucose",0.1,Vector2(30,0),1)
	chemistry.emit("glucose",0.1,Vector2(30,0),1)
	check.call(is_equal_approx(remote.amount,0.1) and remote.p==position_before and is_equal_approx(chemistry.amount("glucose"),0.3),"Local product coalescence cannot absorb material into a distant packet")
