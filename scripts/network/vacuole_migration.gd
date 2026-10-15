extends RefCounted
## One-way archived migration. Preserve organic mass, finite fuel and paid ATP.
static func apply(cell) -> Dictionary:
	var chem=cell.chemistry
	var material: float=chem.reactor_mass
	for vacuole in chem.vacuoles:material+=float(vacuole.get("material",0))
	var fuel:=0.0
	var atp:=0.0
	var reserve:=0.0
	var food:=0.0
	var waste:=0.0
	var old_count: int=chem.particles.size()
	for packet in chem.particles:
		if not packet.alive:continue
		if packet.species=="atp":atp+=packet.amount
		elif packet.species=="reserved_atp":reserve+=packet.amount
		var weight: float=chem.Catalog.data().species[packet.species].material
		var quantity: float=packet.amount*weight
		if quantity<=0:continue
		if packet.fuel>0:food+=quantity;fuel+=packet.fuel
		else:waste+=quantity
	var before_material: float=cell.body+cell.biomass+cell.organ_mass()+cell.brood_mass+cell.surface_material()+material+food+waste
	cell.energy=atp;cell.brood_energy=reserve;cell.biomass+=material
	cell.oxygen=0;cell.carbon=0
	chem.particles=[];chem.nodes=[];chem.edges=[];chem.totals={};chem.vacuoles=[];chem.reactor_mass=0
	chem.presentation_totals={};chem.pending_time=0;chem.coarse_due=-1
	var entry: Vector2=cell.local_point(0)*.7
	if food>0:chem.emit("food",food,entry,-1,-1,fuel)
	if waste>0:chem.emit("waste",waste,cell.local_point(cell.excretion_angle())*.5,-1,-1,0)
	chem.model_version=1
	cell.update_geometry()
	return {"before_material":before_material,"after_material":cell.organic_mass(),"before_packets":old_count,"after_packets":chem.particles.size(),"food":food,"waste":waste,"reclaimed_tissue":material,"fuel":fuel,"atp":atp,"reserved_atp":reserve}
