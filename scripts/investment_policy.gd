extends RefCounted
## Saved purchase intent; anatomy, biomass and feeding use the ordinary rules.
const MANUAL_ONLY:=[] # Every currently available organ has an explicit strategy role.
const DEFAULT:="balanced"
# One shared weighted distribution for NPCs, Balanced families and the ecology fixture.
const MIX:={"hunter":2,"parasite":4,"grazer":10,"producer":20}
const MIX_TOTAL:=36
static func path_at(ticket: int) -> String:
 var slot:=posmod(ticket,MIX_TOTAL)
 for role in MIX:
  if slot<int(MIX[role]):return role
  slot-=int(MIX[role])
 return "producer"

static func balanced_path(sim,cell) -> String:
 # Stable per-cell lottery: no ecology RNG draw, no changing role as relatives die.
 return path_at(cell.id*19349663 ^ sim.seed_value*83492791)
const OPERATING_BIOMASS:=12.0
const STRATEGIES:=["manual","balanced","hunter","parasite","producer","grazer","custom"]
const PRIORITIES:={
 "hunter":["hunting","propulsion","feeding","poreforming","toxin","cilia","mitochondrion","protection"],
 "parasite":["hunting","sensing","propulsion","proboscis","mitochondrion","regenerative","protection"],
 "producer":["photosynthesis","protection","mitochondrion","regenerative","neutralizing"],
 "grazer":["cilia","protection","propulsion","regenerative","mitochondrion","sensing"],
}
static func npc_assignments(sim) -> void:
 # Defaults are resolved without rewriting saved family or individual choices.
 sim.investment.npc.clear()

static func strategy(sim,cell) -> String:
 var chosen: String=sim.investment.cells.get(cell.id,sim.investment.lineages.get(cell.lineage_id(),DEFAULT))
 return balanced_path(sim,cell) if chosen=="balanced" else chosen

static func inherit_strategy(sim,parent,child) -> void:
 # Explicit choices, including Manual, are inherited without random reassignment.
 if sim.investment.cells.has(parent.id):sim.investment.cells[child.id]=sim.investment.cells[parent.id]
 var root=parent.lineage_id()
 var templates=sim.investment.get("cell_templates",{}).get(root,{})
 if templates.has(parent.id):templates[child.id]=templates[parent.id].duplicate(true)

# Variants are deterministic preferences, never free organs or hidden ecology knowledge.
const VARIANTS:={
 "hunter":[["hunting","propulsion","feeding","poreforming","toxin","sensing","protection","mitochondrion","regenerative"],
           ["hunting","propulsion","feeding","poreforming","cilia","counterattack","protection","neutralizing","mitochondrion","regenerative","toxin_sac","family_toward"]],
 "parasite":[["hunting","sensing","propulsion","proboscis","mitochondrion","regenerative","protection","family_away"],
             ["hunting","sensing","propulsion","proboscis","neutralizing","mitochondrion","protection","regenerative","toxin_sac"]],
 "producer":[["photosynthesis","protection","regenerative","mitochondrion","neutralizing","cilia","sensing","family_away","toxin_sac"],
             ["photosynthesis","cilia","neutralizing","mitochondrion","regenerative","protection","sensing","family_toward","toxin_sac"]],
 "grazer":[["cilia","mitochondrion","regenerative","sensing","feeding","protection","neutralizing","family_toward"],
           ["cilia","neutralizing","regenerative","acidifying","mitochondrion","feeding","sensing","protection","family_away"]],
}
const WEAPONS:=["poreforming","toxin","counterattack","proboscis"]
static func weapons(cell) -> int:
 var count:=0
 for kind in WEAPONS:count+=working(cell,kind)
 return count

static func hunter_weapons(cell) -> int:
 return weapons(cell)-working(cell,"proboscis")

static func synergy_blocker(cell,policy: String) -> Dictionary:
 if cell.unattended_protected:return {}
 for organ in cell.organs:
  if policy=="parasite" and organ.kind in ["feeding","photosynthesis","poreforming","toxin","counterattack","acidifying"]:return {"action":"remove","id":organ.id}
  if (policy in ["hunter","grazer"] and organ.kind=="photosynthesis") or (policy in ["producer","grazer"] and organ.kind in WEAPONS) or (policy=="producer" and organ.kind=="feeding"):
   return {"action":"remove","id":organ.id}
 return {}

