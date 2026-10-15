extends RefCounted
const Cell=preload("res://scripts/cell.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
static func run(check: Callable) -> void:
	var cell=Cell.new()
	check.call(cell.chemistry.particle_count()==0,"A new cell has no seeded molecular cloud")
	var mass: float=cell.organic_mass()
	var energy: float=cell.energy
	cell.chemistry.receive(0,3,2,cell.position+cell.local_point(0))
	check.call(is_equal_approx(cell.organic_mass()-mass,3) and is_equal_approx(cell.raw_fuel,15),"Intake transfers actual nutrient material and its finite fuel")
	mass=cell.organic_mass();energy=cell.energy
	cell.chemistry.advance(cell,1)
	check.call(cell.energy>energy and cell.biomass>18 and cell.waste>0,"Digestion directly credits numeric ATP/biomass and retains waste")
	check.call(absf(cell.organic_mass()-mass)<.000001,"Digestion conserves represented organic material")
	check.call(absf(cell.chemistry.potential()+(cell.biomass-18)*7.5+cell.energy-energy-15)<.000001,"Digestion cannot credit ATP beyond its finite fuel after retaining tissue")
	check.call(cell.chemistry.particles.all(func(p):return p.species in ["food","waste"]),"Only food/waste parcels inhabit cytoplasm")
	var sim=preload("res://scripts/simulation.gd").new(41,0,false)
	sim.cells=[cell];sim.player=cell;sim.particles=[]
	for i in 300:
		cell.chemistry.advance(cell,.1);cell.chemistry.excrete(sim,cell,.1)
	var released:=0.0
	for p in sim.particles:
		check.call(p.kind==2,"Only waste is expelled by digestion")
		released+=p.amount
	check.call(cell.substrate==0 and cell.waste<.000001 and released>0,"A waste-filled vacuole travels to the cytoproct and empties")
	check.call(absf(cell.organic_mass()+released-mass)<.000001,"Expulsion transfers material once into the external pool")
	energy=cell.energy;mass=cell.organic_mass()
	cell.chemistry.receive(0,1,0,cell.position+cell.local_point(0));cell.chemistry.advance(cell,5)
	check.call(cell.energy==energy and absf(cell.organic_mass()-mass-1)<.000001,"Spent nutrients cannot regain ATP or create tissue")
	cell.energy=17;cell.brood_energy=3;cell.reserve(2);cell.reserve(-2)
	check.call(cell.energy==17 and cell.brood_energy==3,"Numeric reserve transfers neither duplicate nor destroy ATP")
	for i in 1000:cell.chemistry.emit("food",.01,Vector2.from_angle(i)*25)
	check.call(cell.chemistry.particle_count()<=24,"Weighted carriers bound parcel count without losing material")
	var copy=Codec.new().restore(Codec.new().capture(cell))
	check.call(copy.energy==cell.energy and copy.brood_energy==cell.brood_energy and absf(copy.organic_mass()-cell.organic_mass())<.000001,"Numeric resources and finite vacuoles survive checkpoint roundtrip")
	var graph:=Codec.new().capture(cell)
	for record in graph.objects:
		if record.kind=="cell":record.fields.erase("energy");record.fields.erase("brood_energy")
		if record.kind=="chemistry":
			record.fields.erase("model_version")
			record.fields.particles={"$array":[{"id":0,"species":"atp","amount":11.0,"fuel":0.0,"p":Vector2.ZERO,"alive":true},{"id":1,"species":"reserved_atp","amount":4.0,"fuel":0.0,"p":Vector2.ZERO,"alive":true},{"id":2,"species":"glucose","amount":2.0,"fuel":15.0,"p":Vector2.ZERO,"alive":true}],"builtin":0}
	var migrated=Codec.new().restore(graph)
	check.call(migrated.energy==11 and migrated.brood_energy==4 and migrated.substrate==2 and migrated.raw_fuel==15,"Legacy ATP/reserves become numbers; retained metabolites become finite food")
	var again=Codec.new().restore(Codec.new().capture(migrated))
	check.call(again.energy==11 and again.brood_energy==4 and again.substrate==2,"Migration is idempotent across later checkpoints")
