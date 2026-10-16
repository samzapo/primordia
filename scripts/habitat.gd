extends RefCounted
## Seeded fern, radial, fan and spiral branching colonies. Fixed environmental geometry, not food emitters.
const Medium = preload("res://scripts/medium.gd")
const BIN := 128.0
const COLS := 32
const ROWS := 20
var plants: Array = []
var native_bounds := true
var forms: Array = []
var segments: Array = []
var bins: Dictionary = {}
var enabled := true
var flow_revision := 0
# Cells collide with stems; dissolved packets permeate the colony.
# False is retained solely for the historical contact benchmark.
var particles_permeable := true
var accelerator = preload("res://scripts/backend.gd").create()

func _init(seed_number: int = 0, occupied: Array = []) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = seed_number ^ 0x62ab91
	for i in 8:
		forms.append(_make_form(["fern","radial","fan","spiral"][i%4],i/4,random.randf_range(0.6,0.86)))
	# Reject overlap with all initial cells and keep water passages between colonies.
	for i in 10:
		for attempt in 120:
			var radius := random.randf_range(185,275)
			var position := Vector2(random.randf()*Medium.WORLD.x,random.randf()*Medium.WORLD.y)
			# Three varied colonies form each loose reef; fallback preserves open starts.
			# Keep the same colony count and explicit water corridors.
			if i%3 != 0 and not plants.is_empty() and attempt < 80:
				var anchor: Dictionary = plants[mini(plants.size()-1,(i/3)*3)]
				var heading := random.randf()*TAU
				var separation: float = radius+anchor.radius+random.randf_range(110,210)
				position = Medium.wrap_position(anchor.p+Vector2.from_angle(heading)*separation)
			if i == 0 and attempt == 0:
				radius = 190
				position = Vector2(1580,1340)
			var clear := true
			for cell in occupied:
				if Medium.offset(position,cell.position).length() < radius+cell.extent()+35: clear = false; break
			for plant in plants:
				if Medium.offset(position,plant.p).length() < radius+plant.radius+90: clear = false; break
			if not clear: continue
			plants.append({"p":position,"radius":radius,"form":i%forms.size(),"angle":random.randf()*TAU})
			break
	rebuild()

static func _make_form(kind: String, variant: int, turn: float) -> Dictionary:
	var form := {"kind":kind,"arms":1,"turn":turn,"branches":[],"palette":0,"root":Vector2.ZERO,"root_radius":7.0,"leaf":"oval"}
	match kind:
		"radial":
			form.arms = 5+variant*2
			form.palette = 2
			for arm in form.arms:
				_branch(form.branches,Vector2.ZERO,TAU*arm/form.arms,61.0,7.0,2,turn)
		"fern":
			form.root = Vector2(0,82)
			form.root_radius = 4.5
			form.leaf = "blade"
			_fern(form.branches,variant,turn)
		"fan":
			form.root = Vector2(0,76)
			form.root_radius = 5.0
			form.palette = 1
			form.leaf = "bud"
			_stem(form.branches,form.root,Vector2(0,48),5,4)
			for side in [-1,0,1]:
				_fork(form.branches,Vector2(0,48),-PI/2+side*(0.6+variant*0.10),42,3.5,3,turn*0.53)
		"spiral":
			form.arms = 3+variant
			form.palette = 3
			form.root_radius = 5.0
			for arm in form.arms:
				var a := Vector2.ZERO
				for i in range(1,9):
					var phase: float = TAU*arm/form.arms+float(i)/8*(1.8+turn*0.4)
					var b := Vector2.from_angle(phase)*(i*9.2)
					_stem(form.branches,a,b,lerpf(4.8,1.8,float(i)/8),1)
					if i > 1:
						_branch(form.branches,b,(b-a).angle()-0.9,15*(1-i/12.0),1.2,1,0.75)
					a = b
	# Normalize the complete foliage envelope for safe placement, culling and SVG.
	var extent := 0.0
	for branch in form.branches:
		extent = maxf(extent,maxf(branch.a.length(),branch.b.length())+maxf(branch.r,5.5))
	if extent > 96:
		var scale := 96/extent
		for branch in form.branches:
			branch.a *= scale
			branch.b *= scale
			branch.r *= scale
		form.root *= scale
		form.root_radius *= scale
	return form

