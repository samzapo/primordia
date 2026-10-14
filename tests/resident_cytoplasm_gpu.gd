extends SceneTree
const Cell=preload("res://scripts/cell.gd")
const GPU=preload("res://scripts/resident_particles.gd")
const Cytoplasm=preload("res://scripts/resident_cytoplasm.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var beacon:=ColorRect.new();beacon.size=Vector2(8,8);root.add_child(beacon)
	await process_frame;await process_frame
	var gpu=GPU.new();gpu.rd=RenderingServer.get_rendering_device()
	var cell=Cell.new(42,Vector2(100,100));var chem=cell.chemistry
	var matter: float=cell.organic_mass();var potential: float=chem.potential()+chem.heat
	var before: Array=chem.particles.duplicate(true)
	var component=Cytoplasm.new()
	var ok: bool=component.attach(gpu,chem,cell)
	check(ok,"resident cytoplasm compiles on the main hardware device: "+component.error)
	if not ok:print("CYTOPLASM GPU: %d assertions, %d failures" % [assertions,failures]);quit(1);return
	check(chem.particles.is_empty() and chem.accelerator==component,"GPU is sole particle owner")
	check(absf(cell.organic_mass()-matter)<.000001,"ownership preserves finite material")
	check(absf(chem.potential()+chem.heat-potential)<.000001,"ownership preserves finite fuel")
	var query: float=chem._local_amount("atp",Vector2.ZERO,1000)
	var paid: float=chem.spend_atp(3,Vector2.ZERO,1000)
	check(absf(paid-minf(3,query))<.000001,"ATP spending returns a finite paid receipt")
	check(absf(chem.amount("atp")+chem.amount("adp")-96)<.000001,"ATP conversion retains carriers")
	check(absf(chem.potential()+chem.heat-potential)<.000001,"ATP conversion accounts heat")
	var tick: int=chem.tick;var started:=Time.get_ticks_usec()
	for i in 60:chem.advance(cell,1.0/60)
	print("cytoplasm 60 detailed steps ms=",(Time.get_ticks_usec()-started)/1000.0," packets=",chem.particle_count()," receipt bytes=",component.readback_bytes," exports=",component.exports)
	check(chem.tick==tick+60,"transport advances exactly one tick per fine step")
	check(component.exports==0,"fine simulation never downloads a particle pool")
	check(absf(cell.organic_mass()-matter)<.00001,"transport and local chemistry conserve material")
	var state: Array=chem.particle_snapshots()
	check(not state.is_empty(),"explicit detached presentation/checkpoint export")
	for packet in state:
		check(is_finite(packet.amount) and packet.amount>0 and is_finite(packet.fuel),"finite live packet")
	chem.ensure_cpu()
	check(chem.accelerator==null and chem.particles.size()==state.size(),"offscreen handoff has one CPU owner")
	check(absf(cell.organic_mass()-matter)<.00001,"offscreen handoff preserves matter")
	check(Cytoplasm.new().attach(gpu,chem,cell),"promotion resumes the existing state")
	check(chem.tick==tick+60,"promotion does not replay elapsed time")
	chem.ensure_cpu()
	await deeper(gpu)
	print("CYTOPLASM GPU: %d assertions, %d failures" % [assertions,failures]);beacon.queue_free();await process_frame;quit(0 if failures==0 else 1)

func fresh():
	var cell=Cell.new(19,Vector2.ZERO);var chem=cell.chemistry
	chem.particles=[];chem.bins.clear();chem.totals.clear();chem.vacuoles=[]
	for node in chem.nodes:node.enabled=false
	return cell

func deeper(gpu) -> void:
	var cell=fresh();var chem=cell.chemistry
	var node=chem.node_at(chem.find_module("glycolysis"));node.enabled=true
	var at: Vector2=chem.site(node)
	chem.emit("catalyst",.025,at,node.id,node.id)
	for pair in [["glucose",2.0],["nad",.001],["adp",10.0]]:chem.emit(pair[0],pair[1],at)
	var material: float=cell.organic_mass();var energy: float=chem.potential()+chem.heat
	check(Cytoplasm.new().attach(gpu,chem,cell),"local reaction fixture owns resident particles")
	chem.advance(cell,.01)
	check(absf(chem.amount("pyruvate")-.01)<.000001,"local NAD limits the actual glycolytic extent")
	check(absf(chem.amount("atp")-.02)<.000001 and absf(chem.amount("nadh")-.001)<.000001,"reaction produces finite ATP and bound cofactor particles")
	check(absf(cell.organic_mass()-material)<.000001,"local reaction conserves matter")
	check(absf(chem.potential()+chem.heat-energy)<.000001,"local reaction conserves potential plus heat")
	var graph=preload("res://scripts/network/state_codec.gd").new().capture(cell)
	var restored=preload("res://scripts/network/state_codec.gd").new().restore(graph)
	check(chem.particles.is_empty() and restored.chemistry.particles.size()==chem.particle_count(),"checkpoint is detached without moving GPU authority")
	check(absf(restored.organic_mass()-material)<.000001,"checkpoint roundtrip retains finite intracellular quantities")
	chem.ensure_cpu()
	# Route configuration does not transport distant or incompatible feedstock.
	for scenario in ["distant","unrouted"]:
		cell=fresh();chem=cell.chemistry;node=chem.node_at(chem.find_module("glycolysis"));node.enabled=true;at=chem.site(node)
		chem.emit("catalyst",.025,at,node.id,node.id);chem.emit("nad",1,at);chem.emit("adp",10,at)
		chem.emit("glucose",2,at+Vector2(40,0) if scenario=="distant" else at,chem.find_module("respiration") if scenario=="unrouted" else -1)
		check(Cytoplasm.new().attach(gpu,chem,cell),"promote "+scenario+" fixture")
		chem.advance(cell,.001)
		check(chem.amount("pyruvate")==0,"physical locality and route compatibility: "+scenario)
		chem.ensure_cpu()
	# A realistic-size dense cytoplasm, with no copied particle graph per tick.
	cell=fresh();chem=cell.chemistry
	for i in 4000:
		var pos: Vector2=Vector2.from_angle(i*2.399963)*(.3+fposmod(i*.61803399,.6))*cell.radius
		var packet: Dictionary={"id":i+1099511627776,"species":"nad","amount":.05,"fuel":0.0,"p":pos,"previous":pos,"v":Vector2.ZERO,"angle":0.0,"source":-1,"compartment":-1,"alive":true}
		chem.particles.append(packet);chem._index(packet)
	chem.next_packet=1099511632000;chem.totals["nad"]=200.0
	check(Cytoplasm.new().attach(gpu,chem,cell),"dense fixture promotion")
	var component=chem.accelerator;var started:=Time.get_ticks_usec()
	for i in 60:chem.advance(cell,1.0/60)
	print("dense cytoplasm 4000 packets / 60 fine steps ms=",(Time.get_ticks_usec()-started)/1000.0)
	check(component.exports==0,"dense fine chemistry has only compact receipts")
	check(absf(chem.amount("nad")-200)<.000001,"dense transport retains all finite cofactor")
	check(chem.particle_snapshots()[0].id==1099511627776,"64-bit particle identities survive compute and export")
	chem.ensure_cpu()
	# Overflow retries on device, publishes one successful receipt, and never
	# consumes an input twice. Force a small capacity for this bounded fixture.
	cell=fresh();chem=cell.chemistry
	for i in 4090:
		var packet: Dictionary={"id":i,"species":"oxygen","amount":40.0,"fuel":0.0,"p":Vector2.ZERO,"previous":Vector2.ZERO,"v":Vector2.ZERO,"angle":0.0,"source":-1,"compartment":-1,"alive":true}
		chem.particles.append(packet);chem._index(packet)
	chem.next_packet=4090;chem.totals["oxygen"]=4090*40.0
	component=Cytoplasm.new();component.prepare(chem,cell);component.capacity=4096
	var packed=component._pack(chem.particles);var control=component._control(chem);var anatomy=component._anatomy(cell);var ok: Array=[false]
	RenderingServer.call_on_render_thread(func():ok[0]=component.initialize(gpu.rd,packed,control,anatomy);component.semaphore.post());component.semaphore.wait()
	check(ok[0],"bounded overflow fixture initialized")
	chem.particles=[];chem.bins.clear();chem.accelerator=component;component.texture.texture_rd_rid=component.image
	component.command(12)
	component._capacity_limit=4096
	var request:=PackedFloat64Array();request.resize(32);request[0]=1;request[1]=10000;request[6]=-1;request[7]=-1;request[8]=-1;request[10]=component.species.find("nad");request[13]=4294967295;request[14]=4294967295;request[15]=4294967295;request[16]=4294967295
	RenderingServer.call_on_render_thread(component._execute.bind(request.to_byte_array(),PackedByteArray(),1));component.semaphore.wait()
	check(not component.error.is_empty() and component.snapshot().size()==4090 and component.value(32+component.species.find("nad"))==0,"hard capacity failure restores the last complete device transaction")
	check(absf(component.value(64))<.000001 and absf(chem.amount("oxygen")-4090*40.0)<.000001,"failed transaction retains old derived inventories and publishes no partial receipt")
	component.error="";component._capacity_limit=component.MAX_CAPACITY
	chem.emit("nad",10000,Vector2.ZERO)
	check(component.grows==1 and absf(chem.amount("nad")-10000)<.000001,"overflow rolls back and retries one funded emission")
	check(absf(chem.amount("oxygen")-4090*40.0)<.000001,"device growth preserves prior inventory")
	chem.ensure_cpu()
	# An empty GPU export must never resurrect stale storage slots.
	cell=fresh();chem=cell.chemistry
	check(Cytoplasm.new().attach(gpu,chem,cell),"empty owner initialized")
	check(chem.particle_snapshots().is_empty(),"zero particles exports an empty graph")
	chem.ensure_cpu()

	# Photosynthesis spends real local carbon and ADP and returns one receipt.
	cell=fresh();chem=cell.chemistry;node=chem.node_at(chem.find_module("photosynthesis"));node.enabled=true;at=chem.site(node)
	chem.emit("catalyst",.025,at,node.id,node.id);chem.emit("carbon",2,at);chem.emit("adp",10,at)
	material=cell.organic_mass();var solar: float=chem.solar_work;energy=chem.potential()+chem.heat+cell.biomass*7.5
	check(Cytoplasm.new().attach(gpu,chem,cell),"photosynthetic resident fixture")
	check(absf(chem.accelerator.command(10,.5,at,15)-.5)<.000001,"local carbon limits a single photosynthetic receipt")
	check(absf(chem.amount("carbon")-1.5)<.000001 and absf(chem.amount("glucose")-.325)<.000001 and absf(chem.amount("oxygen")-1.25)<.000001,"photosynthesis produces finite glucose and oxygen")
	check(absf(cell.organic_mass()-material)<.000001,"photosynthesis includes stationary biomass in material accounting")
	check(absf(chem.potential()+chem.heat+cell.biomass*7.5-energy-(chem.solar_work-solar))<.000001,"photosynthesis records actual solar work")
	chem.ensure_cpu()
	cell=fresh();chem=cell.chemistry;node=chem.node_at(chem.find_module("osmosis"));node.enabled=true
	at=Vector2(.02,.62)*cell.radius;chem.emit("water",1.5,at);chem.emit("atp",1,at)
	check(Cytoplasm.new().attach(gpu,chem,cell),"contractile resident fixture")
	chem.advance(cell,.1)
	check(chem.expelled>0 and chem.amount("adp")>0,"contractile pump expels local water and consumes local ATP")
	check(absf(chem.amount("atp")+chem.amount("adp")-1)<.000001,"pumping retains adenylate carriers")
	chem.ensure_cpu()
	cell=fresh();chem=cell.chemistry;node=chem.node_at(chem.find_module("digestion"));node.enabled=true
	at=cell.local_point(0)*.65;chem.emit("food",1,at,-1,-1,7.5);chem.emit("atp",30,at)
	material=cell.organic_mass();energy=chem.potential()+chem.heat+(cell.biomass+chem._vacuole_material())*7.5
	check(Cytoplasm.new().attach(gpu,chem,cell),"digestive resident fixture")
	chem.advance(cell,1.5)
	check(chem.amount("glucose")>0 and chem.amount("food")<1,"finite vacuole digests food at its local catalyst")
	check(absf(cell.organic_mass()-material)<.00001,"digestion retains tissue, vacuole and particle matter")
	check(absf(chem.potential()+chem.heat+(cell.biomass+chem._vacuole_material())*7.5-energy)<.00001,"digestion retains fuel, tissue potential and heat")
	chem.ensure_cpu()
	# Sparse metadata survives explicit exports without narrowing its 64-bit facts.
	cell=fresh();chem=cell.chemistry;chem.emit("nad",1,Vector2.ZERO)
	chem.particles[0].id=1099511627776;chem.particles[0].source=1099511627888;chem.particles[0].compartment=1099511627999;chem.particles[0]["marker"]={"fixture":"retained"}
	check(Cytoplasm.new().attach(gpu,chem,cell),"64-bit metadata fixture")
	var packet: Dictionary=chem.particle_snapshots()[0]
	check(packet.id==1099511627776 and packet.source==1099511627888 and packet.compartment==1099511627999,"identity, source and compartment remain exact 64-bit facts")
	check(packet.get("marker",{})=={"fixture":"retained"},"sparse non-physical metadata survives GPU ownership")
	chem.emit("nad",1,Vector2(20,0),1099511628001,1099511628017,0)
	check(chem.particle_snapshots().any(func(item):return item.source==1099511628001 and item.compartment==1099511628017),"resident admissions keep full-width source and compartment facts")
	chem.ensure_cpu()

	var sim=preload("res://scripts/simulation.gd").new(81,0,false)
	cell=fresh();chem=cell.chemistry;sim.cells=[cell];sim.player=cell
	at=cell.local_point(0)*.98;chem.emit("oxygen",100,at);chem.emit("glucose",20,at)
	check(Cytoplasm.new().attach(gpu,chem,cell),"membrane transfer fixture")
	chem.excrete(sim,cell,.1)
	var oxygen:=0.0;var glucose:=0.0;var capacity:=0.0
	for outside in sim.particles:
		if outside.kind==1:oxygen+=outside.amount
		if outside.kind==0:glucose+=outside.amount;capacity+=outside.capacity
	check(oxygen>0 and glucose>0,"actual local packets cross the membrane")
	check(absf(oxygen+chem.amount("oxygen")-100)<.000001 and absf(glucose+chem.amount("glucose")-20)<.000001,"membrane receipts transfer each finite amount once")
	check(absf(capacity-glucose)<.000001,"external nutrient retains the exported intracellular fuel")
	var total: float=cell.organic_mass()
	for outside in sim.particles:total+=outside.amount*sim.Catalog.material(outside.kind)
	sim._die(cell)
	var released:=0.0
	for outside in sim.particles:released+=outside.amount*sim.Catalog.material(outside.kind)
	check(chem.accelerator==null and chem.particles.is_empty(),"lysis releases GPU ownership before destroying the cell")
	check(absf(released-total)<.00001,"resident lysis releases all finite material without duplication")

	cell=fresh();chem=cell.chemistry;cell.biomass=30;material=cell.organic_mass()
	check(Cytoplasm.new().attach(gpu,chem,cell),"resident construction fixture")
	var installed: int=chem.add_module("autocatalysis",cell)
	check(installed>=0 and chem.accelerator!=null and chem.particles.is_empty(),"paid catalyst construction stays GPU resident")
	check(absf(cell.organic_mass()-material)<.000001,"installed reactor and catalyst seeds are paid from real tissue")
	var preview=chem.clone_for(Cell.new())
	check(chem.accelerator!=null and preview.particles.size()==chem.particle_count(),"detached editing preview does not replace the authority")
	check(chem.remove_module(installed,cell),"structural removal takes exclusive CPU ownership")
	check(chem.accelerator==null and absf(cell.organic_mass()-material)<.000001,"removal retains all refund, waste and catalyst material")

	cell=fresh();chem=cell.chemistry;chem.emit("nad",1,Vector2.ZERO)
	check(Cytoplasm.new().attach(gpu,chem,cell),"native GPU presentation fixture")
	component=chem.accelerator
	var view=preload("res://scripts/cytoplasm_view.gd").new();root.add_child(view)
	view.position=Vector2(128,128);view.scale=Vector2.ONE*12;view.sync(chem,1)
	for frame in 4:await process_frame
	var resident_image: Image=root.get_texture().get_image()
	check(component.exports==0,"native instanced drawing samples resident texture without pose export")
	chem.ensure_cpu();view.sync(chem,1)
	for frame in 4:await process_frame
	var cpu_image: Image=root.get_texture().get_image();var error_sum:=0.0;var colored:=0
	for x in range(100,170):
		for y in range(100,170):
			var a:=resident_image.get_pixel(x,y);var b:=cpu_image.get_pixel(x,y)
			error_sum+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
			if a.r>.3 and a.b>.4:colored+=1
	print("native cytoplasm instancing pixels=",colored," mean RGB error=",error_sum/4900)
	check(colored>20 and error_sum/4900<.01,"native GPU and snapshot instancing draw the same colored finite particle")
	view.queue_free();await process_frame

	# Differential chemistry at a well-supplied local site. This checks catalog
	# stoichiometry and finite receipts, without asserting gameplay viability.
	for definition in chem.Catalog.data().modules:
		if definition.has("action"):continue
		cell=fresh();chem=cell.chemistry;node=chem.node_at(chem.find_module(definition.id));node.enabled=true;at=chem.site(node)
		chem.emit("catalyst",.025,at,node.id,node.id)
		for key in definition.inputs:chem.emit(key,float(definition.inputs[key])*3,at)
		chem.emit("atp",100,at);chem.emit("adp",100,at)
		var reference=Cell.new(19);reference.chemistry=chem.clone_for(reference)
		var reference_node=reference.chemistry.node_at(node.id)
		reference.chemistry._react(reference,reference_node,reference.chemistry.particles[0],.001)
		check(Cytoplasm.new().attach(gpu,chem,cell),"resident recipe "+definition.id)
		chem.advance(cell,.001)
		for key in chem.Catalog.data().species:
			if key=="water":continue # Solvent lottery is exercised separately.
			check(absf(chem.amount(key)-reference.chemistry.amount(key))<.000001,"finite reference stoichiometry "+definition.id+" / "+key)
		check(absf(cell.biomass-reference.biomass)<.000001 and absf(chem.heat-reference.chemistry.heat)<.000001,"stationary product and heat receipt "+definition.id)
		chem.ensure_cpu()

	# Two foods with different fuel straddle a spatial bin. The digestive
	# receipt must consume the same physical candidate as the CPU reference.
	cell=fresh();chem=cell.chemistry;node=chem.node_at(chem.find_module("digestion"));node.enabled=true
	chem.vacuoles=[{"id":1000000,"p":Vector2(0,25),"radius":8.0,"acid":1.0,"material":.0125,"age":0.0}]
	chem.emit("food",1,Vector2(3,25),-1,1000000,0);chem.emit("food",1,Vector2(-3,25),-1,1000000,7.5)
	chem.emit("catalyst",.0125,Vector2(0,25),node.id,1000000);chem.emit("atp",100,Vector2(0,25))
	var digestion_reference=Cell.new(19);digestion_reference.chemistry=chem.clone_for(digestion_reference)
	digestion_reference.chemistry._digest(digestion_reference,.01)
	check(Cytoplasm.new().attach(gpu,chem,cell),"ordered spatial digestion fixture")
	chem.advance(cell,.01)
	check(absf(chem.amount("glucose")-digestion_reference.chemistry.amount("glucose"))<.000001 and absf(chem.amount("salvage")-digestion_reference.chemistry.amount("salvage"))<.000001,"spatial bins retain the reference digestive fuel and candidate order")
	chem.ensure_cpu()
