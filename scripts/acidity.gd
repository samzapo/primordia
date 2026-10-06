extends RefCounted
## Coarse acid-equivalent field. This is not a calibrated pH solver.
const Medium = preload("res://scripts/medium.gd")
var values := PackedFloat32Array()
var pending := PackedFloat32Array()

func _init() -> void:
	values.resize(Medium.COLS*Medium.ROWS)
	pending.resize(values.size())

func sample(at: Vector2) -> float:
	var p := Medium.wrap_position(at)/Medium.SIZE-Vector2.ONE*0.5
	var x := floori(p.x)
	var y := floori(p.y)
	return lerpf(lerpf(values[Medium.index(x,y)],values[Medium.index(x+1,y)],p.x-x),lerpf(values[Medium.index(x,y+1)],values[Medium.index(x+1,y+1)],p.x-x),p.y-y)

func exchange(at: Vector2, amount: float) -> float:
	var p := Medium.wrap_position(at)/Medium.SIZE
	var index := Medium.index(floori(p.x),floori(p.y))
	var before := values[index]
	values[index] = clampf(before+amount,0,1)
	return values[index]-before

func step(dt: float, fluid) -> void:
	# The caller selects either the detailed region or its coarse complement.
	for i in fluid.active_indices:
		var at := Vector2(i%Medium.COLS+0.5,floori(float(i)/Medium.COLS)+0.5)*Medium.SIZE
		var local_dt: float = dt*fluid.activity[i]
		var upstream := sample(at-fluid.velocity[i]*local_dt)
		var x: int = i%Medium.COLS
		var y := floori(float(i)/Medium.COLS)
		var neighbors := (values[Medium.index(x-1,y)]+values[Medium.index(x+1,y)]+values[Medium.index(x,y-1)]+values[Medium.index(x,y+1)])*0.25
		pending[i] = clampf(lerpf(upstream,neighbors,minf(1,local_dt*0.5))*exp(-local_dt*0.012),0,1)
	for i in fluid.active_indices: values[i] = pending[i]