static func _stem(output: Array, a: Vector2, b: Vector2, width: float, depth: int) -> void:
	output.append({"a":a,"b":b,"r":width,"depth":depth})

static func _fern(output: Array, variant: int, turn: float) -> void:
	# A curved rachis with paired pinnae; each pinna repeats smaller leaflets.
	var previous := Vector2(0,82)
	for i in range(1,11):
		var t := float(i)/10
		var p := Vector2(sin(t*PI)*(-8 if variant == 0 else 13),82-t*170)
		_stem(output,previous,p,lerpf(4.5,1.1,t),2)
		if i < 10:
			var span := (48 if variant == 0 else 38)*sin(PI*pow(t,0.72))+5
			for side in [-1,1]:
				var axis := Vector2(side,-0.32-t*0.55).normalized()
				_branch(output,p,axis.angle(),span,lerpf(2.3,1.1,t),1,turn)
		previous = p

static func _fork(output: Array, a: Vector2, angle: float, length: float, width: float, depth: int, turn: float) -> void:
	var b := a+Vector2.from_angle(angle)*length
	_stem(output,a,b,width,depth)
	if depth == 0: return
	for side in [-1,1]:
		_fork(output,b,angle+side*turn,length*0.63,width*0.66,depth-1,turn*0.93)

static func _branch(output: Array, a: Vector2, angle: float, length: float, width: float, depth: int, turn: float) -> void:
	var b := a+Vector2.from_angle(angle)*length
	output.append({"a":a,"b":b,"r":width,"depth":depth})
	if depth == 0: return
	for fraction in [0.5,0.82]:
		for sign_value in [-1,1]:
			_branch(output,a.lerp(b,fraction),angle+sign_value*turn,length*0.39,width*0.49,depth-1,turn)

func rebuild() -> void:
	flow_revision+=1
	segments.clear()
	bins.clear()
	for plant in plants:
		var scale: float = plant.radius/100.0
		for branch in forms[plant.form].branches:
			# Only stout stems are solid; the finest foliage is permeable decoration.
			if branch.depth == 0: continue
			var a: Vector2 = plant.p+branch.a.rotated(plant.angle)*scale
			var b: Vector2 = plant.p+branch.b.rotated(plant.angle)*scale
			segments.append({"a":a,"b":b,"r":branch.r*scale})
			var id := segments.size()-1
			var reach: Vector2 = Vector2.ONE*(branch.r*scale+8)
			var lo := ((a.min(b)-reach)/BIN).floor()
			var hi := ((a.max(b)+reach)/BIN).floor()
			for y in range(int(lo.y),int(hi.y)+1):
				for x in range(int(lo.x),int(hi.x)+1):
					var key := posmod(y,ROWS)*COLS+posmod(x,COLS)
					if not bins.has(key): bins[key] = []
					bins[key].append(id)

	if accelerator != null: accelerator.obstacle_configure(segments,bins)

func _key(p: Vector2) -> int:
	return posmod(floori(p.y/BIN),ROWS)*COLS+posmod(floori(p.x/BIN),COLS)

func query(start: Vector2, end: Vector2, radius: float) -> Array:
	if not enabled: return []
	end = start+Medium.offset(start,end)
	if radius <= 7 and _key(start) == _key(end): return bins.get(_key(end),[])
	var lo := ((start.min(end)-Vector2.ONE*radius)/BIN).floor()
	var hi := ((start.max(end)+Vector2.ONE*radius)/BIN).floor()
	var ids: Dictionary = {}
	for y in range(int(lo.y),mini(int(hi.y)+1,int(lo.y)+ROWS)):
		for x in range(int(lo.x),mini(int(hi.x)+1,int(lo.x)+COLS)):
			for id in bins.get(posmod(y,ROWS)*COLS+posmod(x,COLS),[]): ids[id] = true
	return ids.keys()

