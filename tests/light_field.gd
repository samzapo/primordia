extends SceneTree
const Light=preload("res://scripts/light_field.gd")
const Sim=preload("res://scripts/simulation.gd")
var assertions:=0
var failures:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=Sim.new(81,0,false)
	var state: int=sim.rng.state;var background: int=sim.background_rng.state
	var a:=Light.field(81);var b:=Light.field(82)
	var mean:=0.0;var minimum:=1.0;var maximum:=0.0
	for value in a:mean+=value;minimum=minf(minimum,value);maximum=maxf(maximum,value)
	check(absf(mean/a.size()-0.5)<0.000001,"Irregular layout retains the old mean illumination before existing weather/habitat scaling")
	check(minimum>=0.04999 and maximum<=0.95001 and maximum-minimum>0.65,"Both broad dark and light regions exist within finite bounded illumination")
	check(a!=b and a==Light.field(81),"The pond seed varies the stable pattern without random draws")
	var continuous:=true;var gradients:=true;var x_gradient_varies_with_y:=false
	for y in range(0,2560,160):
		for x in range(0,4096,160):
			var p:=Vector2(x+0.31,y+0.47)
			continuous=continuous and absf(Light.sample(81,p)-Light.sample(81,p+Light.WORLD))<0.000001
			continuous=continuous and absf(Light.sample(81,p)-Light.sample(81,p+Vector2(Light.WORLD.x,0)))<0.000001
			continuous=continuous and absf(Light.sample(81,p)-Light.sample(81,p+Vector2(0,Light.WORLD.y)))<0.000001
			continuous=continuous and absf(Light.sample(81,p)-Light.sample(81,p+Vector2(0.01,0)))<0.001
			var d:=Light.direction(81,p)
			var g:=Vector2(sim.light_at(p+Vector2(32,0))-sim.light_at(p-Vector2(32,0)),sim.light_at(p+Vector2(0,32))-sim.light_at(p-Vector2(0,32)))
			gradients=gradients and (g.length_squared()<0.0000001 or d.dot(g.normalized())>0.99)
			var dx:=Light.sample(81,p+Vector2(32,0))-Light.sample(81,p-Vector2(32,0))
			var shifted:=p+Vector2(0,500)
			var other:=Light.sample(81,shifted+Vector2(32,0))-Light.sample(81,shifted-Vector2(32,0))
			x_gradient_varies_with_y=x_gradient_varies_with_y or absf(dx-other)>0.03
	check(continuous,"Illumination is continuous and wraps seamlessly at the pond boundaries")
	check(gradients,"Photosynthetic steering follows the same field shown by the renderer")
	check(x_gradient_varies_with_y,"Warped regions cannot collapse to independent horizontal and vertical grid stripes")
	var adjacent:=0.0;var broad:=0.0;var n:=0
	for y in range(0,Light.ROWS,4):
		for x in range(0,Light.COLS,4):
			var p:=Vector2(x+0.5,y+0.5)*Light.SIZE
			adjacent+=absf(Light.sample(81,p+Vector2(32,0))-Light.sample(81,p))
			broad+=absf(Light.sample(81,p+Vector2(500,0))-Light.sample(81,p));n+=1
	check(adjacent/n<0.03 and broad>adjacent*5,"Light varies gently at grid scale and meaningfully over 100 micrometers")
	check(sim.rng.state==state and sim.background_rng.state==background,"Building/querying illumination never consumes ecological random streams")
	var restored=preload("res://scripts/network/state_codec.gd").new().restore(preload("res://scripts/network/state_codec.gd").new().capture(sim))
	check(is_equal_approx(restored.light_at(Vector2(712,389)),sim.light_at(Vector2(712,389))),"Saved ponds restore the same seeded illumination without a new save field")
	print("LIGHT FIELD: %d assertions, %d failures; range=%.3f..%.3f adjacent=%.4f 100um=%.4f" % [assertions,failures,minimum,maximum,adjacent/n,broad/n])
	quit(0 if failures==0 else 1)