static func missing_synergy_part(sim,cell,policy: String) -> String:
 if policy=="hunter":
  if working(cell,"hunting")==0:return "hunting"
  if working(cell,"propulsion")==0:return "propulsion"
  if working(cell,"feeding")==0:return "feeding"
  # The first weapon comes last: mounting a pore gland also grants the
  # ordinary Hunter synergy's self-pore immunity in that same transaction.
  if hunter_weapons(cell)==0 and cell.count("photosynthesis")==0:return "poreforming"
 elif policy=="parasite":
  for kind in ["hunting","sensing","propulsion","proboscis"]:
   if working(cell,kind)==0:return kind
 elif policy=="producer":
  if working(cell,"mitochondrion")==0 and cell.energy<18 and cell.substrate>.1 and cell.oxygen>.1:return "mitochondrion"
  if working(cell,"photosynthesis")<2:return "photosynthesis"
  if working(cell,"mitochondrion")==0:return "mitochondrion"
 elif policy=="grazer":
  if working(cell,"feeding")==0:return "feeding"
  if working(cell,"cilia")==0:return "cilia"
 return ""

static func candidate(sim,cell) -> Dictionary:
 var policy:=strategy(sim,cell)
 if cell.id in sim.managed_cells:return {}
 if policy=="custom":return template_decision(sim,cell)
 if policy not in VARIANTS:return {}
 # Finish the actual anatomical synergy before scoring optional support.
 # A protected blocker may prevent completion; never expand around it instead.
 if cell.synergy()!=policy:
  var core:=missing_synergy_part(sim,cell,policy)
  if core!="" and cell.can_fit(core,0,1,false):
   return {"cell":cell,"kind":core,"mutation":"shade_leaf" if sim.light_at(cell.position)<.5 else "sun_leaf"} if core=="photosynthesis" else {"cell":cell,"kind":core}
  return {}
 # Recovery uses only this cell's stocks and local light, never a remote food query.
 if policy=="producer" and cell.energy<18:
  if cell.substrate>.1 and cell.oxygen>.1 and working(cell,"mitochondrion")<2 and cell.can_fit("mitochondrion",0,1,false):
   return {"cell":cell,"kind":"mitochondrion"}
  if working(cell,"photosynthesis")<4 and (working(cell,"photosynthesis")==0 or cell.carbon>.001) and cell.can_fit("photosynthesis",0,1,false):
   return {"cell":cell,"kind":"photosynthesis","mutation":"shade_leaf" if sim.light_at(cell.position)<.5 else "sun_leaf"}
 var variant: int=posmod(cell.id*19349663 ^ sim.seed_value*83492791,2)
 var priorities: Array=VARIANTS[policy][variant]
 var best: Dictionary={}
 var score:=-INF
 for index in priorities.size():
  var kind: String=priorities[index]
  var count: int=working(cell,kind)
  var limit: int=4 if kind=="photosynthesis" else 2 if kind in ["feeding","cilia","protection","mitochondrion"] else 1
  if count>=limit or not cell.can_fit(kind,0,1,false):continue
  var value: float=(priorities.size()-index)/pow(1+count,1.7)
  if working(cell,priorities[0])==0 and index==0:value+=100
  # Establish a complete working role before duplicating its headline organ.
  if index>0 and count==0:value+=12
  if policy=="hunter" and working(cell,"hunting")>0:
   if hunter_weapons(cell)==0 and kind in ["toxin","poreforming","counterattack"]:value+=70
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
 if cell.id in sim.managed_cells:return {}
 if policy=="custom":return template_decision(sim,cell)
 if policy not in VARIANTS:return {}
 var blocker:=synergy_blocker(cell,policy)
 if not blocker.is_empty():return blocker
 var choice:=candidate(sim,cell)
 if cell.energy<18 and (choice.is_empty() or not essential(cell,policy,choice.kind) or not can_purchase(sim,cell,choice.kind)):
  var recovery:=shed_support(cell,policy)
  if not recovery.is_empty():return recovery
 if not choice.is_empty() and can_purchase(sim,cell,choice.kind):
  choice["action"]="install";return choice
 var priorities: Array=VARIANTS[policy][posmod(cell.id*19349663 ^ sim.seed_value*83492791,2)]
 var missing_core: bool=cell.synergy()!=policy
 # Only replace unsuitable/excess anatomy; do not liquidate useful support just
 # to chase another purchase. Keep passive food/energy and last defenses.
 for organ in cell.organs:
  if cell.unattended_protected:continue
  if cell.inherent(organ):continue
  if organ.hp>0 and organ.kind in ["feeding","photosynthesis","mitochondrion"] and working(cell,organ.kind)<=1:continue
  if organ.hp>0 and organ.kind in ["protection","regenerative","neutralizing"] and working(cell,organ.kind)<=1:continue
  if organ.hp>0 and policy=="parasite" and organ.kind in ["hunting","sensing","propulsion","proboscis"] and working(cell,organ.kind)<=1:continue
  if organ.hp>0 and policy=="hunter" and ((organ.kind in WEAPONS and organ.kind!="proboscis" and hunter_weapons(cell)<=1) or (organ.kind=="propulsion" and working(cell,"propulsion")<=1)):continue
  if organ.hp>0 and policy=="grazer" and organ.kind=="cilia" and working(cell,"cilia")<=1:continue
  var limit: int=4 if organ.kind=="photosynthesis" else 2 if organ.kind in ["feeding","cilia","protection","mitochondrion"] else 1
  var excess: bool=working(cell,organ.kind)>limit
  var unsuitable: bool=missing_core and organ.kind not in priorities and not (policy=="hunter" and organ.kind=="proboscis")
  if organ.hp<=0 or excess or unsuitable:
   return {"action":"remove","id":organ.id}
 return {}

