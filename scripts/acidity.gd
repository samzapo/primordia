extends RefCounted
## Transport acid equivalents, not pH: mixing logarithmic pH directly is invalid.
## The pH display uses ideal dilute water at 25 C and a fictional concentration
## calibration (one field unit = 1 mmol/L excess strong acid), not a pond assay.
const DIFFUSION := 0.12
const NEUTRALIZATION := 0.08
const EXCESS_MOLAR := 0.001
static func ph_from_equivalents(value: float) -> float:
	# Stable quadratic solution of H - OH = excess, H*OH = 1e-14.
	var excess:=absf(value)*EXCESS_MOLAR
	var major: float=(excess+sqrt(excess*excess+4e-14))*.5
	var hydrogen: float=major if value>=0 else 1e-14/major
	return clampf(-log(hydrogen)/log(10),0,14)

static func indicator_color(ph: float) -> Color:
	var stops: Array=[Color("ef38a2"),Color("f52f82"),Color("fa557c"),Color("ff963a"),Color("ffe278"),Color("dfe99c"),Color("e8edbc"),Color("bfd944"),Color("17b545"),Color("30a78f"),Color("75d8eb"),Color("24a9c6"),Color("7861b5"),Color("742bd0")]
	var at:=clampf(ph,1,14)-1
	var color: Color=stops[floori(at)].lerp(stops[mini(13,floori(at)+1)],fposmod(at,1))
	color.a=smoothstep(.25,2.0,absf(ph-7))*.82
	return color

func ph_at(at: Vector2) -> float:return ph_from_equivalents(sample(at))

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
		pending[i] = clampf(lerpf(upstream,neighbors,minf(1,local_dt*DIFFUSION))*exp(-local_dt*NEUTRALIZATION),0,1)
	for i in fluid.active_indices: values[i] = pending[i]
