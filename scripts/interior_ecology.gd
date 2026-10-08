extends RefCounted
## Bounded intracellular parcel dynamics. Every parcel represents existing stock;
## motion continues in build mode but cannot award resources or advance biology.
const MAX_FOOD := 12
const MAX_WASTE := 8
var parcels: Array = []
var clock := 0.0
var identity := -1

func sync(cell, ap: int) -> void:
	if identity != cell.id:
		parcels.clear()
		clock = 0
		identity = cell.id
	var specifications := [
		{"kind":"food","amount":maxf(0,cell.substrate),"count":mini(MAX_FOOD,ceili(maxf(0,cell.substrate)/1.5))},
		{"kind":"waste","amount":maxf(0,cell.waste),"count":mini(MAX_WASTE,ceili(maxf(0,cell.waste)/0.4))},
		{"kind":"ap","amount":float(maxi(0,ap)),"count":maxi(0,ap)}]
	var next: Array = []
	for spec in specifications:
		for i in spec.count:
			var key: String = spec.kind+str(i)
			var parcel := {}
			for old in parcels:
				if old.key == key: parcel = old; break
			if parcel.is_empty():
				var a: float = i*2.399963+cell.id*0.37
				var p: Vector2 = Vector2.from_angle(a)*cell.radius*(0.33+0.25*fposmod(i*0.618,1))
				if spec.kind == "food": p = cell.local_point(0)*0.70+Vector2(0,(i%3-1)*4)
				parcel = {"key":key,"kind":spec.kind,"p":p,"v":Vector2.ZERO,"phase":a}
			parcel["amount"] = spec.amount/spec.count
			parcel["radius"] = 2.6 if spec.kind == "ap" else 2.2+sqrt(parcel.amount)*1.6
			next.append(parcel)
	parcels = next

func step(dt: float, cell) -> void:
	# Two small bounded substeps avoid tunneling during a slow editor frame.
	dt = clampf(dt,0,1.0/15)
	for substep in 2:
		var h := dt*0.5
		clock += h
		for parcel in parcels:
			var p: Vector2 = parcel.p
			var flow := Vector2(-p.y,p.x)*0.12
			var jitter := Vector2(sin(clock*2.1+parcel.phase),cos(clock*1.7+parcel.phase*1.3))*3
			parcel.v = parcel.v.lerp(flow+jitter,1-exp(-h*4))
			parcel.p += parcel.v*h
		for i in parcels.size():
			for j in range(i+1,parcels.size()):
				var a: Dictionary = parcels[i]
				var b: Dictionary = parcels[j]
				var delta: Vector2 = b.p-a.p
				var distance := delta.length()
				var reach: float = a.radius+b.radius
				if distance >= reach: continue
				var normal := delta/distance if distance > 0.00001 else Vector2.from_angle(i*2.4+j)
				var correction: Vector2 = normal*(reach-distance)*0.25
				a.p -= correction
				b.p += correction
		for parcel in parcels:
			var p: Vector2 = parcel.p
			var limit: float = maxf(0,cell.local_point(cell.surface_parameter(p.angle())).length()*0.78-parcel.radius)
			parcel.p = p.limit_length(limit)
			# Keep the large nucleus clear; tiny packets circulate around it.
			var nucleus: Vector2 = Vector2(-0.12,-0.10)*cell.radius
			var delta: Vector2 = parcel.p-nucleus
			if delta.length() < cell.radius*0.30+parcel.radius:
				parcel.p = nucleus+delta.normalized()*(cell.radius*0.30+parcel.radius)
				parcel.p = parcel.p.limit_length(limit)

func amount(kind: String) -> float:
	var total := 0.0
	for parcel in parcels:
		if parcel.kind == kind: total += parcel.amount
	return total