static func closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var edge := b-a
	return a+edge*clampf((p-a).dot(edge)/maxf(edge.length_squared(),0.00001),0,1)

func clear_at(p: Vector2, radius: float) -> bool:
	for id in query(p,p,radius):
		var s: Dictionary = segments[id]
		var a := p+Medium.offset(p,s.a)
		if p.distance_to(closest(p,a,a+s.b-s.a)) < radius+s.r+0.1: return false
	return true

static func circle_hit(p: Vector2, travel: Vector2, center: Vector2, radius: float) -> float:
	var delta := p-center
	var a := travel.length_squared()
	var b := delta.dot(travel)
	var c := delta.length_squared()-radius*radius
	if c <= 0: return 0.0 if b < 0 else 2.0
	var d := b*b-a*c
	if a < 0.000001 or d < 0: return 2.0
	var t := (-b-sqrt(d))/a
	return t if t >= 0 and t <= 1 else 2.0

static func capsule_hit(p: Vector2, travel: Vector2, a: Vector2, b: Vector2, radius: float) -> float:
	var t := minf(circle_hit(p,travel,a,radius),circle_hit(p,travel,b,radius))
	var axis := (b-a).normalized()
	var normal := axis.orthogonal()
	var side := (p-a).dot(normal)
	var speed := travel.dot(normal)
	if absf(speed) > 0.000001:
		for sign_value in [-1,1]:
			if speed*sign_value >= 0: continue
			var hit: float = (sign_value*radius-side)/speed
			var along := (p+travel*hit-a).dot(axis)
			if hit >= 0 and hit <= 1 and along >= 0 and along <= a.distance_to(b): t = minf(t,hit)
	return t

func move(start: Vector2, end: Vector2, velocity: Vector2, radius: float, candidates: Array = []) -> Array:
	if not enabled: return [end,velocity,false]
	var ids := candidates if not candidates.is_empty() else query(start,end,radius)
	if ids.is_empty(): return [end,velocity,false]
	var p := start
	var travel := Medium.offset(start,end)
	var hit_any := false
	# Growth/spawns can overlap a stem. Resolve initial penetration first.
	for iteration in 6:
		var pushed := false
		for id in ids:
			var s: Dictionary = segments[id]
			var a := p+Medium.offset(p,s.a)
			var b: Vector2 = a+s.b-s.a
			var delta := p-closest(p,a,b)
			var reach: float = radius+s.r+0.2
			if delta.length_squared() >= reach*reach: continue
			var n := delta.normalized() if delta.length_squared() > 0.000001 else (b-a).orthogonal().normalized()
			p += n*(reach-delta.length())
			velocity -= n*minf(0,velocity.dot(n))
			pushed = true
			hit_any = true
		if not pushed: break
	# Continuous capsule sweeps catch crossings; slide along the contacted stem.
	for iteration in 4:
		var earliest := 2.0
		var normal := Vector2.ZERO
		for id in ids:
			var s: Dictionary = segments[id]
			var a := p+Medium.offset(p,s.a)
			var b: Vector2 = a+s.b-s.a
			var t := capsule_hit(p,travel,a,b,radius+s.r+0.05)
			if t >= earliest: continue
			earliest = t
			var at := p+travel*t
			normal = (at-closest(at,a,b)).normalized()
		if earliest > 1:
			p += travel
			break
		hit_any = true
		p += travel*earliest+normal*0.08
		travel *= 1-earliest
		travel -= normal*minf(0,travel.dot(normal))
		velocity -= normal*minf(0,velocity.dot(normal))
		if travel.length_squared() < 0.000001: break
	return [Medium.wrap_position(p),velocity,hit_any]

