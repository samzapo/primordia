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
 var bodies: Array=[]
 for cell in sim.cells:
  if not cell.dead and cell.health>0 and cell.lineage_id()!=sim.lineage.root_id and cell.lineage_id() not in sim.managed_lineages:bodies.append(cell)
 bodies.sort_custom(func(a,b):return a.id<b.id)
 var hunters:=floori(bodies.size()*.1)
 var remaining:=bodies.size()-hunters
 var quotas: Dictionary={"hunter":hunters,"producer":ceili(remaining*.5),"grazer":floori(remaining*.5)}
 var assigned: Dictionary={}
 var waiting: Array=[]
 # Birth intent is explicit: descendants keep their inherited choice even when
 # reproduction changes the population mix. Quotas guide unassigned NPCs.
 for cell in bodies:
  var inherited: String=sim.investment.cells.get(cell.id,"")
  if inherited in ["hunter","producer","grazer"]:
   assigned[cell.id]=inherited;quotas[inherited]-=1
  else:waiting.append(cell)
 var unassigned: Array=[]
 for cell in waiting:
  var strategy: String=sim.investment.npc.get(cell.id,"")
  if quotas.get(strategy,0)>0:assigned[cell.id]=strategy;quotas[strategy]-=1
  else:unassigned.append(cell)
 for cell in unassigned:
  for strategy in ["hunter","producer","grazer"]:
   if quotas[strategy]>0:
    assigned[cell.id]=strategy;quotas[strategy]-=1;break
 sim.investment.npc=assigned

static func strategy(sim,cell) -> String:
 if sim.investment.cells.has(cell.id):return sim.investment.cells[cell.id]
 var root: int=cell.lineage_id()
 if root!=sim.lineage.root_id and root not in sim.managed_lineages:return sim.investment.npc.get(cell.id,"manual")
 return sim.investment.lineages.get(root,"manual")

# Commit only after placement succeeds. Failed proposals never consume RNG or
# leave an override for an identity that has not been born.
static func inherit_strategy(sim,parent,child) -> void:
 var inherited: String=strategy(sim,parent)
 if inherited=="manual":inherited=STRATEGIES[sim.rng.randi_range(1,3)]
 sim.investment.cells[child.id]=inherited
 if child.lineage_id()!=sim.lineage.root_id and child.lineage_id() not in sim.managed_lineages:
  sim.investment.npc[child.id]=inherited

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
