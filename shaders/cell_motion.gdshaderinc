// Shared CPU/GPU presentation mapping; server membrane and collision state stay untouched.
global uniform float primordia_cosmetic_clock;
uniform sampler2D gel_shape : filter_nearest, repeat_enable;
uniform sampler2D gel_reference : filter_nearest, repeat_enable;
uniform float gel_started=0.0;
uniform float gel_softness=1.0;
uniform float gel_phase=0.0;
uniform bool gel_enabled=false;
uniform bool gel_cached=false;
uniform mat3 gel_to_cell=mat3(1.0);
uniform mat3 gel_from_cell=mat3(1.0);
vec4 gel_sample(sampler2D data,float a){
 float f=mod(a+6.283185307,6.283185307)/6.283185307*64.0;
 int i=int(floor(f));
 return mix(texelFetch(data,ivec2(i%64,0),0),texelFetch(data,ivec2((i+1)%64,0),0),fract(f));
}
vec2 gel_point(vec2 p){
 if(!gel_enabled || dot(p,p)<.00001)return p;
 float a=atan(p.y,p.x);
 vec4 data=gel_sample(gel_shape,a);
 float t=max(0.0,primordia_cosmetic_clock-gel_started);
 float delta=data.r-data.g;
 float b=(data.b+9.0*delta)/12.0;
 float radius=data.g+exp(-9.0*t)*(delta*cos(12.0*t)+b*sin(12.0*t));
 float reference=gel_cached?gel_sample(gel_reference,a).r:data.g;
 float ratio=clamp(radius/max(1.0,reference),.25,4.0);
 float wave=1.0+gel_softness*(.018*sin(a*2.0-primordia_cosmetic_clock*2.7+gel_phase)+.010*sin(a*3.0+primordia_cosmetic_clock*3.1+gel_phase*.7));
 return p*ratio*wave;
}
vec2 gel_world_point(vec2 p){
 if(!gel_enabled)return p;
 return (gel_from_cell*vec3(gel_point((gel_to_cell*vec3(p,1.0)).xy),1.0)).xy;
}