# Core food/energy and role-defining parts may be built before a birth reserve;
# discretionary expansion waits for both a birth budget and one minute of upkeep.
static func essential(cell,policy: String,kind: String) -> bool:
 if kind=="photosynthesis":return working(cell,kind)<2 or (policy=="producer" and cell.energy<18)
 if kind=="mitochondrion":return working(cell,kind)==0 or (policy=="producer" and cell.energy<18 and working(cell,kind)<2)
 if kind=="feeding":return working(cell,"feeding")==0 and (policy in ["grazer","hunter"] or working(cell,"photosynthesis")==0)
 if kind=="regenerative" and cell.health<70:return working(cell,kind)==0
 if policy=="parasite" and kind in ["hunting","sensing","propulsion","proboscis"]:return working(cell,kind)==0
 if policy=="hunter":
  if kind in ["hunting","propulsion"]:return working(cell,kind)==0
  if kind in WEAPONS and kind!="proboscis":return hunter_weapons(cell)==0
 return policy=="grazer" and kind in ["feeding","cilia"] and working(cell,kind)==0

static func can_purchase(sim,cell,kind: String) -> bool:
 var cost: float=cell.construction_price(kind)
 var policy:=strategy(sim,cell)
 var core:=essential(cell,policy,kind)
 var reserve:=OPERATING_BIOMASS
 var energy_floor:=18.0
 if sim.automatic_reproduction and not core:
  for mode in ["mitosis","budding"]:
   if not (cell.automatic_division if mode=="mitosis" else cell.automatic_budding):continue
   var q: Dictionary=sim.Lifecycle.quote(sim,cell,mode)
   reserve=maxf(reserve,q.material);energy_floor=maxf(energy_floor,q.energy)
 if cost>0 and cell.biomass-cost<reserve:return false
 # Leaves/mitochondria can rescue an underpowered build. Other additions must
 # already have enough ATP to run for a minute without consuming the birth budget.
 if kind in ["photosynthesis","mitochondrion"] and core:return true
 var upkeep: float=cell.organ_upkeep({"kind":kind,"scale":1.0,"hp":1.0,"mutation":""})
 return cell.energy>=energy_floor+60.0*upkeep

static func shed_support(cell,policy: String) -> Dictionary:
 if cell.unattended_protected:return {}
 var worst: Dictionary={};var largest:=0.0
 for organ in cell.organs:
  if organ.hp>0:
   if organ.kind in ["feeding","photosynthesis","mitochondrion"] or cell.receptor(organ.kind):continue
   if organ.kind=="regenerative" and cell.health<70:continue
   if policy=="parasite" and organ.kind in ["hunting","sensing","propulsion","proboscis"] and working(cell,organ.kind)<=1:continue
   if policy=="hunter" and organ.kind in WEAPONS and organ.kind!="proboscis" and hunter_weapons(cell)<=1:continue
   if policy=="hunter" and organ.kind=="propulsion" and working(cell,"propulsion")<=1:continue
   if policy=="grazer" and organ.kind=="cilia" and working(cell,"cilia")<=1:continue
  var upkeep: float=cell.organ_upkeep(organ)
  if organ.hp<=0 or upkeep>largest:
   worst={"action":"remove","id":organ.id};largest=upkeep
 return worst

static func working(cell,kind: String) -> int:
 var count:=0
 for organ in cell.organs:
  if organ.kind==kind and organ.hp>0:count+=1
 return count

static func set_strategy(sim,scope: String,value: String) -> bool:
 if scope not in ["cell","lineage","family_adopt"] or (value not in STRATEGIES and not (scope in ["cell","family_adopt"] and value=="inherit")):return false
 if sim.player.dead:return false
 if scope=="family_adopt":
  for member in sim.cells:
   if member.lineage_id()==sim.player.lineage_id():sim.investment.cells.erase(member.id)
 elif scope=="cell":
  if value=="inherit":sim.investment.cells.erase(sim.player.id)
  else:sim.investment.cells[sim.player.id]=value
 else:sim.investment.lineages[sim.player.lineage_id()]=value
 return true

