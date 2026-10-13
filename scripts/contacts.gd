extends RefCounted
## Bounded impulse contacts for soft radial membranes and solid stems.
## The ring supplies geometry/compliance; this is not a continuum soft-body solver.
const Medium = preload("res://scripts/medium.gd")
const RESTITUTION := 0.12
const FRICTION := 0.38

static func surface(cell, direction: Vector2) -> Dictionary:
	var parameter: float = cell.surface_parameter(direction.angle()-cell.angle)
	var phase: float = fposmod(parameter,TAU)/TAU*cell.membrane.COUNT
	var i := int(phase)
	var edge: Vector2 = (cell.membrane.points[(i+1)%cell.membrane.COUNT]-cell.membrane.points[i]).rotated(cell.angle)
	var n := Vector2(edge.y,-edge.x).normalized()
	return {"at":cell.position+cell.local_point(parameter).rotated(cell.angle),"normal":n}

static func velocity_at(cell, at: Vector2) -> Vector2:
	if cell == null or cell.activity <= 0: return Vector2.ZERO
	return cell.velocity+Medium.offset(cell.position,at).orthogonal()*cell.angular_velocity

static func apply(cell, impulse: Vector2, at: Vector2) -> void:
	if cell == null or cell.activity <= 0: return
	cell.velocity += impulse*(cell.activity/cell.mass)
	cell.angular_velocity += Medium.offset(cell.position,at).cross(impulse)*(cell.activity/cell.inertia)

static func solve(a, b, at: Vector2, normal: Vector2, penetration: float) -> float:
	var ia: float = a.activity/a.mass
	var ib: float = b.activity/b.mass if b != null else 0.0
	var ra := Medium.offset(a.position,at)
	var rb := Medium.offset(b.position,at) if b != null else Vector2.ZERO
	var aa: float = a.activity/a.inertia
	var ab: float = b.activity/b.inertia if b != null else 0.0
	var relative := velocity_at(b,at)-velocity_at(a,at)
	var closing := relative.dot(normal)
	var denominator := ia+ib+pow(ra.cross(normal),2)*aa+pow(rb.cross(normal),2)*ab
	if denominator <= 0: return 0
	# Tiny resting contacts do not bounce; real impacts retain a little elasticity.
	var impulse := maxf(0,-closing*(1+RESTITUTION if closing < -6 else 1)/denominator)
	apply(a,-normal*impulse,at)
	apply(b,normal*impulse,at)
	var tangent := normal.orthogonal()
	relative = velocity_at(b,at)-velocity_at(a,at)
	var tangential_mass := ia+ib+pow(ra.cross(tangent),2)*aa+pow(rb.cross(tangent),2)*ab
	var friction := clampf(-relative.dot(tangent)/maxf(tangential_mass,0.000001),-impulse*FRICTION,impulse*FRICTION)
	apply(a,-tangent*friction,at)
	apply(b,tangent*friction,at)
	# Position projection is separate from velocity: resolving overlap cannot
	# manufacture a launch impulse. Activity-zero cells act as static boundaries.
	var correction := maxf(0,penetration-0.03)/maxf(ia+ib,0.000001)
	a.position = Medium.wrap_position(a.position-normal*correction*ia)
	if b != null: b.position = Medium.wrap_position(b.position+normal*correction*ib)
	return impulse

static func dent(cell, at: Vector2, depth: float) -> void:
	if cell == null or cell.activity <= 0 or depth <= 0.001: return
	cell.membrane.compress(Medium.offset(cell.position,at).rotated(-cell.angle).angle(),minf(depth,cell.radius*0.075),cell.radius)
	cell.render_revision += 1

static func pair(a, b, dt: float, deform: bool) -> bool:
	var delta := Medium.offset(a.position,b.position)
	if delta.length_squared() > pow(a.extent()+b.extent()+0.2,2): return false
	var radial := delta.normalized() if delta.length_squared() > 0.000001 else Vector2.RIGHT
	var sa := surface(a,radial)
	var sb := surface(b,-radial)
	var gap := Medium.offset(sa.at,sb.at)
	if gap.dot(radial) > 0.15: return false
	var normal: Vector2 = (sa.normal-sb.normal).normalized()
	if normal.dot(radial) < 0.65: normal = radial
	var at: Vector2 = sa.at+gap*0.5
	var depth := maxf(0,-gap.dot(normal))
	var closing := maxf(0,-(velocity_at(b,at)-velocity_at(a,at)).dot(normal))
	solve(a,b,at,normal,depth)
	if deform:
		var compression := minf(minf(a.radius,b.radius)*0.06,depth*0.18+closing*dt*0.65)
		dent(a,sa.at,compression)
		dent(b,sb.at,compression)

	return true
