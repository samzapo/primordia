extends RefCounted
## Explicit computational outflow. Equal removal probability for every exterior kind.
const Catalog=preload("res://scripts/chemistry_catalog.gd")
static func thin(packets: Array,probability: float,random: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary={"removed":0,"loss":0.0,"fuel_loss":0.0}
	if probability<=0:return result
	for packet in packets:
		if not packet.alive or random.randf()>=probability:continue
		result.removed+=1
		result.loss+=float(packet.amount)*Catalog.material(packet.kind)
		if packet.kind==0:result.fuel_loss+=clampf(float(packet.get("capacity",packet.amount)),0,packet.amount)*7.5
		packet.alive=false
	return result

static func add(target: Dictionary,source: Dictionary) -> void:
	for key in ["removed","loss","fuel_loss"]:target[key]=target.get(key,0)+source.get(key,0)
