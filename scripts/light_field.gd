extends RefCounted
## Seeded, periodic illumination. A derived cache, never saved ecology or RNG.
## 0.2 micrometers/unit: broad modes span about 100um to the whole pond.
const WORLD:=Vector2(4096,2560)
const COLS:=128
const ROWS:=80
const SIZE:=32.0
static var cache: Dictionary={}

static func field(seed_value: int) -> PackedFloat32Array:
	if cache.has(seed_value):return cache[seed_value]
	var values:=PackedFloat32Array();values.resize(COLS*ROWS)
	var phase:=Vector2(fposmod(float(seed_value%104729)*0.6180339887,TAU),fposmod(float(seed_value%130363)*0.4142135623,TAU))
	var mean:=0.0
	for y in ROWS:
		var v:=TAU*(y+0.5)/ROWS
		for x in COLS:
			var u:=TAU*(x+0.5)/COLS
			var a:=u+0.60*sin(v+phase.y)+0.32*sin(u-v+phase.x)
			var b:=v+0.55*sin(u+phase.x)+0.25*cos(u+v+phase.y)
			var value:=0.54*sin(a+phase.x)+0.38*cos(b+phase.y)+0.24*sin(a+b+phase.x*0.7)+0.16*cos(2*a-b+phase.y)+0.08*sin(3*a+2*b+phase.x)
			values[y*COLS+x]=value;mean+=value
	mean/=values.size()
	var extent:=0.000001
	for value in values:extent=maxf(extent,absf(value-mean))
	for i in values.size():values[i]=0.5+0.45*(values[i]-mean)/extent
	if cache.size()>=4:cache.erase(cache.keys()[0])
	cache[seed_value]=values
	return values

static func sample(seed_value: int,at: Vector2) -> float:
	var values:=field(seed_value)
	var p:=Vector2(fposmod(at.x,WORLD.x),fposmod(at.y,WORLD.y))/SIZE-Vector2.ONE*0.5
	var x:=floori(p.x);var y:=floori(p.y)
	var fx:=p.x-x;var fy:=p.y-y
	return lerpf(lerpf(values[_index(x,y)],values[_index(x+1,y)],fx),lerpf(values[_index(x,y+1)],values[_index(x+1,y+1)],fx),fy)

static func direction(seed_value: int,at: Vector2) -> Vector2:
	return Vector2(sample(seed_value,at+Vector2(SIZE,0))-sample(seed_value,at-Vector2(SIZE,0)),sample(seed_value,at+Vector2(0,SIZE))-sample(seed_value,at-Vector2(0,SIZE))).normalized()

static func _index(x: int,y: int) -> int:
	return posmod(y,ROWS)*COLS+posmod(x,COLS)
