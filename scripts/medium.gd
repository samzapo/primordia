extends RefCounted
## Mass-lumped, viscous 2D medium. Not an incompressible Navier-Stokes solver.
const SIZE := 64.0
const COLS := 64
const ROWS := 40
const WORLD := Vector2(COLS * SIZE, ROWS * SIZE)
const NODE_MASS := 22.0
const PLANT_DAMPING := .5 # Owner: halve vegetation dissipation, retaining its geometry.
# Keep the rectangular view and a full grid-cell halo at full speed. Only the
# next offscreen grid cell fades to dormancy; edge blur is presentation only.
const ACTIVE_PAD := 64.0
const ACTIVE_FADE := 64.0
var velocity := PackedVector2Array()
var particle_velocity := PackedVector2Array() # Derived particle-only attractor field; never saved.
var activity := PackedFloat32Array()
var driven := true
var induced_key := "" # Derived target cache; never a retained physical velocity.
var induced_base := PackedVector2Array()
var induced_base_key := ""
# Only the serial coarse cell integrator may couple to distant cached nodes.
var global_coupling := false
var local_suction := true
var native_suction := true
var native_views := true
static var kernels=preload("res://scripts/backend.gd").create()
var active_indices := PackedInt32Array()
var tide := PackedVector2Array()
# Derived habitat cache, rebuilt from retained plant anatomy rather than saved.
var plant_drag := PackedFloat32Array()
var plant_geometry := -1
var plant_revision := -1
var plant_enabled := false
var changes := PackedVector2Array()
var indices := PackedInt32Array([0,0,0,0])
var weights := PackedFloat64Array([0,0,0,0])

func _init() -> void:
	velocity.resize(COLS * ROWS)
	activity.resize(COLS * ROWS)
	changes.resize(COLS * ROWS)
	tide.resize(COLS * ROWS)
	for y in ROWS:
		for x in COLS:
			var i := index(x,y)
			velocity[i] = current(Vector2(x + 0.5, y + 0.5) * SIZE)
			tide[i] = velocity[i]
			active_indices.append(i)

static func wrap_position(p: Vector2) -> Vector2:
	return Vector2(fposmod(p.x, WORLD.x), fposmod(p.y, WORLD.y))

