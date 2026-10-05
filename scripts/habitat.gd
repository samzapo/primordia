extends RefCounted
## Seeded radial branching colonies. Fixed environmental geometry, not food emitters.
const Medium = preload("res://scripts/medium.gd")
const BIN := 128.0
const COLS := 32
const ROWS := 20
var plants: Array = []
var forms: Array = []
var segments: Array = []
var bins: Dictionary = {}
var enabled := true
var accelerator = preload("res://scripts/backend.gd").create()

func _init(seed_number: int = 0, occupied: Array = []) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = seed_number ^ 0x62ab91
	for i in 6:
		var form := {"arms":5+i%3,"turn":random.randf_range(0.6,0.86),"branches":[],"palette":i%3}
		for arm in form.arms:
			_branch(form.branches,Vector2.ZERO,TAU*arm/form.arms,61.0,7.0,2,form.turn)
		forms.append(form)
	# Reject overlap with all initial cells and keep water passages between colonies.
	for i in 10:
		for attempt in 120:
			var radius := random.randf_range(185,275)
			var position := Vector2(random.randf()*Medium.WORLD.x,random.randf()*Medium.WORLD.y)
			# Three radial colonies form each loose reef; fallback preserves open starts.
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
			plants.append({"p":position,"radius":radius,"form":i%6,"angle":random.randf()*TAU})
			break
	rebuild()

static func _branch(output: Array, a: Vector2, angle: float, length: float, width: float, depth: int, turn: float) -> void:
	var b := a+Vector2.from_angle(angle)*length
	output.append({"a":a,"b":b,"r":width,"depth":depth})
	if depth == 0: return
	for fraction in [0.5,0.82]:
		for sign_value in [-1,1]:
			_branch(output,a.lerp(b,fraction),angle+sign_value*turn,length*0.39,width*0.49,depth-1,turn)

func rebuild() -> void:
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

func move_particles(particles: Array, ids: Array, revision: int, grid, native: bool = true) -> void:
	if not enabled: return
	if native and accelerator != null:
		if accelerator.obstacle_particles(particles,ids,revision): grid.rebuild(particles)
		return
	for index in ids:
		var packet: Dictionary = particles[index]
		if not packet.alive or packet.get("updated",-1) != revision: continue
		var candidates := query(packet.previous,packet.p,4.0)
		if candidates.is_empty(): continue
		var result := move(packet.previous,packet.p,packet.v,4.0,candidates)
		if not result[2]: continue
		var before: Vector2 = packet.p
		packet.p = result[0]
		packet.v = result[1]
		packet.previous = packet.p # Never interpolate through a solid branch.
		grid.move(index,before,packet.p)
