extends RefCounted
## Render actual membrane-bound material; no extra particles, damage or hit targets.
const ParticleArt=preload("res://scripts/particle_art.gd")
static func layout(cell,assembly: Dictionary) -> Dictionary:
	var point: Vector2=cell.local_point(assembly.a)
	var normal: Vector2=cell.local_normal(assembly.a)
	var radius:=clampf(cell.radius*.065,4,9)
	return {"at":point+normal*(radius*.65+2),"tag":point+normal*2,"radius":radius,"normal":normal,"units":clampi(int(assembly.units),0,4),"capped":bool(assembly.capped)}

static func draw(canvas: CanvasItem,cell,assembly: Dictionary) -> void:
	var pose:=layout(cell,assembly)
	var radius: float=pose.radius
	var complete: bool=pose.units==4 and not pose.capped
	var color:=Color("ffdc80") if complete else Color("ff985c")
	if pose.capped:color=Color("75bbff")
	if pose.units>0:
		var phase: float=pose.normal.angle()-PI*.25
		var sweep: float=TAU*pose.units/4.0
		# Each bound stage is a growing curved scaffold, not a full empty ring.
		canvas.draw_arc(pose.at,radius,phase,phase+sweep,24,Color("172b49"),5,true)
		canvas.draw_arc(pose.at,radius,phase,phase+sweep,24,color,2.8,true)
	if complete:
		canvas.draw_circle(pose.at,radius*.50,Color("071327"),true)
		canvas.draw_arc(pose.at,radius*.62,0,TAU,24,Color("fff1bb"),2.1,true)
	canvas.draw_texture_rect(ParticleArt.texture(11),Rect2(pose.tag-Vector2.ONE*3.5,Vector2.ONE*7),false)
	for i in pose.units:
		var a: float=pose.normal.angle()+TAU*i/4
		var at: Vector2=pose.at+Vector2.from_angle(a)*radius
		canvas.draw_set_transform(at,a+PI*.5)
		canvas.draw_texture_rect(ParticleArt.texture(12),Rect2(-Vector2.ONE*4,Vector2.ONE*8),false)
		canvas.draw_set_transform(Vector2.ZERO)
	if pose.capped:
		canvas.draw_arc(pose.at,radius*.8,pose.normal.angle()-.8,pose.normal.angle()+PI+.8,20,color,3,true)
		canvas.draw_line(pose.at+Vector2(-radius,-radius),pose.at+Vector2(radius,radius),color,2,true)
