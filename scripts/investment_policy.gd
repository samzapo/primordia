extends RefCounted
## Saved purchase intent; anatomy, AP and feeding still use the ordinary rules.
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
 for cell in bodies:
  var strategy: String=sim.investment.npc.get(cell.id,"")
  if quotas.get(strategy,0)>0:assigned[cell.id]=strategy;quotas[strategy]-=1
  else:waiting.append(cell)
 for cell in waiting:
  for strategy in ["hunter","producer","grazer"]:
   if quotas[strategy]>0:
    assigned[cell.id]=strategy;quotas[strategy]-=1;break
 sim.investment.npc=assigned

static func strategy(sim,cell) -> String:
 var root: int=cell.lineage_id()
 if root!=sim.lineage.root_id and root not in sim.managed_lineages:return sim.investment.npc.get(cell.id,"manual")
 return sim.investment.cells.get(cell.id,sim.investment.lineages.get(root,"manual"))

static func candidate(sim,cell) -> Dictionary:
 var policy:=strategy(sim,cell)
 if policy not in PRIORITIES or cell.id in sim.managed_cells:return {}
 var best: Dictionary={}
 var score:=-INF
 var priorities: Array=PRIORITIES[policy]
 for index in priorities.size():
  var kind: String=priorities[index]
  if not cell.can_fit(kind,0,1,false):continue
  # Acquire the strategy's core first, then diversify by diminishing priority.
  var value: float=(priorities.size()-index)/float(1+cell.count(kind))
  if cell.count(priorities[0])==0 and index==0:value+=100
  if value>score:best={"cell":cell,"kind":kind};score=value
 return best

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
