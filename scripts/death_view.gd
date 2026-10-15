extends Node2D
const Art = preload("res://scripts/cell_art.gd")
const Medium = preload("res://scripts/medium.gd")
const LIFETIME := 1.8
var source
var seen := 0
var bursts: Array[Dictionary] = []
var camera := Vector2.ZERO
var zoom := 1.0

func reset(sim, serial: int=0) -> void:
	source=sim;seen=serial;bursts.clear()
	queue_redraw()

func sync(sim, at: Vector2, scale: float, dt: float) -> void:
	if source != sim:
		source = sim
		seen = 0
		bursts.clear()
	for burst in bursts: burst.age += dt
	bursts = bursts.filter(func(burst): return burst.age < LIFETIME)
	for event in sim.death_bursts:
		if event.serial <= seen: continue
		seen = event.serial
		if sim.time-event.time > LIFETIME: continue
		var burst: Dictionary = event.duplicate()
		burst.age = 0.0
		burst.colors = Art.make(sim.seed_value,event.lineage).colors
		bursts.append(burst)
		if bursts.size() > 32: bursts.pop_front()
	camera = at
	zoom = scale
	queue_redraw()

func _draw() -> void:
	for burst in bursts:
		var age: float = burst.age
		var fade: float = pow(maxf(0,1-age/LIFETIME),1.5)
		var origin: Vector2 = Medium.offset(camera,burst.at)
		var contour: PackedVector2Array = burst.outline
		var color: Color = burst.colors[3]
		color.a = fade*0.8
		# The actual membrane breaks into outward-moving vector fragments.
		for i in range(0,contour.size(),4):
			var a: Vector2 = contour[i].rotated(burst.angle)
			var b: Vector2 = contour[(i+2)%contour.size()].rotated(burst.angle)
			var move: Vector2 = (a+b).normalized()*burst.radius*age*0.75
			draw_line(origin+a+move,origin+b+move,color,maxf(1/zoom,4*(1-age/LIFETIME)),true)
		var glow: Color = burst.colors[4]
		glow.a = fade*0.35
		draw_arc(origin,burst.radius*(0.8+age*1.5),0,TAU,48,glow,2/zoom,true)