static func offset(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(wrapf(b.x - a.x, -WORLD.x * 0.5, WORLD.x * 0.5), wrapf(b.y - a.y, -WORLD.y * 0.5, WORLD.y * 0.5))

static func visibility(p: Vector2, camera: Vector2, half_view: Vector2 = Vector2(508,316)) -> float:
	var beyond := offset(camera,p).abs()-half_view-Vector2.ONE*ACTIVE_PAD
	var t := clampf(1.0-maxf(beyond.x,beyond.y)/ACTIVE_FADE,0,1)
	return t*t*(3-2*t)

static func activity_half_view(half_view: Vector2) -> Vector2:
	return half_view+Vector2.ONE*(ACTIVE_PAD+ACTIVE_FADE)

static func index(x: int, y: int) -> int:
	return posmod(y, ROWS) * COLS + posmod(x, COLS)

func current(p: Vector2) -> Vector2:
	# Explicit externally maintained tide plus periodic vortices.
	return Vector2(11 + 17 * sin(TAU * p.y / WORLD.y * 4), 15 * sin(TAU * p.x / WORLD.x * 4))

func particle_flow() -> PackedVector2Array:
	return particle_velocity if not particle_velocity.is_empty() else velocity

func prepare_attractors(cells: Array) -> void:
	# Append small mouth descriptors to the water field, not a blended force grid.
	# Every transport backend chooses one mouth per sample; stable IDs break ties.
	particle_velocity=velocity.duplicate()
	var ordered: Array=cells.duplicate()
	ordered.sort_custom(func(a,b):return a.id<b.id)
	for cell in ordered:
		if cell.dead or cell.substrate>=cell.gut_capacity()-.000001:continue
		for organ in cell.organs:
			if not cell.oral_pumping(organ):continue
			var power: float=minf(300,cell.ORAL_FLOW*organ.scale*organ.hp/organ.max_hp*cell.Genes.factor(organ,"suction")*cell.work_capacity())
			particle_velocity.append(cell.pore_center(organ))
			particle_velocity.append(Vector2(cell.oral_reach(organ),power))

func transport_sample(p: Vector2,kind: int=0) -> Vector2:
	if kind==3:return sample(p) # Chemical signals never enter the mouth attractor.
	var field:=particle_flow()
	var pull:=Vector2.ZERO
	var strongest:=-1.0
	for i in range(COLS*ROWS,field.size(),2):
		var delta:=offset(p,field[i]);var distance:=delta.length()
		var reach: float=field[i+1].x
		if distance>=reach or distance<.000001:continue
		var speed: float=field[i+1].y*(1-distance/reach)*minf(1,distance/24.0)
		if speed>strongest+.0001:
			strongest=speed;pull=delta/distance*speed
	return sample(p)+pull*(1.0 if kind==0 else .2)

func sample(p: Vector2) -> Vector2:
	return _sample(p,velocity)

func _sample(p: Vector2,field: PackedVector2Array) -> Vector2:
	# Allocation-free bilinear sampling is the hottest transport operation.
	var q := wrap_position(p) / SIZE - Vector2.ONE * 0.5
	var x := floori(q.x)
	var y := floori(q.y)
	var fx := q.x-x
	var fy := q.y-y
	var top := field[index(x,y)].lerp(field[index(x+1,y)],fx)
	var bottom := field[index(x,y+1)].lerp(field[index(x+1,y+1)],fx)
	return top.lerp(bottom,fy)

func set_camera(camera: Vector2, half_view: Vector2 = Vector2(508,316)) -> void:
	for i in active_indices: activity[i] = 0
	active_indices.clear()
	var reach := activity_half_view(half_view)
	var lo := Vector2i(((camera-reach)/SIZE).floor())
	var hi := Vector2i(((camera+reach)/SIZE).ceil())
	for y in range(lo.y,mini(hi.y+1,lo.y+ROWS)):
		for x in range(lo.x,mini(hi.x+1,lo.x+COLS)):
			var i := index(x,y)
			var amount := visibility(Vector2(x+0.5,y+0.5)*SIZE,camera,half_view)
			activity[i] = amount
			if amount > 0: active_indices.append(i)

func _weights(p: Vector2) -> float:
	var q := wrap_position(p)/SIZE-Vector2.ONE*0.5
	var x := floori(q.x)
	var y := floori(q.y)
	var fx := q.x-x
	var fy := q.y-y
	indices[0] = index(x,y)
	indices[1] = index(x+1,y)
	indices[2] = index(x,y+1)
	indices[3] = index(x+1,y+1)
	weights[0] = (1-fx)*(1-fy)*(1.0 if global_coupling else activity[indices[0]])
	weights[1] = fx*(1-fy)*(1.0 if global_coupling else activity[indices[1]])
	weights[2] = (1-fx)*fy*(1.0 if global_coupling else activity[indices[2]])
	weights[3] = fx*fy*(1.0 if global_coupling else activity[indices[3]])
	return weights[0]+weights[1]+weights[2]+weights[3]

func exchange(body, arm: Vector2, dt: float, strength: float = 16.0) -> Vector2:
	# Implicit drag impulse with exact equal/opposite momentum transfer to wet nodes.
	# Dormant nodes neither accept impulses nor contribute to the coupled sample.
	var total := _weights(body.position+arm)
	if total < 0.0001: return Vector2.ZERO
	var flow := Vector2.ZERO
	var inverse_fluid_mass := 0.0
	for k in 4:
		weights[k] /= total
		flow += velocity[indices[k]]*weights[k]
		inverse_fluid_mass += weights[k]*weights[k]/NODE_MASS
	var relative: Vector2 = flow - body.velocity - Vector2(-arm.y, arm.x) * body.angular_velocity
	var speed = relative.length()
	if speed < 0.00001: return Vector2.ZERO
	var axis = relative / speed
	var inverse_mass: float = 1.0/body.mass + pow(arm.cross(axis), 2)/body.inertia + inverse_fluid_mass
	var impulse = relative * (1 - exp(-strength * inverse_mass * dt)) / inverse_mass
	body.velocity += impulse / body.mass
	body.angular_velocity += arm.cross(impulse) / body.inertia
	for k in 4: velocity[indices[k]] -= impulse*weights[k]/NODE_MASS
	return impulse

func deposit(p: Vector2, impulse: Vector2) -> bool:
	var total := _weights(p)
	if total < 0.0001: return false
	for k in 4: velocity[indices[k]] += impulse*weights[k]/(NODE_MASS*total)
	return true

func step(dt: float) -> void:
	# Same conservative viscosity and external tide; only wet nodes are visited.
	for i in active_indices: changes[i] = Vector2.ZERO
	for i in active_indices:
		if activity[i] <= 0: continue
		var x := i%COLS
		var y := i/COLS
		for j in [index(x+1,y),index(x,y+1)]:
			var amount := minf(activity[i],activity[j])*minf(dt*0.8,0.2)
			if amount <= 0: continue
			var exchange_velocity := (velocity[j]-velocity[i])*amount
			changes[i] += exchange_velocity
			changes[j] -= exchange_velocity
		if driven: changes[i] += (tide[i]-velocity[i])*(1-exp(-dt*activity[i]*0.12))
	for i in active_indices:
		velocity[i] += changes[i]
		if plant_drag.size()==velocity.size():velocity[i]*=exp(-plant_drag[i]*dt*activity[i])

func momentum() -> Vector2:
	var sum = Vector2.ZERO
	for v in velocity: sum += v * NODE_MASS
	return sum

func can_couple(p: Vector2) -> bool:
	return _weights(p) > 0.0001

func suction(body, mouth: Vector2, reach: float, power: float, dt: float, inflow_axis: Vector2 = Vector2.ZERO) -> void:
	# ATP-driven local inflow changes the real medium. Return the exact opposite
	# linear/angular impulse to the pumping cell; other cells feel it via drag.
	var candidates := active_indices
	if local_suction:
		candidates = PackedInt32Array()
		var lo := Vector2i(((mouth-Vector2.ONE*reach)/SIZE).floor())
		var hi := Vector2i(((mouth+Vector2.ONE*reach)/SIZE).floor())
		for y in range(lo.y,mini(hi.y+1,lo.y+ROWS)):
			for x in range(lo.x,mini(hi.x+1,lo.x+COLS)):
				var candidate := index(x,y)
				if global_coupling or activity[candidate] > 0: candidates.append(candidate)
	if native_suction and kernels!=null:
		velocity=kernels.fluid_suction(velocity,activity,candidates,body,mouth,reach,power,dt,global_coupling,inflow_axis)
		return
	for i in candidates:
		var at := Vector2(i%COLS+0.5,int(i/COLS)+0.5)*SIZE
		var delta := offset(at,mouth)
		var distance := delta.length()
		if distance < 4 or distance >= reach: continue
		var arm := offset(body.position,at)
		if arm.length() < body.radius*0.65: continue
		var falloff := pow(1-distance/reach,2.0)*(1.0 if global_coupling else activity[i])
		# A ciliary band preferentially draws from the receptor-selected side;
		# ordinary pore pumping keeps its historical symmetric inflow.
		if inflow_axis.length_squared() > 0.01:
			falloff *= 0.15+0.85*maxf(0,(-delta/distance).dot(inflow_axis.normalized()))
		# A pump imposes inflow relative to its moving membrane. Solve the paired
		# body/node impulse with both inertias, avoiding world-anchored feedback.
		var surface_velocity: Vector2 = body.velocity+Vector2(-arm.y,arm.x)*body.angular_velocity
		var correction: Vector2 = delta/distance*power-(velocity[i]-surface_velocity)
		var axis := correction.normalized()
		var inverse_mass: float = 1.0/NODE_MASS+1.0/body.mass+pow(arm.cross(axis),2)/body.inertia
		var momentum_change: Vector2 = correction*(1-exp(-dt*2.2*falloff))/inverse_mass
		velocity[i] += momentum_change/NODE_MASS
		body.velocity -= momentum_change/body.mass
		body.angular_velocity -= arm.cross(momentum_change)/body.inertia

# Union of observed rectangles; no camera means the existing coarse field path.
func set_views(views: Array) -> void:
	if native_views and kernels!=null:
		var result: Dictionary=kernels.fluid_views(views)
		activity=result.activity;active_indices=result.indices;return
	active_indices.clear()
	for y in ROWS:
		for x in COLS:
			var i := index(x,y)
			var at := Vector2(x+.5,y+.5)*SIZE
			var detail := 0.0
			for view in views: detail = maxf(detail,visibility(at,Vector2(view.x,view.y),Vector2(view.z,view.w)))
			activity[i] = detail
			if detail > 0: active_indices.append(i)

func metrics() -> Dictionary:
	var speeds: Array=[];var invalid:=0
	for v in velocity:
		if v.is_finite():speeds.append(v.length())
		else:invalid+=1
	speeds.sort()
	return {"nodes":velocity.size(),"nonfinite":invalid,"speed_p50":speeds[speeds.size()/2] if not speeds.is_empty() else 0,"speed_p95":speeds[int(speeds.size()*.95)] if not speeds.is_empty() else 0,"speed_max":speeds[-1] if not speeds.is_empty() else 0}

func set_plants(habitat) -> void:
	var enabled: bool=habitat!=null and habitat.enabled
	var identity: int=habitat.get_instance_id() if habitat!=null else 0
	var revision: int=habitat.flow_revision if habitat!=null else 0
	if identity==plant_geometry and revision==plant_revision and enabled==plant_enabled:return
	plant_geometry=identity;plant_revision=revision;plant_enabled=enabled
	plant_drag.resize(COLS*ROWS);plant_drag.fill(0)
	if not enabled:return
	# Compact raster kernel over actual branches, including permeable foliage.
	# Sum stem density at wet grid nodes; a finite drag relaxes water toward the
	# anchored vegetation. It neither stops particles at stems nor caps velocity.
	for plant in habitat.plants:
		var scale: float=plant.radius/100.0
		for branch in habitat.forms[plant.form].branches:
			var a: Vector2=plant.p+branch.a.rotated(plant.angle)*scale
			var b: Vector2=plant.p+branch.b.rotated(plant.angle)*scale
			var radius: float=branch.r*scale
			var halo: float=SIZE*.55
			var reach:=Vector2.ONE*(radius+halo)
			var low:=Vector2i(((a.min(b)-reach)/SIZE-Vector2.ONE*.5).ceil())
			var high:=Vector2i(((a.max(b)+reach)/SIZE-Vector2.ONE*.5).floor())
			for y in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					var at:=Vector2(x+.5,y+.5)*SIZE
					var edge:=b-a
					var closest: Vector2=a+edge*clampf((at-a).dot(edge)/maxf(edge.length_squared(),.00001),0,1)
					var coverage:=clampf((radius+halo-at.distance_to(closest))/halo,0,1)
					var i:=index(x,y)
					plant_drag[i]=minf(2.0*PLANT_DAMPING,plant_drag[i]+.9*PLANT_DAMPING*minf(1,2*radius/SIZE)*coverage)
