extends RefCounted
## Saved purchase intent; anatomy, biomass and feeding use the ordinary rules.
const MANUAL_ONLY:=[] # Every currently available organ has an explicit strategy role.
const STRATEGIES:=["manual","hunter","producer","grazer","custom"]
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
 if sim.investment.cells.has(parent.id):sim.investment.cells[child.id]=strategy(sim,parent)
 var root=parent.lineage_id()
 var templates=sim.investment.get("cell_templates",{}).get(root,{})
 if templates.has(parent.id):templates[child.id]=templates[parent.id].duplicate(true)

# Variants are deterministic preferences, never free organs or hidden ecology knowledge.
const VARIANTS:={
 "hunter":[["hunting","toxin","propulsion","poreforming","sensing","protection","mitochondrion","regenerative"],
           ["hunting","poreforming","cilia","counterattack","protection","neutralizing","mitochondrion","regenerative","toxin_sac","family_toward"]],
 "producer":[["photosynthesis","protection","regenerative","mitochondrion","neutralizing","cilia","sensing","family_away","toxin_sac"],
             ["photosynthesis","cilia","neutralizing","mitochondrion","counterattack","regenerative","protection","sensing","family_toward","toxin_sac"]],
 "grazer":[["cilia","mitochondrion","regenerative","sensing","feeding","protection","neutralizing","family_toward"],
           ["cilia","neutralizing","regenerative","acidifying","mitochondrion","feeding","sensing","protection","family_away"]],
}
static func candidate(sim,cell) -> Dictionary:
 var policy:=strategy(sim,cell)
 if cell.id in sim.managed_cells:return {}
 if policy=="custom":return template_decision(sim,cell)
 if policy not in VARIANTS:return {}
 # Survival support comes before expanding any opted-in role. No remote food query.
 if policy=="producer" and cell.energy<18*cell.growth_scale():
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
 if cell.id in sim.managed_cells:return {}
 if policy=="custom":return template_decision(sim,cell)
 if policy not in VARIANTS:return {}
 var choice:=candidate(sim,cell)
 if not choice.is_empty() and cell.biomass>=cell.construction_price(choice.kind):
  choice["action"]="install";return choice
 var priorities: Array=VARIANTS[policy][posmod(cell.id*19349663 ^ sim.seed_value*83492791,2)]
 var missing_core: bool=working(cell,priorities[0])==0
 # Only replace unsuitable/excess anatomy; do not liquidate useful support just
 # to chase another purchase. Keep passive food/energy and last defenses.
 for organ in cell.organs:
  if cell.inherent(organ):continue
  if organ.hp>0 and organ.kind in ["feeding","photosynthesis","mitochondrion"] and working(cell,organ.kind)<=1:continue
  if organ.hp>0 and organ.kind in ["protection","regenerative","neutralizing"] and working(cell,organ.kind)<=1:continue
  var limit: int=4 if organ.kind=="photosynthesis" else 2 if organ.kind in ["feeding","cilia","protection","mitochondrion"] else 1
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
 return {"templates":sim.investment.get("templates",{}).get(root,{}),"cell_templates":sim.investment.get("cell_templates",{}).get(root,{}),"npc":{},"lineages":{root:sim.investment.lineages.get(root,"manual")},"cells":overrides}


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
  elif cell.can_fit(wanted.kind,0,1,false) and cell.biomass>=cell.construction_price(wanted.kind):
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
 var bucket=posmod(cell.id*19349663 ^ sim.seed_value,100)
 var fallback="hunter" if bucket<10 else "producer" if bucket<55 else "grazer"
 var saved=sim.investment.cells.get(cell.id,null);sim.investment.cells[cell.id]=fallback
 var result=decision(sim,cell)
 if saved==null:sim.investment.cells.erase(cell.id)
 else:sim.investment.cells[cell.id]=saved
 return result

static func retire(sim,cell) -> void:
 sim.investment.cells.erase(cell.id);sim.investment.npc.erase(cell.id)
 sim.investment.get("completed_templates",{}).erase(cell.id)
 var root=cell.lineage_id()
 var overrides=sim.investment.get("cell_templates",{}).get(root,{})
 overrides.erase(cell.id)
 if overrides.is_empty():sim.investment.get("cell_templates",{}).erase(root)
