extends RefCounted
## Local damped membrane playback. No physics steps, RNG or authoritative writes.
const SAMPLES:=64
const DECAY:=9.0
const FREQUENCY:=12.0
var source:=PackedFloat32Array()
var target:=PackedFloat32Array()
var speed:=PackedFloat32Array()
var points:=PackedVector2Array()
var started:=0.0
var last_clock:=-1.0
var clock:=0.0
var softness:=1.0
var phase:=0.0
var texture: ImageTexture
var raster_texture: ImageTexture
var raster_radii:=PackedFloat32Array()
var materials: Array[ShaderMaterial]=[]
var nucleus_lag:=Vector2.ZERO
var lag_velocity:=Vector2.ZERO
var pose:=Transform2D.IDENTITY

static func sample(values: PackedFloat32Array,angle: float) -> float:
 if values.is_empty():return 1.0
 var f:=fposmod(angle,TAU)/TAU*SAMPLES
 var i:=floori(f)
 return lerpf(values[i%SAMPLES],values[(i+1)%SAMPLES],f-i)

static func radii(outline: PackedVector2Array) -> PackedFloat32Array:
 var result:=PackedFloat32Array()
 var angles:=PackedFloat32Array()
 for p in outline:angles.append(fposmod(p.angle(),TAU))
 # Membrane points are in increasing polar order, but the first can straddle 0.
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
 var t:=maxf(0,dt);var delta:=from-to
 var b: float=(velocity+DECAY*delta)/FREQUENCY
 var e:=exp(-DECAY*t);var c:=cos(FREQUENCY*t);var s:=sin(FREQUENCY*t)
 var offset:=e*(delta*c+b*s)
 return Vector2(to+offset,e*((-DECAY*delta+FREQUENCY*b)*c+(-DECAY*b-FREQUENCY*delta)*s))

func bind(material: ShaderMaterial,cached: bool=false) -> void:
 if not materials.has(material):materials.append(material)
 material.set_shader_parameter("gel_cached",cached)
 if texture!=null:material.set_shader_parameter("gel_shape",texture)
 if raster_texture!=null:material.set_shader_parameter("gel_reference",raster_texture)

func _upload() -> void:
 var data:=PackedFloat32Array()
 for i in SAMPLES:data.append_array(PackedFloat32Array([source[i],target[i],speed[i],0]))
 var image:=Image.create_from_data(SAMPLES,1,false,Image.FORMAT_RGBAF,data.to_byte_array())
 if texture==null:texture=ImageTexture.create_from_image(image)
 else:texture.update(image)
 for material in materials:
  material.set_shader_parameter("gel_shape",texture)
  material.set_shader_parameter("gel_started",started)

func capture_raster(outline: PackedVector2Array) -> void:
 raster_radii=radii(outline)
 var image:=Image.create_from_data(SAMPLES,1,false,Image.FORMAT_RF,raster_radii.to_byte_array())
 if raster_texture==null:raster_texture=ImageTexture.create_from_image(image)
 else:raster_texture.update(image)
 for material in materials:material.set_shader_parameter("gel_reference",raster_texture)

func sync(cell,now: float,global_pose: Transform2D) -> void:
 clock=now
 var dt:=maxf(0,now-last_clock) if last_clock>=0 else 0.0
 var reset: bool=last_clock<0 or now<last_clock or dt>1
 phase=fposmod(cell.id*.731,TAU)
 softness=.12 if cell.membrane.cell_wall else .65 if is_finite(cell.membrane.hunter_angle) else 1.0
 if reset or points!=cell.membrane.points:
  var next:=radii(cell.membrane.outline())
  if reset or target.size()!=SAMPLES:
   source=next.duplicate();speed.resize(SAMPLES);speed.fill(0)
  else:
   for i in SAMPLES:
    var state:=spring(source[i],target[i],speed[i],now-started)
    source[i]=clampf(state.x,next[i]*.25,next[i]*4)
    speed[i]=clampf(state.y,-next[i]*2,next[i]*2)
  target=next;points=cell.membrane.points.duplicate();started=now
  _upload()
 if reset:nucleus_lag=Vector2.ZERO;lag_velocity=Vector2.ZERO
 if dt>0 and not reset:
  var wanted: Vector2=(-cell.shape_acceleration.rotated(-cell.angle)*.002+Vector2(0,-cell.angular_velocity)*2).limit_length(4)*softness
  for axis in 2:
   var state:=spring(nucleus_lag[axis],wanted[axis],lag_velocity[axis],dt)
   nucleus_lag[axis]=state.x;lag_velocity[axis]=state.y
 pose=global_pose
 for material in materials:
  material.set_shader_parameter("gel_softness",softness)
  material.set_shader_parameter("gel_phase",phase)
  material.set_shader_parameter("gel_to_cell",global_pose.affine_inverse())
  material.set_shader_parameter("gel_from_cell",global_pose)
 last_clock=now

func radius_at(angle: float) -> float:
 return spring(sample(source,angle),sample(target,angle),sample(speed,angle),clock-started).x

func point(at: Vector2,cached: bool=false) -> Vector2:
 if target.is_empty() or at.length_squared()<.00001:return at
 var a:=at.angle()
 var reference: float=sample(raster_radii if cached and not raster_radii.is_empty() else target,a)
 var ratio:=clampf(radius_at(a)/maxf(1,reference),.25,4.0)
 var wave: float=1+softness*(.018*sin(a*2-clock*2.7+phase)+.010*sin(a*3+clock*3.1+phase*.7))
 return at*ratio*wave

func normal(at: Vector2,direction: Vector2) -> Vector2:
 return (point(at+direction*2)-point(at)).normalized()

func outline(values: PackedVector2Array,cached: bool=false) -> PackedVector2Array:
 var result:=PackedVector2Array()
 for at in values:result.append(point(at,cached))
 return result
