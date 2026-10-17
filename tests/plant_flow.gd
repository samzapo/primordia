extends RefCounted
const Medium=preload("res://scripts/medium.gd")
const Habitat=preload("res://scripts/habitat.gd")
static func run(check: Callable) -> void:
 var habitat=Habitat.new(44)
 habitat.plants=[{"p":Vector2(4090,1280),"radius":100.0,"form":0,"angle":0.0}]
 habitat.forms=[{"branches":[{"a":Vector2(-50,0),"b":Vector2(50,0),"r":14.0,"depth":1}]}]
 habitat.rebuild()
 var medium=Medium.new();medium.driven=false
 check.call(medium.current(Vector2.ZERO)==Vector2(11,0),"Ambient current retains its original strength while vegetation supplies local drag")
 medium.set_plants(habitat)
 check.call(Array(medium.plant_drag).max()>0,"Existing plant branches create a nonzero porous water drag")
 var node:=Medium.index(63,19)
 var at:=Vector2(63.5,19.5)*Medium.SIZE
 var a: Vector2=habitat.plants[0].p+habitat.forms[0].branches[0].a
 var b: Vector2=habitat.plants[0].p+habitat.forms[0].branches[0].b
 var nearest: Vector2=a+(b-a)*clampf((at-a).dot(b-a)/(b-a).length_squared(),0,1)
 var legacy_drag: float=.9*(28.0/Medium.SIZE)*clampf((14+Medium.SIZE*.55-at.distance_to(nearest))/(Medium.SIZE*.55),0,1)
 check.call(absf(medium.plant_drag[node]-legacy_drag*.5)<.000001 and legacy_drag>0,"Measured branch drag is exactly half the previous dissipation coefficient")
 var original: PackedFloat32Array=medium.plant_drag.duplicate()
 habitat.plants[0].p.x+=Medium.WORLD.x;habitat.rebuild();medium.set_plants(habitat)
 check.call(medium.plant_drag==original,"Vegetation damping wraps consistently at pond seams")
 medium.velocity.fill(Vector2(40,-10));medium.activity.fill(1)
 var before: PackedVector2Array=medium.velocity.duplicate()
 var expected:=PackedVector2Array()
 if medium.kernels!=null:expected=medium.kernels.fluid_step(before,medium.activity,medium.tide,.25,false,medium.plant_drag)
 medium.step(.25)
 var energy_before:=0.0;var energy_after:=0.0;var error:=0.0
 for i in before.size():
  energy_before+=before[i].length_squared();energy_after+=medium.velocity[i].length_squared()
  if not expected.is_empty():error=maxf(error,medium.velocity[i].distance_to(expected[i]))
 check.call(energy_after<energy_before and Array(medium.velocity).all(func(v):return v.is_finite()),"Anchored plants dissipate water motion without numerical growth")
 if not expected.is_empty():check.call(error<.0001,"Native and reference vegetation drag agree at the coarse interval")
 var open_index:=Medium.index(20,10)
 check.call(medium.velocity[open_index]==before[open_index],"Open water receives no artificial global speed cap")
 medium.velocity=before.duplicate();medium.activity.fill(0);medium.step(.25)
 check.call(medium.velocity==before,"Inactive foreground nodes are left for the offscreen complement")
 habitat.enabled=false;medium.set_plants(habitat)
 check.call(Array(medium.plant_drag).max()==0,"Disabled habitat clears drag instead of leaving stale obstacles")
 habitat.enabled=true;medium.set_plants(habitat)
 check.call(medium.plant_drag==original,"Re-enabled habitat rebuilds the same geometric damping")
 check.call(habitat.particles_permeable,"Fluid drag leaves chemical particles permeable to stems")
 # Stress the real conservative pump/body coupling through repeated coarse steps.
 var body=preload("res://scripts/cell.gd").new(7,Vector2(4090,1280))
 body.update_geometry();medium.velocity.fill(Vector2(300,-160));medium.activity.fill(1)
 var peak:=0.0
 for step in 240:
  medium.suction(body,body.position+Vector2(65,0),130,24,.25)
  if medium.kernels!=null:medium.velocity=medium.kernels.fluid_body_exchange(medium.velocity,medium.activity,body,.25,true)
  else:
   for j in 6:medium.exchange(body,Vector2.from_angle(j*TAU/6)*body.radius,.25,body.fluid_drag()/6)
  medium.step(.25)
  for v in medium.velocity:peak=maxf(peak,v.length())
 check.call(peak<350 and body.velocity.is_finite() and is_finite(body.angular_velocity),"A minute of coarse pumping and body exchange stays bounded from a large finite incoming current")
 check.call(medium.metrics().speed_max<before[0].length()*9,"Vegetated flow relaxes rather than accelerating under repeated coupling")
