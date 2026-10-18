extends RefCounted
## Open-air carbon exchange. All additions enter exterior particle ownership.
## One bounded sweep per five simulation seconds; cameras/players grant nothing.
const COLS:=64
const ROWS:=40
const COUNT:=COLS*ROWS
const SIZE:=64.0
const PERIOD:=5.0
const SATURATION:=8.0 # Carbon units per 64x64 water area, not a cell allowance.
const RELAXATION:=10.0

static func node(at: Vector2) -> int:
 return posmod(floori(at.y/SIZE),ROWS)*COLS+posmod(floori(at.x/SIZE),COLS)

static func inventory(packets: Array) -> Dictionary:
 var mass:=PackedFloat32Array();mass.resize(COUNT)
 var first: Dictionary={}
 for packet in packets:
  if not packet.alive or packet.kind!=5:continue
  var k:=node(packet.p)
  mass[k]+=packet.amount
  if not first.has(k):first[k]=packet
 return {"mass":mass,"first":first}

static func deposit(sim,pending,first: Dictionary) -> float:
 var added:=0.0
 for k in COUNT:
  var q: float=pending[k]
  if q<=0:continue
  if first.has(k):
   var packet: Dictionary=first[k]
   packet.amount+=q;packet.capacity=float(packet.get("capacity",packet.amount-q))+q
  else:
   # A fixed surface grid has no camera/cell lookup. New material must diffuse
   # or advect to the membrane before the ordinary gas-intake path can use it.
   var at:=Vector2(k%COLS+.5,int(k/COLS)+.5)*SIZE
   sim.spawn_particle(sim.CARBON,at,Vector2.ZERO,q,-1)
  added+=q
 return added

static func degas(packets: Array,ratios: PackedFloat32Array) -> float:
 var removed:=0.0
 for packet in packets:
  if not packet.alive or packet.kind!=5:continue
  var factor: float=ratios[node(packet.p)]
  if factor>=1:continue
  var before: float=packet.amount
  packet.amount*=factor;packet.capacity=float(packet.get("capacity",before))*factor
  removed+=before-packet.amount
 return removed

static func step(sim) -> void:
 if not sim.ambient_carbon_enabled or sim.remote_client or sim.time<sim.ambient_carbon_due:return
 var elapsed: float=maxf(0,sim.time-sim.ambient_carbon_at)
 sim.ambient_carbon_at=sim.time;sim.ambient_carbon_due=sim.time+PERIOD
 if elapsed<=0:return
 var factor:=1-exp(-elapsed/RELAXATION)
 var added:=0.0;var removed:=0.0
 if sim.resident!=null:
  var result: Dictionary=sim.resident.replenish_carbon(factor,SATURATION)
  if result.has("error"):return
  added=result.added;removed=result.removed
 elif sim.particle_pool:
  var ids: Array[int]=[];ids.assign(sim.kernels.pool_carbon_ids())
  var prior=sim.rng;sim.rng=sim.ecology_rng
  sim._chemistry(0,ids,true);sim.rng=prior
  var result: Dictionary=sim.kernels.pool_carbon_supply(factor,SATURATION)
  added=float(result.added)+deposit(sim,result.pending,{})
  removed=float(result.removed)
 else:
  var ids: Array[int]=[]
  for i in sim.particles.size():
   if sim.particles[i].alive and sim.particles[i].kind==sim.CARBON:ids.append(i)
  var prior=sim.rng;sim.rng=sim.ecology_rng
  sim._chemistry(0,ids,true);sim.rng=prior
  var stock:=inventory(sim.particles)
  var pending:=PackedFloat64Array();pending.resize(COUNT)
  var ratios:=PackedFloat32Array();ratios.resize(COUNT);ratios.fill(1)
  for k in COUNT:
   pending[k]=maxf(0,SATURATION-stock.mass[k])*factor
   if stock.mass[k]>SATURATION:ratios[k]=1-factor*(1-SATURATION/stock.mass[k])
  removed=degas(sim.particles,ratios)
  added=deposit(sim,pending,stock.first)
  if sim.kernels!=null:sim.kernels.invalidate_particle_render()
 sim.ambient_carbon_added+=added
 sim.external_input+=added
 sim.ambient_carbon_removed+=removed
 sim.respiration_loss+=removed
