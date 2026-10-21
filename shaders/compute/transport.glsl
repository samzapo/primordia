#[compute]
#version 450
layout(local_size_x=128,local_size_y=1,local_size_z=1) in;
struct Particle { vec4 pose; vec4 motion; vec4 thermal; };
layout(set=0,binding=0,std430) restrict buffer State { Particle particles[]; };
layout(set=0,binding=1,std430) readonly buffer Flow { vec2 flow[]; };
layout(push_constant,std430) uniform Params { uint count; float dt; uint mouths; float pad1; } params;
const vec2 WORLD=vec2(4096,2560);
int node(ivec2 p) { p=ivec2(mod(vec2(p),vec2(64,40))); return p.y*64+p.x; }
vec2 sample_flow(vec2 p) { vec2 q=mod(p,WORLD)/64.-.5; ivec2 lo=ivec2(floor(q)); vec2 f=fract(q); return mix(mix(flow[node(lo)],flow[node(lo+ivec2(1,0))],f.x),mix(flow[node(lo+ivec2(0,1))],flow[node(lo+ivec2(1,1))],f.x),f.y); }
vec2 transport_flow(vec2 p,int kind) {
 vec2 pull=vec2(0);float strongest=-1.;
 for(uint j=0u;j<params.mouths;j++){
  vec2 d=mod(flow[2560u+j*2u]-p+WORLD*.5,WORLD)-WORLD*.5;
  float distance=length(d),reach=flow[2561u+j*2u].x;
  if(distance>=reach||distance<.000001)continue;
  float speed=flow[2561u+j*2u].y*(1.-distance/reach)*min(1.,distance/24.);
  if(speed>strongest+.0001){strongest=speed;pull=d/distance*speed;}
 }
 return sample_flow(p)+pull*(kind==0?1.:.2);
}
void main(){
 uint i=gl_GlobalInvocationID.x; if(i>=params.count)return;
 Particle p=particles[i]; float dt=params.dt*p.thermal.w; if(dt<=0.)return;
 bool tracer=p.motion.w==3.;
 float diffusion=tracer ? 240. : 12.;
 vec2 launch=tracer ? vec2(0.) : p.motion.xy;
 if(dt<=.05) {
  p.pose.xy=mod(p.pose.xy+(launch+transport_flow(p.pose.xy,int(p.motion.w)))*dt,WORLD);
 } else {
  int steps=clamp(int(ceil(dt/.25)),1,8);
  float h=dt/float(steps), damping=exp(-.8*h);
  for(int j=0;j<steps;j++){
   vec2 midpoint=p.pose.xy+transport_flow(p.pose.xy,int(p.motion.w))*(h*.5)+launch*((1.-exp(-.4*h))/.8);
   p.pose.xy=mod(p.pose.xy+transport_flow(midpoint,int(p.motion.w))*h+launch*((1.-damping)/.8),WORLD);
   launch*=damping;
  }
 }
 p.pose.xy=mod(p.pose.xy+p.thermal.xy*sqrt(diffusion*dt),WORLD);
 p.motion.xy=tracer ? vec2(0.) : p.motion.xy*exp(-dt*.8); p.motion.z+=dt;
 p.pose.z=mod(p.pose.z+p.pose.w*dt+p.thermal.z*sqrt(1.2*dt)+3.14159265359,6.28318530718)-3.14159265359;
 if(tracer)p.pose.z=0.;
 particles[i]=p;
}
