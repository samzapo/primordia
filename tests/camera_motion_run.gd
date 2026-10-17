extends SceneTree
const Motion=preload("res://scripts/camera_motion.gd")
const Medium=preload("res://scripts/medium.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var move=Motion.new()
	move.begin(Vector2(4090,1200),3.1,12)
	var target:=Vector2(12,1400)
	var first:=move.sample(target,-3.1,3)
	check(first.at.distance_to(Vector2(4090,1200))<.0001 and absf(wrapf(first.heading-3.1,-PI,PI))<.001 and absf(first.zoom-12)<.001,"Retarget starts at the exact displayed pose without a position, angle or zoom jump")
	var before: Dictionary=first
	var paused: Dictionary={}
	for frame in 15:move.advance(1.0/60,true)
	paused=move.sample(target,-3.1,3)
	check(paused==before,"Pause holds an in-progress camera transition exactly")
	var last_distance: float=Medium.offset(first.at,target).length()
	for frame in 45:
		move.advance(1.0/60)
		var pose:=move.sample(target,-3.1,3)
		var distance:=Medium.offset(pose.at,target).length()
		check(distance<=last_distance+.001,"Position approaches the target along the short wrapped route")
		check(absf(wrapf(pose.heading-first.heading,-PI,PI))<.1,"Orientation takes the short angular route")
		last_distance=distance
	check(not move.active and last_distance<.001,"Camera arrives exactly at its live destination")
	move.begin(Vector2(200,300),.5,8)
	move.sample(Vector2(2000,1500),-.5,2)
	move.advance(.2)
	var halfway:=move.sample(Vector2(2000,1500),-.5,2)
	move.begin(halfway.at,halfway.heading,halfway.zoom)
	var retarget:=move.sample(Vector2(900,600),1,4)
	check(retarget.at.distance_to(halfway.at)<.001 and absf(retarget.zoom-halfway.zoom)<.001,"A second retarget starts from the current interpolated view")
	move.cancel()
	check(move.sample(Vector2(900,600),1,4).at==Vector2(900,600),"Direct gesture cancellation restores exact pointer control")
	print("CAMERA MOTION: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
