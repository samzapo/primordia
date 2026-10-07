extends RefCounted
## Synthetic, fixed-inventory transport fixture; no birth, feeding or reactions.
const WORLD := Vector2(4096,2560)
const RADII := [4.0,2.5,3.0,2.5,5.0,3.0,4.0,4.0,3.0,3.0,3.5]
static func make(count: int, distribution: String = "uniform") -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed=340071
	var data := PackedFloat32Array()
	data.resize(count*12)
	for i in count:
		var k := i*12
		var at := Vector2(2048,1280)+Vector2(rng.randf_range(-810,810),rng.randf_range(-506,506))
		if distribution=="clustered":
			at=Vector2(2048,1280)+Vector2.from_angle(TAU*(i%5)/5.0)*270+Vector2(rng.randfn(0,45),rng.randfn(0,45))
		elif distribution=="seam":
			at=Vector2(4094 if i%2 else 2,2558 if i%3 else 2)
		data[k]=at.x;data[k+1]=at.y;data[k+2]=rng.randf_range(-PI,PI);data[k+3]=rng.randf_range(-1,1)
		data[k+4]=rng.randf_range(-30,30);data[k+5]=rng.randf_range(-30,30);data[k+7]=i%11
		data[k+8]=2*RADII[i%11]*0.8
		data[k+9]=300.0/count # Fixed total, independent of resolution.
	return data
static func flow() -> PackedVector2Array:
	var field := PackedVector2Array()
	for y in 40:
		for x in 64:
			field.append(Vector2(32+23*sin(TAU*(y+0.5)/40),18*cos(TAU*(x+0.5)/64)))
	return field
static func hash32(x: int) -> int:
	x=((x^(x>>16))*0x7feb352d)&0xffffffff
	x=((x^(x>>15))*0x846ca68b)&0xffffffff
	return x^(x>>16)
static func uniform_noise(x: int) -> float: return ((hash32(x)>>8)+0.5)/16777216.0
static func normal_noise(x: int) -> float: return sqrt(-2*log(uniform_noise(x)))*cos(TAU*uniform_noise(x^0x9e3779b9))
static func node(x: int,y: int) -> int: return posmod(y,40)*64+posmod(x,64)
static func sample(field: PackedVector2Array, at: Vector2) -> Vector2:
	var p := Vector2(fposmod(at.x,4096),fposmod(at.y,2560))/64-Vector2(0.5,0.5)
	var x := floori(p.x)
	var y := floori(p.y)
	return field[node(x,y)].lerp(field[node(x+1,y)],p.x-x).lerp(field[node(x,y+1)].lerp(field[node(x+1,y+1)],p.x-x),p.y-y)
static func wrapped(at: Vector2) -> Vector2: return Vector2(fposmod(at.x,4096),fposmod(at.y,2560))
static func advance(data: PackedFloat32Array, field: PackedVector2Array, dt: float, tick: int) -> PackedFloat32Array:
	# Portable correctness oracle, never presented as a native-CPU speed comparison.
	var out := data.duplicate()
	for i in data.size()/12:
		var k := i*12
		var tracer := data[k+7]==3
		var at := Vector2(data[k],data[k+1])
		var launch := Vector2.ZERO if tracer else Vector2(data[k+4],data[k+5])
		var original := launch
		if dt<=0.05: at=wrapped(at+(sample(field,at)+launch)*dt)
		else:
			var steps := clampi(ceili(dt/0.25),1,8)
			var h := dt/steps
			for j in steps:
				var mid := at+sample(field,at)*(h*0.5)+launch*((1-exp(-0.4*h))/0.8)
				at=wrapped(at+sample(field,mid)*h+launch*((1-exp(-0.8*h))/0.8))
				launch*=exp(-0.8*h)
		var seed := (i*0x9e3779b9+tick*0x85ebca6b)&0xffffffff
		at=wrapped(at+Vector2(normal_noise(seed),normal_noise((seed+1)&0xffffffff))*sqrt((240 if tracer else 12)*dt))
		out[k]=at.x;out[k+1]=at.y
		out[k+2]=0 if tracer else wrapf(data[k+2]+data[k+3]*dt+normal_noise((seed+2)&0xffffffff)*sqrt(1.2*dt),-PI,PI)
		original*=exp(-0.8*dt);out[k+4]=original.x;out[k+5]=original.y;out[k+6]+=dt
	return out
static func compare(a: PackedFloat32Array,b: PackedFloat32Array) -> Dictionary:
	if a.size()!=b.size(): return {"passed":false,"reason":"size mismatch"}
	var position := 0.0
	var angle := 0.0
	var motion := 0.0
	var finite := true
	var unchanged := true
	for k in range(0,a.size(),12):
		for j in 12: finite=finite and is_finite(b[k+j])
		position=maxf(position,Vector2(wrapf(a[k]-b[k],-2048,2048),wrapf(a[k+1]-b[k+1],-1280,1280)).length())
		angle=maxf(angle,absf(wrapf(a[k+2]-b[k+2],-PI,PI)))
		for j in [4,5,6]: motion=maxf(motion,absf(a[k+j]-b[k+j]))
		for j in [3,7,8,9,10,11]: unchanged=unchanged and a[k+j]==b[k+j]
	return {"passed":finite and unchanged and position<0.1 and angle<0.001 and motion<0.01,"max_position_error":position,"max_angle_error":angle,"max_motion_error":motion,"finite":finite,"metadata_unchanged":unchanged}

static func load_native() -> bool:
	if OS.get_environment("PRIMORDIA_BACKEND")=="script": return false
	if not ClassDB.class_exists("PrimordiaResidentReference"):
		for path in ["res://native/resident.gdextension","res://build/native/primordia.gdextension"]:
			if FileAccess.file_exists(path):
				GDExtensionManager.load_extension(path)
				break
	return ClassDB.class_exists("PrimordiaResidentReference")
