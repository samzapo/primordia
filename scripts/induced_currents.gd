extends RefCounted
## Short migrating external events; physical targets and source-local art share this data.
const COLUMNS := 8
const ROWS := 4
const COUNT := COLUMNS*ROWS
const PERIOD := 20.0
const GOLD_CORE := .22
const UNITS_PER_UM := 1.0/preload("res://scripts/scale_bar.gd").MICROMETERS_PER_UNIT
const Medium=preload("res://scripts/medium.gd")
static func sources(seed_number: int,clock: float) -> Array:
	var result: Array=[]
	for lane in COUNT:
		var phase:=maxf(0,clock)+lane*PERIOD/COUNT
		var episode:=floori(phase/PERIOD)
		var age:=fposmod(phase,PERIOD)
		var random:=RandomNumberGenerator.new()
		random.seed=seed_number^(lane*91771+episode*1000003+0x6ed1)
		var tile:=Vector2(lane%COLUMNS,int(lane/COLUMNS))
		var origin: Vector2=(tile+Vector2(random.randf_range(.1,.9),random.randf_range(.1,.9)))*Medium.WORLD/Vector2(COLUMNS,ROWS)
		var radius:=random.randf_range(30,100)*UNITS_PER_UM*.5
		var heading:=Vector2.from_angle(random.randf()*TAU)
		var migration: Vector2=heading*random.randf_range(10,50)*UNITS_PER_UM
		# Opposite-phase continuous lanes guarantee an event while others expire.
		var duration:=20.0 if lane==0 or lane==COUNT/2 else random.randf_range(1,20)
		var ramp:=minf(.5,duration*.2)
		var envelope:=smoothstep(0,ramp,age)*(1-smoothstep(duration-ramp,duration,age)) if age<duration else 0.0
		result.append({"p":Medium.wrap_position(origin+migration*age),"radius":radius,"migration":migration,"age":age,"duration":duration,"kind":"spiral" if random.randf()>.5 else "directional","spin":1.0 if random.randf()>.5 else -1.0,"strength":random.randf_range(12,24),"heading":heading,"envelope":envelope})
	return result

static func _field(delta: Vector2,source: Dictionary) -> Vector2:
	if source.kind=="directional":return source.heading*source.strength
	return (Vector2(-delta.y,delta.x)*source.spin*2-delta*.35)*source.strength/source.radius

static func forcing(at: Vector2,items: Array) -> Vector2:
	var result:=Vector2.ZERO
	var weight:=0.0
	for source in items:
		var delta: Vector2=Medium.offset(source.p,at)
		var q: float=delta.length()/source.radius
		if q>=1 or source.envelope<=0:continue
		var fade:=pow(1-q*q,2)*float(source.envelope)
		result+=_field(delta,source)*fade;weight+=fade
	return result/maxf(1.0,weight)

static func update(sim) -> void:
	# Fast events refresh at 10Hz, rasterizing only their small support regions.
	var key: String=str(floori(sim.time*10))+":"+str(sim.environment.get("hour",-1))
	if sim.fluid.induced_key==key:return
	sim.fluid.induced_key=key
	var base_key: String=str(sim.environment.get("flow_angle",0.0))+":"+str(sim.environment.get("flow_strength",1.0))
	if sim.fluid.induced_base.size()!=sim.fluid.tide.size() or sim.fluid.induced_base_key!=base_key:
		sim.fluid.induced_base.resize(sim.fluid.tide.size());sim.fluid.induced_base_key=base_key
		for i in sim.fluid.tide.size():
			var at:=Vector2(i%Medium.COLS+.5,int(i/Medium.COLS)+.5)*Medium.SIZE
			sim.fluid.induced_base[i]=sim.fluid.current(at).rotated(sim.environment.get("flow_angle",0.0))*float(sim.environment.get("flow_strength",1.0))
	sim.fluid.tide=sim.fluid.induced_base.duplicate()
	var additions:=PackedVector2Array();additions.resize(sim.fluid.tide.size())
	var weights:=PackedFloat32Array();weights.resize(sim.fluid.tide.size())
	var touched: Dictionary={}
	for source in sources(sim.seed_value,sim.time):
		if source.envelope<=0:continue
		var reach: Vector2=Vector2.ONE*source.radius
		var low:=Vector2i(((source.p-reach)/Medium.SIZE-Vector2.ONE*.5).ceil())
		var high:=Vector2i(((source.p+reach)/Medium.SIZE-Vector2.ONE*.5).floor())
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var delta: Vector2=Vector2(x+.5,y+.5)*Medium.SIZE-source.p
				var q: float=delta.length()/source.radius
				if q>=1:continue
				var fade:=pow(1-q*q,2)*float(source.envelope)
				var i:=Medium.index(x,y)
				additions[i]+=_field(delta,source)*fade;weights[i]+=fade;touched[i]=true
	for i in touched:sim.fluid.tide[i]+=additions[i]/maxf(1.0,weights[i])