static func owned_settings(sim,root: int) -> Dictionary:
 var overrides: Dictionary={}
 for cell in sim.cells:
  if cell.lineage_id()==root and sim.investment.cells.has(cell.id):overrides[cell.id]=sim.investment.cells[cell.id]
 return {"templates":sim.investment.get("templates",{}).get(root,{}),"cell_templates":sim.investment.get("cell_templates",{}).get(root,{}),"npc":{},"lineages":{root:sim.investment.lineages.get(root,DEFAULT)},"cells":overrides}


static func save_template(sim,scope: String,id: int) -> bool:
 if scope not in ["cell","lineage"]:return false
 for model in sim.cells:
  if model.id!=id or model.dead or model.lineage_id()!=sim.player.lineage_id():continue
  var template=[]
  for organ in model.organs:template.append({"kind":organ.kind,"scale":organ.scale,"mutation":organ.get("mutation","")})
  if not sim.investment.has("templates"):sim.investment["templates"]={}
  if not sim.investment.has("cell_templates"):sim.investment["cell_templates"]={}
  var root=sim.player.lineage_id()
  if scope=="lineage":sim.investment.templates[root]=template
  else:
   if not sim.investment.cell_templates.has(root):sim.investment.cell_templates[root]={}
   sim.investment.cell_templates[root][sim.player.id]=template
  return set_strategy(sim,scope,"custom")
 return false

static func template_decision(sim,cell) -> Dictionary:
 var root=cell.lineage_id()
 var target=sim.investment.get("cell_templates",{}).get(root,{}).get(cell.id,sim.investment.get("templates",{}).get(root,[]))
 if target.is_empty():return {}
 var signature=hash(target)
 if sim.investment.get("completed_templates",{}).get(cell.id,-1)==signature:return fallback_decision(sim,cell)
 var used={}
 for wanted in target:
  var found={}
  for organ in cell.organs:
   if organ.kind==wanted.kind and not used.has(organ.id):found=organ;break
  if not found.is_empty():
   used[found.id]=true
   if found.get("mutation","")!=wanted.mutation and wanted.mutation!="":return {"action":"adapt","id":found.id,"gene":wanted.mutation}
  elif cell.can_fit(wanted.kind,0,1,false) and can_purchase(sim,cell,wanted.kind):
   return {"action":"install","kind":wanted.kind,"mutation":wanted.mutation} if wanted.mutation!="" else {"action":"install","kind":wanted.kind}
  else:return {}
 for organ in cell.organs:
  if used.has(organ.id):continue
  if cell.unattended_protected:continue
  return {"action":"remove","id":organ.id}
 if not sim.investment.has("completed_templates"):sim.investment["completed_templates"]={}
 sim.investment.completed_templates[cell.id]=signature
 return fallback_decision(sim,cell)

static func fallback_decision(sim,cell) -> Dictionary:
 # Once the frozen build is complete, expansion is never undone next minute.
 var fallback=balanced_path(sim,cell)
 var saved=sim.investment.cells.get(cell.id,null);sim.investment.cells[cell.id]=fallback
 var result=decision(sim,cell)
 # A completed player-chosen example is not an order to dismantle its core
 # when the diverse fallback happens to prefer a different synergy.
 if result.get("action","")=="remove":
  var kind: String=cell.organ_by_id(result.id).kind
  var root=cell.lineage_id()
  var target=sim.investment.get("cell_templates",{}).get(root,{}).get(cell.id,sim.investment.get("templates",{}).get(root,[]))
  if target.filter(func(part):return part.kind==kind).size()>=cell.count(kind):result={}
 if saved==null:sim.investment.cells.erase(cell.id)
 else:sim.investment.cells[cell.id]=saved
 return result

static func placement_angle(sim,cell,kind: String) -> float:
 if strategy(sim,cell)!="parasite":return fposmod(cell.id*2.399963+cell.organs.size(),TAU)
 var front:=fposmod(cell.id*2.399963,TAU)
 for organ in cell.organs:
  if organ.kind=="propulsion" and organ.hp>0:front=wrapf(float(organ.a)-PI,-PI,PI);break
 for organ in cell.organs:
  if organ.kind=="proboscis" and organ.hp>0:front=float(organ.a);break
 return front+PI if kind=="propulsion" else front if kind=="proboscis" else front+.85 if kind=="hunting" else front-.85 if kind=="sensing" else fposmod(cell.id*2.399963+cell.organs.size(),TAU)

static func retire(sim,cell) -> void:
 sim.investment.cells.erase(cell.id);sim.investment.npc.erase(cell.id)
 sim.investment.get("completed_templates",{}).erase(cell.id)
 var root=cell.lineage_id()
 var overrides=sim.investment.get("cell_templates",{}).get(root,{})
 overrides.erase(cell.id)
 if overrides.is_empty():sim.investment.get("cell_templates",{}).erase(root)