func move_cell(cell, start: Vector2, end: Vector2, dt: float) -> void:
	if not enabled:
		cell.position = end
		return
	var contacts = preload("res://scripts/contacts.gd")
	var ids := query(start,end,cell.extent()+1)
	cell.position = start
	var travel := Medium.offset(start,end)
	var remaining := dt
	for iteration in 4:
		var earliest := 2.0
		var hit_normal := Vector2.ZERO
		var hit_point := Vector2.ZERO
		for id in ids:
			var segment: Dictionary = segments[id]
			var a: Vector2 = cell.position+Medium.offset(cell.position,segment.a)
			var b: Vector2 = a+segment.b-segment.a
			if native_bounds:
				var reach: float = cell.extent()+segment.r+0.2
				var finish: Vector2 = cell.position+travel
				if maxf(cell.position.x,finish.x) < minf(a.x,b.x)-reach or minf(cell.position.x,finish.x) > maxf(a.x,b.x)+reach or maxf(cell.position.y,finish.y) < minf(a.y,b.y)-reach or minf(cell.position.y,finish.y) > maxf(a.y,b.y)+reach: continue
			var near := closest(cell.position,a,b)
			var toward: Vector2 = near-cell.position
			var distance := toward.length()
			if toward.length_squared() < 0.00001: toward = (b-a).orthogonal()
			var normal := toward.normalized()
			var radius: float = cell.support(normal.angle())
			var overlap: float = radius+segment.r-distance
			if overlap > 0:
				var at: Vector2 = cell.position+normal*radius
				var speed := maxf(0,contacts.velocity_at(cell,at).dot(normal))
				contacts.solve(cell,null,at,normal,overlap)
				contacts.dent(cell,at,minf(radius*0.06,overlap*0.12+speed*dt*0.65))
				travel -= normal*maxf(0,travel.dot(normal))
				continue
			# Conservative envelope, refined with the actual approach-side radius.
			var t := capsule_hit(cell.position,travel,a,b,cell.extent()+segment.r)
			if t > 1: continue
			for refine in 3:
				var center: Vector2 = cell.position+travel*t
				normal = (closest(center,a,b)-center).normalized()
				radius = cell.support(normal.angle())
				t = capsule_hit(cell.position,travel,a,b,radius+segment.r+0.05)
				if t > 1: break
			if t < earliest:
				earliest = t
				hit_normal = normal
				hit_point = cell.position+travel*t+normal*radius
		if earliest > 1:
			cell.position = Medium.wrap_position(cell.position+travel)
			break
		cell.position = Medium.wrap_position(cell.position+travel*earliest-hit_normal*0.05)
		var speed := maxf(0,contacts.velocity_at(cell,hit_point).dot(hit_normal))
		contacts.solve(cell,null,hit_point,hit_normal,0)
		contacts.dent(cell,hit_point,speed*dt*0.65)
		remaining *= 1-earliest
		travel = cell.velocity*remaining
		if travel.length_squared() < 0.000001: break
	cell.position = Medium.wrap_position(cell.position)

func move_particles(particles: Array, ids: Array, revision: int, grid, native: bool = true) -> void:
	if not enabled or particles_permeable: return
	if native and accelerator != null:
		if accelerator.obstacle_particles(particles,ids,revision,native_bounds): grid.update(particles,ids)
		return
	for index in ids:
		var packet: Dictionary = particles[index]
		if not packet.alive or packet.get("kind",0) == 3 or packet.get("updated",-1) != revision: continue # Pheromones pass through solids.
		var candidates := query(packet.previous,packet.p,4.0)
		if candidates.is_empty(): continue
		var result := move(packet.previous,packet.p,packet.v,4.0,candidates)
		if not result[2]: continue
		var before: Vector2 = packet.p
		packet.p = result[0]
		packet.v = result[1]
		packet.previous = packet.p # Never interpolate through a solid branch.
		grid.move(index,before,packet.p)
