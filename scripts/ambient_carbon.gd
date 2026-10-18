extends RefCounted
## Open-air carbon exchange. All additions enter exterior particle ownership.
## One bounded sweep per five simulation seconds; cameras/players grant nothing.
const COLS:=64
const ROWS:=40
const COUNT:=COLS*ROWS
const SIZE:=64.0
const PERIOD:=5.0
const GROUPS:=20
const INTERVAL:=PERIOD/GROUPS
const SATURATION:=8.0 # Carbon units per 64x64 water area, not a cell allowance.
const RELAXATION:=10.0
const SPEED_SCALE:=20.0 # World units/s; speed-dependent exchange above background diffusion.

static func group(k: int,seed_value: int) -> int:return posmod(k*17+posmod(seed_value,GROUPS),GROUPS)

static func node(at: Vector2) -> int:
 return posmod(floori(at.y/SIZE),ROWS)*COLS+posmod(floori(at.x/SIZE),COLS)

static func inventory(packets: Array,kind: int=5) -> Dictionary:
 var mass:=PackedFloat32Array();mass.resize(COUNT)
 var first: Dictionary={}
 for packet in packets:
  if not packet.alive or packet.kind!=kind:continue
  var k:=node(packet.p)
  mass[k]+=packet.amount
  if not first.has(k):first[k]=packet
 return {"mass":mass,"first":first}

static func deposit(sim,pending,first: Dictionary,kind: int=5) -> float:
 var added:=0.0
 var room: int=maxi(0,5000-int(sim.habitat_census().external))
 for k in COUNT:
  var q: float=pending[k]
  if q<=0:continue
  if first.has(k):
   var packet: Dictionary=first[k]
   packet.amount+=q;packet.capacity=float(packet.get("capacity",packet.amount-q))+q
  else:
   # A fixed surface grid has no camera/cell lookup. New material must diffuse
   # or advect to the membrane before the ordinary gas-intake path can use it.
   if room<=0:continue # Uncreated material remains in the atmosphere.
   var random:=RandomNumberGenerator.new()
   random.seed=sim.seed_value ^ (k*73856093) ^ (int(sim.time/PERIOD)*19349663)
   var at:=Vector2(k%COLS+random.randf(),int(k/COLS)+random.randf())*SIZE
   sim.spawn_particle(kind,at,Vector2.ZERO,q,-1)
   room-=1
  added+=q
 return added

static func degas(packets: Array,ratios: PackedFloat32Array,kind: int=5) -> float:
 var removed:=0.0
 for packet in packets:
  if not packet.alive or packet.kind!=kind:continue
  var factor: float=ratios[node(packet.p)]
  if factor>=1:continue
  var before: float=packet.amount
  packet.amount*=factor;packet.capacity=float(packet.get("capacity",before))*factor
  removed+=before-packet.amount
 return removed

static func step(sim) -> void:
 if not sim.ambient_carbon_enabled or sim.remote_client or sim.time<sim.ambient_carbon_due:return
 if sim.ambient_carbon_times.size()!=GROUPS:
  sim.ambient_carbon_times.resize(GROUPS)
  sim.ambient_carbon_times.fill(maxf(sim.ambient_carbon_at,sim.time-PERIOD))
 var phase: int=sim.ambient_carbon_phase
 var elapsed: float=maxf(0,sim.time-sim.ambient_carbon_times[phase])
 sim.ambient_carbon_times[phase]=sim.time
 sim.ambient_carbon_phase=(phase+1)%GROUPS
 sim.ambient_carbon_at=sim.time;sim.ambient_carbon_due=sim.time+INTERVAL
 if elapsed<=0:return
 # Sample velocity once, only for the current staggered group. Background
 # diffusion remains; the extra exchange coefficient is linear in local speed.
 var speeds:=PackedFloat32Array();speeds.resize(COUNT)
 for k in COUNT:
  if group(k,sim.seed_value)!=phase:continue
  speeds[k]=1+sim.fluid.velocity[sim.fluid.index(k%COLS,int(k/COLS))].length()/SPEED_SCALE
 for kind in [sim.CARBON,sim.OXYGEN]:
  var factors:=PackedFloat32Array();factors.resize(COUNT)
  var relaxation: float=RELAXATION if kind==sim.CARBON else 60.0
  var target: float=SATURATION if kind==sim.CARBON else .5
  for k in COUNT:
   if speeds[k]>0:factors[k]=1-exp(-elapsed*speeds[k]/relaxation)
  var added:=0.0;var removed:=0.0
  if sim.resident!=null:
   var result: Dictionary=sim.resident.replenish_carbon(0,target,phase,kind,factors)
   if result.has("error"):return
   added=result.added;removed=result.removed
  elif sim.particle_pool:
   var ids: Array[int]=[];ids.assign(sim.kernels.pool_carbon_ids(kind))
   var prior=sim.rng;sim.rng=sim.ecology_rng
   sim._chemistry(0,ids,true);sim.rng=prior
   var result: Dictionary=sim.kernels.pool_carbon_supply(0,target,phase,posmod(sim.seed_value,GROUPS),kind,factors)
   added=float(result.added)+deposit(sim,result.pending,{},kind)
   removed=float(result.removed)
  else:
   var ids: Array[int]=[]
   for i in sim.particles.size():
    if sim.particles[i].alive and sim.particles[i].kind==kind:ids.append(i)
   var prior=sim.rng;sim.rng=sim.ecology_rng
   sim._chemistry(0,ids,true);sim.rng=prior
   var stock:=inventory(sim.particles,kind)
   var pending:=PackedFloat64Array();pending.resize(COUNT)
   var ratios:=PackedFloat32Array();ratios.resize(COUNT);ratios.fill(1)
   for k in COUNT:
    if group(k,sim.seed_value)!=phase:continue
    pending[k]=maxf(0,target-stock.mass[k])*factors[k]
    if stock.mass[k]>target:ratios[k]=1-factors[k]*(1-target/stock.mass[k])
   removed=degas(sim.particles,ratios,kind)
   added=deposit(sim,pending,stock.first,kind)
   if sim.kernels!=null:sim.kernels.invalidate_particle_render()
  if kind==sim.CARBON:
   sim.ambient_carbon_added+=added;sim.external_input+=added
   sim.ambient_carbon_removed+=removed;sim.respiration_loss+=removed
  else:
   sim.ambient_oxygen_added+=added;sim.ambient_oxygen_removed+=removed
