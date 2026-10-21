shader_type canvas_item;
render_mode unshaded;
uniform sampler2D state_texture : filter_nearest, repeat_disable;
uniform bool cpu_instances = false;
uniform vec2 camera = vec2(2048.0,1280.0);
varying flat float species;
varying flat vec4 signal_tint;
uniform sampler2D signal_lineage_texture : filter_nearest, repeat_disable;
uniform sampler2D signal_palette : filter_nearest, repeat_disable;
uniform bool family_tints = false;
vec4 family_color(vec2 key){
 int slots=textureSize(signal_palette,0).x/2;
 if(slots<1)return vec4(1.,1.,1.,.65);
 uint root=uint(key.x)|(uint(key.y)<<uint(16));
 uint slot=(root*2654435761u)&uint(slots-1);
 for(int i=0;i<2048;i++){
  vec4 held=texelFetch(signal_palette,ivec2(int(slot)*2,0),0);
  if(held.a<.5)break;
  if(all(equal(held.xy,key)))return texelFetch(signal_palette,ivec2(int(slot)*2+1,0),0);
  slot=(slot+1u)&uint(slots-1);
 }
 return vec4(1.,1.,1.,.65);
}
void vertex() {
 if (cpu_instances) {
  species=round(COLOR.r*25.0);
 } else {
  ivec2 pixel=ivec2((INSTANCE_ID%256)*3,INSTANCE_ID/256);
  vec4 pose=texelFetch(state_texture,pixel,0);
  vec4 motion=texelFetch(state_texture,pixel+ivec2(1,0),0);
  float diameter=texelFetch(state_texture,pixel+ivec2(2,0),0).x;
  vec2 at=mod(pose.xy-camera+vec2(2048.0,1280.0),vec2(4096.0,2560.0))-vec2(2048.0,1280.0);
  float co=cos(pose.z),si=sin(pose.z);
  VERTEX=mat2(vec2(co,si),vec2(-si,co))*VERTEX*diameter+at;
  species=motion.w;
 }
 signal_tint=vec4(1.,1.,1.,.65);
 if(species==3.0 && family_tints)signal_tint=family_color(texelFetch(signal_lineage_texture,ivec2(INSTANCE_ID%256,INSTANCE_ID/256),0).xy);
 COLOR=vec4(1.0);
}
void fragment() {
 if(species<0.0)discard;
 vec2 uv=vec2((UV.x+species)/26.0,UV.y);
 COLOR=texture(TEXTURE,uv);
 if(species==3.0)COLOR*=signal_tint;
 else if(species==1.0)COLOR.a*=.6;
}
