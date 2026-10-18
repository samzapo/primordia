extends RefCounted
## Saved purchase intent; anatomy, AP and feeding still use the ordinary rules.
const MANUAL_ONLY:=[] # Every currently available organ has an explicit strategy role.
const STRATEGIES:=["manual","hunter","producer","grazer"]
const PRIORITIES:={
 "hunter":["hunting","toxin","propulsion","poreforming","cilia","mitochondrion","protection"],
 "producer":["photosynthesis","protection","mitochondrion","regenerative","neutralizing"],
 "grazer":["cilia","protection","propulsion","regenerative","mitochondrion","sensing"],
}
static func npc_assignments(sim) -> void:
 # Former automatic quotas are retired; all unchosen policies are Manual.
 sim.investment.npc.clear()

static func strategy(sim,cell) -> String:
 if sim.investment.cells.has(cell.id):return sim.investment.cells[cell.id]
 return sim.investment.lineages.get(cell.lineage_id(),"manual")

static func inherit_strategy(sim,parent,child) -> void:
 # Manual is inherited too: birth never opts a player into automatic spending.
 sim.investment.cells[child.id]=strategy(sim,parent)

# Variants are deterministic preferences, never free organs or hidden ecology knowledge.
const VARIANTS:={
 "hunter":[["hunting","toxin","propulsion","poreforming","sensing","protection","mitochondrion","regenerative"],
           ["hunting","poreforming","cilia","counterattack","protection","neutralizing","mitochondrion","regenerative","toxin_sac"]],
 "producer":[["photosynthesis","protection","regenerative","mitochondrion","neutralizing","cilia","sensing","toxin_sac"],
             ["photosynthesis","cilia","neutralizing","mitochondrion","counterattack","regenerative","protection","sensing","toxin_sac"]],
 "grazer":[["cilia","mitochondrion","regenerative","sensing","feeding","protection","neutralizing"],
           ["cilia","neutralizing","regenerative","acidifying","mitochondrion","feeding","sensing","protection"]],
}
static func candidate(sim,cell) -> Dictionary:
 var policy:=strategy(sim,cell)
 if policy not in VARIANTS or cell.id in sim.managed_cells:return {}
 var variant: int=posmod(cell.id*19349663 ^ sim.seed_value*83492791,2)
 var priorities: Array=VARIANTS[policy][variant]
 var best: Dictionary={}
 var score:=-INF
 for index in priorities.size():
  var kind: String=priorities[index]
  var count: int=working(cell,kind)
  var limit: int=4 if kind=="photosynthesis" else 2 if kind in ["feeding","cilia","protection"] else 1
  if count>=limit or not cell.can_fit(kind,0,1,false):continue
  var value: float=(priorities.size()-index)/pow(1+count,1.7)
  if working(cell,priorities[0])==0 and index==0:value+=100
  # Establish a complete working role before duplicating its headline organ.
  if index>0 and count==0:value+=12
  if policy=="hunter" and working(cell,"hunting")>0:
   if working(cell,"toxin")+working(cell,"poreforming")+working(cell,"counterattack")==0 and kind in ["toxin","poreforming"]:value+=70
   if working(cell,"propulsion")+working(cell,"cilia")==0 and kind in ["propulsion","cilia"]:value+=50
  if cell.health<70 or cell.acid_stress>.25:
   if kind=="regenerative" and count==0:value+=40
   if kind=="sensing" and count==0:value+=25
  if kind=="mitochondrion" and cell.oxygen<.1 and working(cell,"photosynthesis")==0:value*=.25
  if kind=="mitochondrion" and count==0 and cell.work_capacity()<1 and cell.substrate>0 and cell.oxygen>.1:value+=18
  # An acid-assisted recycler acquires its buffer/repair support first.
  if kind=="acidifying" and working(cell,"regenerative")==0:continue
  if value>score:
   best={"cell":cell,"kind":kind};score=value
   if kind=="photosynthesis":
    best["mutation"]="shade_leaf" if sim.light_at(cell.position)<.5 else "sun_leaf"
 return best

static func decision(sim,cell) -> Dictionary:
 var policy:=strategy(sim,cell)
 if policy not in VARIANTS or cell.id in sim.managed_cells:return {}
 var choice:=candidate(sim,cell)
 if not choice.is_empty() and cell.ap>=cell.construction_price():
  choice["action"]="install";return choice
 var priorities: Array=VARIANTS[policy][posmod(cell.id*19349663 ^ sim.seed_value*83492791,2)]
 var missing_core: bool=working(cell,priorities[0])==0
 # Only replace unsuitable/excess anatomy; do not liquidate useful support just
 # to chase another purchase. Keep passive food/energy and last defenses.
 for organ in cell.organs:
  if cell.inherent(organ):continue
  if organ.hp>0 and organ.kind in ["feeding","photosynthesis","mitochondrion"] and working(cell,organ.kind)<=1:continue
  if organ.hp>0 and organ.kind in ["protection","regenerative","neutralizing"] and working(cell,organ.kind)<=1:continue
  var limit: int=4 if organ.kind=="photosynthesis" else 2 if organ.kind in ["feeding","cilia","protection"] else 1
  var excess: bool=working(cell,organ.kind)>limit
  var unsuitable: bool=missing_core and organ.kind not in priorities
  if organ.hp<=0 or excess or unsuitable:
   return {"action":"remove","id":organ.id}
 return {}

static func working(cell,kind: String) -> int:
 var count:=0
 for organ in cell.organs:
  if organ.kind==kind and organ.hp>0:count+=1
 return count

static func set_strategy(sim,scope: String,value: String) -> bool:
 if scope not in ["cell","lineage"] or (value not in STRATEGIES and not (scope=="cell" and value=="inherit")):return false
 if sim.player.dead:return false
 if scope=="cell":
  if value=="inherit":sim.investment.cells.erase(sim.player.id)
  else:sim.investment.cells[sim.player.id]=value
 else:sim.investment.lineages[sim.player.lineage_id()]=value
 return true

static func owned_settings(sim,root: int) -> Dictionary:
 var overrides: Dictionary={}
 for cell in sim.cells:
  if cell.lineage_id()==root and sim.investment.cells.has(cell.id):overrides[cell.id]=sim.investment.cells[cell.id]
 return {"npc":{},"lineages":{root:sim.investment.lineages.get(root,"manual")},"cells":overrides}
