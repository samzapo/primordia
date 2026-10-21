shader_type canvas_item;
render_mode unshaded;
uniform sampler2D state_texture : filter_nearest, repeat_disable;
uniform bool cpu_instances = false;
uniform vec2 body_scale=vec2(1.0);
#include "res://shaders/vacuole_art.gdshaderinc"
uniform sampler2D focus_mask : filter_linear, repeat_disable;
uniform float focus_extent=1.0;
varying vec2 local_position;
varying flat float kind;
varying flat vec3 contents;
void vertex(){
 if(cpu_instances){
  // Metadata uses custom attributes, never color channels (which can be
  // color-space converted by the browser Compatibility renderer).
  kind=max(0.0,-INSTANCE_CUSTOM.r);contents=vec3(INSTANCE_CUSTOM.r,floor(INSTANCE_CUSTOM.a),fract(INSTANCE_CUSTOM.a)*2.0);
  local_position=VERTEX*(kind>0.0?1.4:7.0)+INSTANCE_CUSTOM.gb;
 }else{
  ivec2 pixel=ivec2((INSTANCE_ID%256)*2,INSTANCE_ID/256);
  vec4 pose=texelFetch(state_texture,pixel,0),stock=texelFetch(state_texture,pixel+ivec2(1,0),0);
  contents=stock.gba;kind=pose.w;
  float co=cos(pose.z),si=sin(pose.z);
  VERTEX=mat2(vec2(co,si),vec2(-si,co))*VERTEX*stock.r+pose.xy*body_scale;
  local_position=VERTEX;
 }
 COLOR=vec4(1);
}
void fragment(){
 if(kind<0.0)discard;
 vec2 mask_uv=local_position/(2.0*focus_extent)+vec2(.5);
 if(any(lessThan(mask_uv,vec2(0)))||any(greaterThan(mask_uv,vec2(1)))||texture(focus_mask,mask_uv).r<.5)discard;
 // QuadMesh uses upward V; the shared artwork and Sprite lens use downward V.
 COLOR=kind>0.0?texture(glyph_atlas,vec2((UV.x+(kind<1.5?2.0:3.0))*.25,1.0-UV.y)):vacuole_art(vec2(UV.x,1.0-UV.y),contents);
}
