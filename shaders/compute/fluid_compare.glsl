#[compute]
#version 450
// Experimental full-torus solvers. Water particles are not chemical packets.
layout(local_size_x=128) in;
layout(set=0,binding=0,std430) buffer State { vec4 a[]; };
layout(set=0,binding=1,std430) buffer Scratch { vec4 b[]; };
layout(set=0,binding=2,std430) buffer Boundary { vec4 wall[]; };
layout(set=0,binding=3,std430) buffer Spatial { int links[]; };
layout(set=0,binding=4,std430) buffer Constraints { vec4 aux[]; };
layout(set=0,binding=5,std430) buffer Exchange { vec4 field[]; };
layout(set=0,binding=6,std430) readonly buffer Geometry { vec4 shape[]; };
layout(set=0,binding=7,std430) buffer Feedback { vec4 feedback[]; };
layout(set=0,binding=8,std430) buffer WallImpulse { vec4 contact[]; };
layout(set=0,binding=9,std430) buffer FeedbackParts { vec4 parts[]; };
shared vec4 force_sum[128];
layout(push_constant,std430) uniform Params {
 uint op; uint count; uint cols; uint rows;
 float dx; float dt; float viscosity; float density;
 uint ping; uint bodies; uint driven; uint model;
 float spacing; float rest_density; float relaxation; float padding;
} p;
const vec2 WORLD=vec2(4096,2560);
const float PI=3.141592653589793;
const float H=32.;
const int BC=128, BR=80, BINS=BC*BR;
vec2 wrap_pos(vec2 x){return mod(x,WORLD);}
vec2 delta(vec2 x,vec2 y){return mod(y-x+WORLD*.5,WORLD)-WORLD*.5;}
int node(ivec2 c){return ((c.y+int(p.rows))%int(p.rows))*int(p.cols)+(c.x+int(p.cols))%int(p.cols);}
ivec2 coord(uint i){return ivec2(i%p.cols,i/p.cols);}
vec2 center(uint i){return (vec2(coord(i))+.5)*p.dx;}
int bin(vec2 x){ivec2 c=ivec2(floor(wrap_pos(x)/H));return ((c.y%BR+BR)%BR)*BC+(c.x%BC+BC)%BC;}
vec2 tide(vec2 x){return vec2(11.+17.*sin(8.*PI*x.y/WORLD.y),15.*sin(8.*PI*x.x/WORLD.x));}
vec2 coarse_delta(vec2 x){
 vec2 q=wrap_pos(x)/64.-.5;ivec2 c=ivec2(floor(q));vec2 f=fract(q);
 int i00=((c.y%40+40)%40)*64+(c.x%64+64)%64;
 int i10=i00/64*64+(c.x+1+64)%64;
 int i01=((c.y+1+40)%40)*64+(c.x+64)%64;
 int i11=i01/64*64+(c.x+1+64)%64;
 return mix(mix(field[i00].xy,field[i10].xy,f.x),mix(field[i01].xy,field[i11].xy,f.x),f.y);
}
vec2 wall_velocity(int id,vec2 x){
 if(id<=0)return vec2(0);
 vec4 pose=shape[1+(id-1)*3],v=shape[2+(id-1)*3];
 vec2 arm=delta(pose.xy,x);
 return v.xy+v.z*vec2(-arm.y,arm.x);
}
vec4 geometry(vec2 x){
 float sd=100000.;vec2 norm=vec2(1,0);float owner=0.;
 for(uint k=0;k<p.bodies;k++){
  vec4 pose=shape[1+k*3],range=shape[3+k*3];vec2 local=delta(pose.xy,x);
  if(length(local)>pose.z+H && sd<H)continue;
  bool inside=false;float best=100000.;vec2 normal=vec2(1,0);
  for(int j=0;j<int(range.y);j++){
   vec4 line=shape[int(range.x)+j];vec2 v=line.zw-line.xy;
   float t=clamp(dot(local-line.xy,v)/max(dot(v,v),.00001),0.,1.);
   vec2 diff=local-line.xy-v*t;float d=length(diff);
   if(d<best){best=d;normal=d>.0001?diff/d:normalize(vec2(v.y,-v.x));}
   if((line.y>local.y)!=(line.w>local.y) && local.x<(line.z-line.x)*(local.y-line.y)/(line.w-line.y)+line.x)inside=!inside;
  }
  if(inside){best=-best;normal=-normal;}
  if(best<sd){sd=best;norm=normal;owner=float(k+1);}
 }
 int start=int(shape[0].z),segments=int(shape[0].y);
 for(int j=0;j<segments;j++){
  vec4 line=shape[start+j*2];float r=shape[start+j*2+1].x;
  vec2 v=delta(line.xy,line.zw),local=delta(line.xy,x);
  float t=clamp(dot(local,v)/max(dot(v,v),.00001),0.,1.);
  vec2 diff=local-v*t;float d=length(diff)-r;
  if(d<sd){sd=d;norm=length(diff)>.0001?normalize(diff):vec2(1,0);owner=-1.;}
 }
 return vec4(sd,norm,owner);
}
vec4 sample_wall(vec2 x){
 vec2 q=wrap_pos(x)/p.dx-.5;ivec2 c=ivec2(floor(q));vec2 f=fract(q);
 float sd=mix(mix(wall[node(c)].x,wall[node(c+ivec2(1,0))].x,f.x),
              mix(wall[node(c+ivec2(0,1))].x,wall[node(c+ivec2(1,1))].x,f.x),f.y);
 vec4 nearest=wall[node(ivec2(round(q)))];
 // SDF gradient interpolation, ownership stays discrete.
 vec2 n=mix(mix(wall[node(c)].yz,wall[node(c+ivec2(1,0))].yz,f.x),
            mix(wall[node(c+ivec2(0,1))].yz,wall[node(c+ivec2(1,1))].yz,f.x),f.y);
 return vec4(sd,length(n)>.0001?normalize(n):nearest.yz,nearest.w);
}
bool solid(int i){return wall[i].x<0.;}
float component(int at,int axis){return axis==0?a[at].x:a[at].y;}
vec2 mac_sample(vec2 x){
 vec2 result=vec2(0);
 for(int axis=0;axis<2;axis++){
  vec2 q=wrap_pos(x)/p.dx-vec2(axis==0?1.:.5,axis==1?1.:.5);
  ivec2 c=ivec2(floor(q));vec2 f=fract(q);
  float value=mix(mix(component(node(c),axis),component(node(c+ivec2(1,0)),axis),f.x),
                   mix(component(node(c+ivec2(0,1)),axis),component(node(c+ivec2(1,1)),axis),f.x),f.y);
  if(axis==0)result.x=value;else result.y=value;
 }
 return result;
}
float kernel(float r){
 if(r>=H)return 0.;
 float t=H*H-r*r;return 4./(PI*pow(H,8.))*t*t*t;
}
vec2 gradient(vec2 d){
 float r=length(d);if(r<.0001 || r>=H)return vec2(0);
 return -30./(PI*pow(H,5.))*(H-r)*(H-r)*d/r;
}
void main(){
 uint i=gl_GlobalInvocationID.x;
 if(p.op==0u){if(i<p.cols*p.rows){wall[i]=geometry(center(i));wall[i].x-=p.spacing*.25;}return;}
 if(p.op==1u){ // MAC advection, viscous diffusion, common external impulse field.
  if(i>=p.cols*p.rows)return;ivec2 c=coord(i);
  vec2 v=a[i].xy,advected;
  for(int axis=0;axis<2;axis++){
   vec2 x=center(i)+vec2(axis==0?p.dx*.5:0.,axis==1?p.dx*.5:0.);
   vec2 u=mac_sample(x);vec2 mid=x-u*p.dt*.5;
   vec2 sampled=mac_sample(x-mac_sample(mid)*p.dt);
   if(axis==0)advected.x=sampled.x;else advected.y=sampled.y;
  }
  vec2 lap=a[node(c+ivec2(1,0))].xy+a[node(c-ivec2(1,0))].xy+
           a[node(c+ivec2(0,1))].xy+a[node(c-ivec2(0,1))].xy-4.*v;
  advected+=lap*(p.viscosity*p.dt/(p.dx*p.dx));
  advected+=coarse_delta(center(i));
  if(p.driven!=0u)advected+=(tide(center(i))-advected)*(1.-exp(-p.dt*.12));
  for(int axis=0;axis<2;axis++){
   int other=node(c+(axis==0?ivec2(1,0):ivec2(0,1)));
   if(solid(int(i))||solid(other)){
    int id=solid(int(i))?int(wall[i].w):int(wall[other].w);
    vec2 value=wall_velocity(id,center(i));
    if(axis==0)advected.x=value.x;else advected.y=value.y;
   }
  }
  b[i]=vec4(advected,0,0);return;
 }
 if(p.op==2u){ // divergence and zero initial pressure
  if(i>=p.cols*p.rows)return;ivec2 c=coord(i);
  float div=solid(int(i))?0.:(b[i].x-b[node(c-ivec2(1,0))].x+
                                 b[i].y-b[node(c-ivec2(0,1))].y)/p.dx;
  aux[i]=vec4(0,0,div,0);return;
 }
 if(p.op==3u){
  if(i>=p.cols*p.rows)return;ivec2 c=coord(i);float sum=0.,n=0.;
  for(int axis=0;axis<4;axis++){
   ivec2 d=axis==0?ivec2(1,0):axis==1?ivec2(-1,0):axis==2?ivec2(0,1):ivec2(0,-1);
   int j=node(c+d);if(!solid(j)){sum+=p.ping==0u?aux[j].x:aux[j].y;n++;}
  }
  float pressure=(solid(int(i))||n==0.)?0.:(sum-p.density*p.dx*p.dx/p.dt*aux[i].z)/n;
  pressure=mix(p.ping==0u?aux[i].x:aux[i].y,pressure,.8);
  if(p.ping==0u)aux[i].y=pressure;else aux[i].x=pressure;return;
 }
 if(p.op==4u){
  if(i>=p.cols*p.rows)return;ivec2 c=coord(i);vec2 v=b[i].xy;
  for(int axis=0;axis<2;axis++){
   int j=node(c+(axis==0?ivec2(1,0):ivec2(0,1)));
   if(!solid(int(i))&&!solid(j)){
    float change=p.dt/(p.density*p.dx)*(aux[j].x-aux[i].x);
    if(axis==0)v.x-=change;else v.y-=change;
   }
  }
  a[i].xy=v;return;
 }
 if(p.op==10u){
  if(i>=p.count)return;vec2 v=a[i].zw+coarse_delta(a[i].xy);
  if(p.driven!=0u)v+=(tide(a[i].xy)-v)*(1.-exp(-p.dt*.12));
  b[i]=vec4(wrap_pos(a[i].xy+v*p.dt),v);
  contact[i]=vec4(0);return;
 }
 if(p.op==11u){if(i<BINS)links[i]=-1;return;}
 if(p.op==12u){
  if(i>=p.count)return;int at=bin(b[i].xy);
  links[BINS+int(i)]=atomicExchange(links[at],int(i));return;
 }
 if(p.op==13u){
  if(i>=p.count)return;float rho=0.,sumgrad=0.;vec2 own=vec2(0);
  ivec2 c=ivec2(floor(b[i].xy/H));
  for(int yy=-1;yy<=1;yy++)for(int xx=-1;xx<=1;xx++){
   int head=((c.y+yy+BR)%BR)*BC+(c.x+xx+BC)%BC;
   for(int j=links[head];j>=0;j=links[BINS+j]){
    vec2 d=delta(b[j].xy,b[i].xy);rho+=p.density*p.spacing*p.spacing*kernel(length(d));
    if(j!=int(i)){vec2 g=p.density*p.spacing*p.spacing/p.rest_density*gradient(d);sumgrad+=dot(g,g);own+=g;}
   }
  }
  // Compression-only constraint avoids tensile attraction in the unresolved
  // boundary layer. Report missing neighbors/density deficit as solver error.
  float constraint=max(rho/p.rest_density-1.,0.);
  aux[i].x=-constraint/(sumgrad+dot(own,own)+.00001);
  aux[i].y=rho/p.rest_density;return;
 }
 if(p.op==14u){
  if(i>=p.count)return;vec2 correction=vec2(0);ivec2 c=ivec2(floor(b[i].xy/H));
  for(int yy=-1;yy<=1;yy++)for(int xx=-1;xx<=1;xx++){
   int head=((c.y+yy+BR)%BR)*BC+(c.x+xx+BC)%BC;
   for(int j=links[head];j>=0;j=links[BINS+j]){
    if(j==int(i))continue;vec2 d=delta(b[j].xy,b[i].xy);
    correction+=(aux[i].x+aux[j].x)*p.density*p.spacing*p.spacing/p.rest_density*gradient(d);
   }
  }
  aux[i].zw=wrap_pos(b[i].xy+correction*p.relaxation);return;
 }
 if(p.op==15u){
  if(i>=p.count)return;vec2 x=aux[i].zw;vec4 surface=sample_wall(x);
  if(surface.x<0.){
   vec2 correction=surface.yz*(-surface.x);
   x=wrap_pos(x+correction);
   vec2 impulse=correction*(p.density*p.spacing*p.spacing/p.dt);
   int id=int(surface.w);
   vec2 arm=id>0?delta(shape[1+(id-1)*3].xy,x):vec2(0);
   contact[i].xy-=impulse;contact[i].z-=arm.x*impulse.y-arm.y*impulse.x;
   contact[i].w=float(id);
  }
  b[i].xy=x;return;
 }
 if(p.op==18u){if(i<p.count)aux[i].xy=contact[i].xy;return;}
 if(p.op==16u){
  if(i>=p.count)return;
  float mass=p.density*p.spacing*p.spacing;
  // Remove purely geometric depenetration from reconstructed velocity. Then
  // resolve actual incoming wall velocity and return its opposite impulse.
  vec2 v=delta(a[i].xy,b[i].xy)/p.dt+aux[i].xy/mass;
  vec4 surface=sample_wall(b[i].xy);vec2 old_v=v;
  if(surface.x<p.spacing*.5){
   vec2 relative=v-wall_velocity(int(surface.w),b[i].xy);
   float closing=dot(relative,surface.yz);
   if(closing<0.)v-=surface.yz*closing;
  }
  vec2 impulse=-(v-old_v)*mass;
  int owner=int(surface.w);vec2 arm=owner>0?delta(shape[1+(owner-1)*3].xy,b[i].xy):vec2(0);
  contact[i]=vec4(impulse,arm.x*impulse.y-arm.y*impulse.x,float(owner));
  vec2 smoothed=vec2(0);float weight=0.;
  ivec2 c=ivec2(floor(b[i].xy/H));
  for(int yy=-1;yy<=1;yy++)for(int xx=-1;xx<=1;xx++){
   int head=((c.y+yy+BR)%BR)*BC+(c.x+xx+BC)%BC;
   for(int j=links[head];j>=0;j=links[BINS+j]){
    float w=kernel(length(delta(b[j].xy,b[i].xy)));
    vec2 neighbor=delta(a[j].xy,b[j].xy)/p.dt+aux[j].xy/mass;
    smoothed+=w*neighbor;weight+=w;
   }
  }
  // This pass writes scratch only: final velocities may not race neighbor reads.
  aux[i].zw=mix(v,weight>0.?smoothed/weight:v,
                 clamp(p.viscosity*p.dt/(p.spacing*p.spacing),0.,.25));return;
 }
 if(p.op==17u){if(i<p.count)a[i]=vec4(b[i].xy,aux[i].zw);return;}
 if(p.op==30u){if(i<p.count)b[i]=a[i];return;}
 if(p.op==20u){ // Common 64x40 CPU-cell/chemistry exchange, 40 KiB per tick.
  if(i>=2560u)return;vec2 x=vec2(i%64u,i/64u)*64.+32.,v=vec2(0);float weight=0.;
  if(p.model==0u)v=mac_sample(x);
  else{
   ivec2 c=ivec2(floor(x/H));
   for(int yy=-1;yy<=1;yy++)for(int xx=-1;xx<=1;xx++){
    int head=((c.y+yy+BR)%BR)*BC+(c.x+xx+BC)%BC;
    for(int j=links[head];j>=0;j=links[BINS+j]){
     float w=kernel(length(delta(b[j].xy,x)));v+=a[j].zw*w;weight+=w;
    }
   }
   v=weight>0.?v/weight:wall_velocity(int(sample_wall(x).w),x);
  }
  field[i]=vec4(v,0,0);return;
 }

 if(p.op==21u){ // Parallel body impulse chunks; fixed-order tree, no float atomics.
  uint samples=p.model==0u?p.cols*p.rows:p.count;
  uint chunks=(samples+127u)/128u;
  uint body=gl_WorkGroupID.x/chunks, chunk=gl_WorkGroupID.x%chunks;
  uint j=chunk*128u+gl_LocalInvocationID.x;
  vec3 impulse=vec3(0);
  if(body<p.bodies && j<samples){
   if(p.model==0u){
    if(!solid(int(j))){
     ivec2 c=coord(j);
     for(int axis=0;axis<4;axis++){
      ivec2 d=axis==0?ivec2(1,0):axis==1?ivec2(-1,0):axis==2?ivec2(0,1):ivec2(0,-1);
      int k=node(c+d);
      if(solid(k)&&int(wall[k].w)==int(body)+1){
       vec2 force=vec2(d)*aux[j].x*p.dx*p.dt;
       vec2 arm=delta(shape[1+body*3].xy,center(j)+vec2(d)*p.dx*.5);
       impulse+=vec3(force,arm.x*force.y-arm.y*force.x);
      }
     }
    }
   }else if(int(contact[j].w)==int(body)+1)impulse=contact[j].xyz;
  }
  force_sum[gl_LocalInvocationID.x]=vec4(impulse,0);
  barrier();
  for(uint width=64u;width>0u;width/=2u){
   if(gl_LocalInvocationID.x<width)force_sum[gl_LocalInvocationID.x]+=force_sum[gl_LocalInvocationID.x+width];
   barrier();
  }
  if(gl_LocalInvocationID.x==0u && body<p.bodies)parts[body*chunks+chunk]=force_sum[0];
  return;
 }
 if(p.op==22u){
  if(i>=p.bodies)return;
  uint samples=p.model==0u?p.cols*p.rows:p.count,chunks=(samples+127u)/128u;
  vec4 impulse=vec4(0);
  for(uint j=0u;j<chunks;j++)impulse+=parts[i*chunks+j];
  feedback[i]=impulse;return;
 }
}
