extends RefCounted
## Network coverage only. Actual camera geometry and simulation clocks stay independent.
const Medium=preload("res://scripts/medium.gd")
const PREFETCH:=384.0
static func expanded(view: Vector4,margin: float=PREFETCH) -> Vector4:
	return Vector4(view.x,view.y,minf(Medium.WORLD.x*.5,view.z+margin),minf(Medium.WORLD.y*.5,view.w+margin))
static func covers(coverage: Vector4,view: Vector4) -> bool:
	var d:=Medium.offset(Vector2(coverage.x,coverage.y),Vector2(view.x,view.y)).abs()
	var full:=Medium.WORLD*.5
	return (coverage.z>=full.x or d.x+view.z<=coverage.z+32) and (coverage.w>=full.y or d.y+view.w<=coverage.w+32)
static func contains(view: Vector4,at: Vector2) -> bool:
	var d:=Medium.offset(Vector2(view.x,view.y),at).abs()
	return d.x<=view.z+32 and d.y<=view.w+32
