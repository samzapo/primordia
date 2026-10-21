extends RefCounted
## One small area-preserving squash/stretch. Map anchors, never organ artwork.
const SAMPLES:=64
const AMPLITUDE:=.006
const RATE:=12.0
var points:=PackedVector2Array()
var target:=PackedFloat32Array()
var raster_radii:=PackedFloat32Array()
var cached:=false
var clock:=0.0
var softness:=1.0
var phase:=0.0
var deformation:=Transform2D.IDENTITY
var nucleus_lag:=Vector2.ZERO # All internals follow anchors without independent lag.

static func sample(values: PackedFloat32Array,angle: float) -> float:
 if values.is_empty():return 1.0
 var f:=fposmod(angle,TAU)/TAU*SAMPLES
 var i:=floori(f)
 return lerpf(values[i%SAMPLES],values[(i+1)%SAMPLES],f-i)

static func radii(outline: PackedVector2Array) -> PackedFloat32Array:
 var result:=PackedFloat32Array()
 var angles:=PackedFloat32Array()
 for p in outline:angles.append(fposmod(p.angle(),TAU))
 if outline.is_empty():
  result.resize(SAMPLES);result.fill(1);return result
 var first:=0
 for i in angles.size():
  if angles[i]<angles[first]:first=i
 var n:=outline.size();var edge:=0
 for i in SAMPLES:
  var a:=TAU*i/SAMPLES
  while edge+1<n and angles[(first+edge+1)%n]<=a:edge+=1
  var left: int=(first+edge)%n;var right: int=(left+1)%n
  var low: float=angles[left];var high: float=angles[right]
  if a<angles[first]:left=posmod(first-1,n);right=first;low=angles[left]-TAU;high=angles[right]
  elif high<=low:high+=TAU
  result.append(maxf(1,lerpf(outline[left].length(),outline[right].length(),clampf((a-low)/maxf(.0001,high-low),0,1))))
 return result

static func spring(from: float,to: float,velocity: float,dt: float) -> Vector2:
 # Critically damped layout easing, with no oscillatory overshoot.
 var t:=maxf(0,dt);var delta:=from-to;var b:=velocity+RATE*delta
 var e:=exp(-RATE*t)
 return Vector2(to+(delta+b*t)*e,(velocity-RATE*b*t)*e)

func sync(cell,now: float,_global_pose: Transform2D) -> void:
 clock=now;phase=fposmod(cell.id*.731,TAU)
 softness=.12 if cell.membrane.cell_wall else .65 if is_finite(cell.membrane.hunter_angle) else 1.0
 var stretch:=exp(AMPLITUDE*softness*sin(now*2.6+phase))
 deformation=Transform2D(0,Vector2(stretch,1/stretch),0,Vector2.ZERO)
 if points!=cell.membrane.points:
  target=radii(cell.membrane.outline());points=cell.membrane.points.duplicate()

func capture_raster(outline: PackedVector2Array) -> void:raster_radii=radii(outline)

func reference_point(at: Vector2,already_cached: bool=false) -> Vector2:
 # Outside-cache appendages must mount on the displayed cached outline until
 # its bounded FIFO refresh catches up, rather than on a newer server shape.
 if not cached or already_cached or target.is_empty() or raster_radii.is_empty():return at
 var angle:=at.angle()
 return at*sample(raster_radii,angle)/maxf(1,sample(target,angle))

func point(at: Vector2,already_cached: bool=false) -> Vector2:
 return deformation*reference_point(at,already_cached)

func normal(at: Vector2,direction: Vector2) -> Vector2:
 # Inverse transpose preserves the surface normal under squash/stretch.
 var inverse:=deformation.affine_inverse()
 return Vector2(inverse.x.dot(direction),inverse.y.dot(direction)).normalized()

func outline(values: PackedVector2Array,already_cached: bool=false) -> PackedVector2Array:
 var result:=PackedVector2Array()
 for at in values:result.append(point(at,already_cached))
 return result
