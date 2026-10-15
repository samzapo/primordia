extends RefCounted
const Medium=preload("res://scripts/medium.gd")
const Cell=preload("res://scripts/cell.gd")
static func momentum(field,body) -> Array:
	var x: float=body.velocity.x*body.mass
	var y: float=body.velocity.y*body.mass
	for value in field.velocity:x+=float(value.x)*field.NODE_MASS;y+=float(value.y)*field.NODE_MASS
	return [x,y]
static func run(check: Callable) -> void:
	for dt in [1.0/60,.125]:
		for global in [false,true]:
			for axis in [Vector2.ZERO,Vector2(1,.3)]:
				var fast=Medium.new();var slow=Medium.new();slow.native_suction=false
				fast.global_coupling=global;slow.global_coupling=global
				for i in fast.activity.size():
					fast.activity[i]=.4 if i%2 else 1.0;slow.activity[i]=fast.activity[i]
				var a=Cell.new(1,Vector2(4090.123,70.321));a.velocity=Vector2(40,-20);a.angular_velocity=.3
				var b=Cell.clone_state(a)
				var before:=momentum(fast,a)
				for i in 20:
					fast.suction(a,Vector2(3.234,70.123),170,64,dt,axis)
					slow.suction(b,Vector2(3.234,70.123),170,64,dt,axis)
				var error:=0.0
				for i in fast.velocity.size():error=maxf(error,fast.velocity[i].distance_to(slow.velocity[i]))
				check.call(error<.0001 and a.velocity.distance_to(b.velocity)<.0001 and absf(a.angular_velocity-b.angular_velocity)<.000001,"Native suction retains ordered reference impulses across seams, axes and coarse/fine steps")
				var after:=momentum(fast,a)
				check.call(Vector2(after[0]-before[0],after[1]-before[1]).length()<.01,"Native pumping conserves paired body/water momentum")
	for views in [[],[Vector4(4090.123,70.321,800,500)],[Vector4(4090.123,70.321,800,500),Vector4(1000.4,1800.2,600,400)]]:
		var fast=Medium.new();var slow=Medium.new();slow.native_views=false
		fast.set_views(views);slow.set_views(views)
		check.call(fast.activity==slow.activity and fast.active_indices==slow.active_indices,"Native observed-field union preserves every reference weight and node order")
