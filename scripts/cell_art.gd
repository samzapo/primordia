extends RefCounted
## Presentation-only lineage identity. Never consumes the simulation's random stream.
const PALETTES := [
	["211344","813dc3","512b86","df64d8","ffc0ec","27c4ec","a4f4ff"],
	["101947","245dd6","18358b","39bce8","9cf3ff","ffb62e","fff18a"],
	["062c39","128b83","10535f","41d4b2","b9f5b0","ffac45","ffe887"],
	["571338","ef5144","bd2f52","ff953b","fff18c","268fd6","83e7ff"],
	["351543","b73987","732c69","f373ae","ffc7c9","39b5e9","b8f1ff"],
	["211d4c","6856cb","3d398f","ac85ef","ded1ff","f6a942","ffe980"]
]
static func make(seed_value: int, lineage: int, paint: String="") -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value ^ (lineage*1640531527)
	var colors: Array[Color] = []
	for hex in PALETTES[random.randi_range(0,PALETTES.size()-1)]: colors.append(Color(hex))
	if paint!="" and Color.html_is_valid(paint):
		var base:=Color(paint)
		colors[0]=base.darkened(.72);colors[1]=base;colors[2]=base.darkened(.38)
		colors[3]=base.lightened(.28);colors[4]=base.lightened(.72)
	var vesicles: Array = []
	for i in 6:
		vesicles.append({"angle":TAU*i/6+random.randf_range(-0.2,0.2),"distance":random.randf_range(0.5,0.67),"radius":random.randf_range(0.065,0.11),"tone":i%3})
	return {"colors":colors,"nucleus":random.randi_range(0,2),"phase":random.randf()*TAU,"vesicles":vesicles}

static func nucleus_outline(form: int, phase: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 32:
		var a := TAU*i/32
		var radius := 1.0
		if form == 1: radius += 0.18*cos(3*a+phase)
		elif form == 2: radius += 0.16*cos(2*a+phase)-0.12*cos(a-phase)
		points.append(Vector2(cos(a)*1.06,sin(a)*0.91)*radius)
	return points
