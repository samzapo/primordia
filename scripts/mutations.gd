extends RefCounted
## One named specialization per organ. All numerical effects use shared cell rules.
const DATA := {
	"economical_flagellum":{"title":"Economical stroke","kind":"propulsion","text":"Half propulsion ATP; 20% less thrust.","thrust":0.8,"motion_cost":0.5},
	"layered_cortex":{"title":"Layered cortex","kind":"protection","text":"60% more organ health; extra tissue adds mass.","health":1.6},
	"barbed_spike":{"title":"Barbed spike","kind":"offensive","text":"50% more damage per ATP; attacks cost 70% more ATP.","damage":1.5,"attack_cost":1.7},
	"recuperative_repair":{"title":"Recuperative repair","kind":"regenerative","text":"60% stronger repair; 40% more ATP per repair.","repair":1.6,"repair_cost":1.4},
	"wide_pore":{"title":"Wide intake","kind":"feeding","text":"30% wider intake and stronger suction; extra upkeep.","intake":1.3,"suction":1.3,"upkeep":0.10},
	"enzyme_pore":{"title":"Concentrated digestion","kind":"feeding","text":"Twice the enzyme secretion; 60% more ATP per packet, slower dispersal.","secretion":2.0,"secretion_cost":1.6,"dispersal":0.5},
	"long_receptor":{"title":"Long-range flight","kind":"sensing","text":"50% more sensing range; extra sensing upkeep.","sense":1.5,"upkeep":0.08},
	"sun_leaf":{"title":"Sun specialist","kind":"photosynthesis","text":"70% faster fixation in bright water; 40% slower below half light.","sun":1.7,"shade":0.6},
	"shade_leaf":{"title":"Shade specialist","kind":"photosynthesis","text":"60% faster fixation below half light; 30% slower in bright water.","sun":0.7,"shade":1.6},
	"pulse_vesicle":{"title":"Pulsed toxin","kind":"toxin","text":"2.5x automatic bursts and their costs; twice the recovery time.","burst":2.5,"cooldown":2.0},
	"dense_antitoxin":{"title":"Dense neutralization","kind":"neutralizing","text":"70% more antitoxin secretion; 90% more ATP per packet.","secretion":1.7,"secretion_cost":1.9},
	"acid_pulse":{"title":"Acid pulse","kind":"acidifying","text":"70% more acid secretion; 90% more ATP per packet. You share the acid exposure.","secretion":1.7,"secretion_cost":1.9}
}
static func factor(organ: Dictionary, key: String, fallback: float = 1.0) -> float:
	return float(DATA.get(organ.get("mutation",""),{}).get(key,fallback))

static func price(organ: Dictionary) -> float:
	return 12.0*organ.scale*organ.scale

static func adaptation_price(organ: Dictionary) -> int:
	return 2*maxi(1,ceili(organ.scale*organ.scale-0.000001))
