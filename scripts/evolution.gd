extends RefCounted
## Persistent discoveries and free division mutations; no scripted expedition.
const Genes=preload("res://scripts/mutations.gd")
var enabled:=true
var sandbox:=true
var clock:=0.0
var points:=0
var offers: Array[String]=[]
var learned: Array[String]=[]
var division_offers: Array[String]=[]
var division_count:=0
var chosen:=true
var random:=RandomNumberGenerator.new()
var status:="growing"
var ending:=""
var light_factor:=1.0
var tide:=0
var challenge:=""
var challenge_result:=""
var offspring_id:=-1
var viable_seconds:=0.0
var completed: Array=[]
var spending: Array=[]
var exposures:={"toxin":0.0,"pore":0.0,"acid":0.0,"photo":0.0}
var arrival_budget:=0
var counter_budget:=0
var resistance:=""
var resistance_clock:=0.0
const TIDE_SECONDS:=INF
const TIDES:=[{"title":"Persistent pond","forecast":"Build, feed and grow your family."}]
func _init(seed_number: int=0) -> void:random.seed=seed_number ^ 0x46ac71
func terminal() -> bool:return false
func divided(_cell) -> bool:
	# Called only at the committed paid birth, never on hatch, follow or login.
	division_count+=1
	if random.randf()>=0.10:return false
	var pool: Array=[]
	for gene in Genes.DATA:
		if gene not in Genes.LIGHT_ADAPTATIONS and gene not in learned and gene not in division_offers:pool.append(gene)
	if pool.is_empty():return false
	# Offers persist until accepted, including across disconnect and restart.
	division_offers.append(pool[random.randi_range(0,pool.size()-1)])
	return true

func accept_division_offer(gene: String) -> bool:
	if terminal() or gene not in division_offers or not Genes.DATA.has(gene):return false
	division_offers.erase(gene)
	if gene not in learned:learned.append(gene)
	return true


func choose(identity: String) -> bool:
	if identity not in offers or identity in learned:return false
	learned.append(identity);offers.erase(identity);return true
func accept_challenge(_kind: String,_cell) -> bool:return false
func record(kind: String,amount: float) -> void:
	if exposures.has(kind):exposures[kind]+=maxf(0,amount)
func fail(_reason: String) -> void:pass
func crisis() -> int:return -1
func observe_successor(_cell) -> void:pass
func is_viable(cell) -> bool:return not cell.dead and cell.health>0
func advance(dt: float,_sim) -> void:clock+=dt
func objective(_sim) -> String:return "Persistent pond · build, feed and grow your family."
func goal_key(_sim) -> String:return "persistent"
func newcomer(_cell,_sim) -> void:pass
func forecast() -> String:return "Your family continues while the pond is running."
