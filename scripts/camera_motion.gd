extends RefCounted
## Ease discrete retargets; continuous snapshot following and direct gestures stay direct.
const Medium=preload("res://scripts/medium.gd")
const DURATION:=.65
var active:=false
var pending:=false
var elapsed:=0.0
var origin:=Vector2.ZERO
var turn:=0.0
var magnification:=1.0
var displacement:=Vector2.ZERO
var rotation_error:=0.0
var zoom_error:=0.0
func begin(at: Vector2,heading: float,scale_value: float) -> void:
	origin=at;turn=heading;magnification=maxf(.0001,scale_value)
	elapsed=0;active=true;pending=true
func cancel() -> void:
	active=false;pending=false;elapsed=0
func advance(dt: float,paused: bool=false) -> void:
	if not active or pending or paused:return
	elapsed=minf(DURATION,elapsed+maxf(0,dt))
	if elapsed>=DURATION:active=false
func sample(at: Vector2,heading: float,scale_value: float) -> Dictionary:
	if not active:return {"at":at,"heading":heading,"zoom":scale_value}
	if pending:
		displacement=Medium.offset(at,origin)
		rotation_error=wrapf(turn-heading,-PI,PI)
		zoom_error=log(magnification/maxf(.0001,scale_value))
		pending=false
	var remaining:=1-smoothstep(0,DURATION,elapsed)
	return {"at":Medium.wrap_position(at+displacement*remaining),"heading":heading+rotation_error*remaining,"zoom":scale_value*exp(zoom_error*remaining)}
