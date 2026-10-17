extends RefCounted
## Seeded weak external forcing, shared by detailed/coarse water and presentation.
const COUNT := 6
const PERIOD := 120.0
const Medium=preload("res://scripts/medium.gd")
static func sources(seed_number: int,clock: float) -> Array:
	var result: Array=[]
	for lane in COUNT:
		var phase:=maxf(0,clock)+lane*PERIOD/COUNT
		var episode:=floori(phase/PERIOD)
		var age:=fposmod(phase,PERIOD)/PERIOD
		var random:=RandomNumberGenerator.new()
		random.seed=seed_number^(lane*91771+episode*1000003+0x6ed1)
		var position:=Vector2(random.randf()*Medium.WORLD.x,random.randf()*Medium.WORLD.y)
		var radius:=random.randf_range(220,380)
		var strength:=random.randf_range(5,9)*(1 if random.randf()>.5 else -1)
		var drift:=Vector2.from_angle(random.randf()*TAU)*random.randf_range(1,3)
		var envelope:=pow(sin(age*PI),2)
		result.append({"p":position,"radius":radius,"strength":strength,"drift":drift,"envelope":envelope})
	return result

static func forcing(at: Vector2,items: Array) -> Vector2:
	var result:=Vector2.ZERO
	for source in items:
		var delta: Vector2=Medium.offset(source.p,at)
		var distance:=delta.length()
		if distance>=source.radius:continue
		var q: float=distance/source.radius
		var fade:=pow(1-q*q,2)*float(source.envelope)
		result+=(Vector2(-delta.y,delta.x)/source.radius*source.strength*2+source.drift)*fade
	return result

static func update(sim) -> void:
	# Half-second target sampling is independent of camera activity and particle RNG.
	var key: String=str(floori(sim.time*2))+":"+str(sim.environment.get("hour",-1))
	if sim.fluid.induced_key==key:return
	sim.fluid.induced_key=key
	var items:=sources(sim.seed_value,sim.time)
	var angle: float=sim.environment.get("flow_angle",0.0)
	var strength: float=sim.environment.get("flow_strength",1.0)
	for i in sim.fluid.tide.size():
		var at:=Vector2(i%Medium.COLS+.5,int(i/Medium.COLS)+.5)*Medium.SIZE
		sim.fluid.tide[i]=sim.fluid.current(at).rotated(angle)*strength+forcing(at,items)
