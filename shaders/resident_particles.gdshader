shader_type canvas_item;
render_mode unshaded;
uniform sampler2D state_texture : filter_nearest, repeat_disable;
uniform bool cpu_instances = false;
uniform vec2 camera = vec2(2048.0,1280.0);
varying flat float species;
void vertex() {
 if (cpu_instances) {
  species=round(COLOR.r*10.0);
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
 COLOR=vec4(1.0);
}
void fragment() {
 vec2 uv=vec2((UV.x+species)/11.0,UV.y);
 COLOR=texture(TEXTURE,uv);
 COLOR.a*= (species==1.0 || species==3.0) ? 0.6 : 1.0;
}
