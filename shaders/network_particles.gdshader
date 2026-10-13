shader_type canvas_item;
render_mode unshaded;
uniform sampler2D state_texture : filter_nearest, repeat_disable;
uniform sampler2D previous_texture : filter_nearest, repeat_disable;
uniform sampler2D bodies_texture : filter_nearest, repeat_disable;
uniform sampler2D outlines_texture : filter_nearest, repeat_disable;
uniform int body_count = 0;
uniform float interpolation = 1.0;
uniform vec2 camera = vec2(2048.0,1280.0);
varying flat float species;
const vec2 WORLD = vec2(4096.0,2560.0);
vec2 offset(vec2 a,vec2 b){return mod(b-a+WORLD*.5,WORLD)-WORLD*.5;}
float turn(float a,float b){return a+mod(b-a+3.14159265,6.2831853)-3.14159265;}
float cross2(vec2 a,vec2 b){return a.x*b.y-a.y*b.x;}
vec2 outline_point(int index){return texelFetch(outlines_texture,ivec2(index%256,index/256),0).xy;}
vec2 exclude_bodies(vec2 at){
 for(int b=0;b<64;b++){
  if(b>=body_count)break;
  vec4 pose=texelFetch(bodies_texture,ivec2(0,b),0);
  vec4 prior=texelFetch(bodies_texture,ivec2(1,b),0);
  vec4 shape=texelFetch(bodies_texture,ivec2(2,b),0);
  vec2 center=prior.xy+offset(prior.xy,pose.xy)*interpolation;
  vec2 d=offset(center,at);
  if(dot(d,d)>pow(pose.w+8.0,2.0))continue;
  float heading=turn(prior.z,pose.z);
  heading=mix(prior.z,heading,interpolation);
  float a=atan(d.y,d.x)-heading;
  vec2 ray=vec2(cos(a),sin(a));
  float support=pose.w;int start=int(shape.x),n=int(shape.y);
  for(int j=0;j<512;j++){
   if(j>=n)break;
   vec2 p=outline_point(start+j),q=outline_point(start+(j+1)%n);
   vec2 edge=q-p;float denominator=cross2(ray,edge);
   if(abs(denominator)<0.000001)continue;
   float t=cross2(p,ray)/denominator;
   float r=cross2(p,edge)/denominator;
   if(t>=0.0 && t<=1.0 && r>=0.0){support=length(mix(p,q,t));break;}
  }
  float distance=length(d);
  if(distance<support+7.0)at=center+vec2(cos(atan(d.y,d.x)),sin(atan(d.y,d.x)))*(support+7.0);
 }
 return at;
}
void vertex(){
 ivec2 pixel=ivec2((INSTANCE_ID%256)*2,INSTANCE_ID/256);
 vec4 current=texelFetch(state_texture,pixel,0);
 vec4 data=texelFetch(state_texture,pixel+ivec2(1,0),0);
 vec4 prior=texelFetch(previous_texture,ivec2(INSTANCE_ID%256,INSTANCE_ID/256),0);
 vec2 at=prior.xy+offset(prior.xy,current.xy)*interpolation;
 species=data.x;
 if(species!=3.0)at=exclude_bodies(at);
 float heading=mix(prior.z,turn(prior.z,current.z),interpolation);
 float size=mix(prior.w,current.w,interpolation);
 float co=cos(heading),si=sin(heading);
 VERTEX=mat2(vec2(co,si),vec2(-si,co))*VERTEX*size+offset(camera,at);
 COLOR=vec4(1.0);
}
void fragment(){
 if(species<0.0)discard;
 COLOR=texture(TEXTURE,vec2((UV.x+species)/26.0,UV.y));
 COLOR.a*=species==1.0 || species==3.0 ? .6 : 1.0;
}
