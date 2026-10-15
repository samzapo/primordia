shader_type canvas_item;
render_mode unshaded;
uniform sampler2D state_texture : filter_nearest, repeat_disable;
uniform bool cpu_instances = false;
uniform sampler2D glyph_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D focus_mask : filter_linear, repeat_disable;
uniform float focus_extent=1.0;
varying vec2 local_position;
varying flat float kind;
varying flat vec4 tint;
void vertex(){
 if(cpu_instances){kind=floor(INSTANCE_CUSTOM.r);tint=COLOR;float angle=fract(INSTANCE_CUSTOM.r)*12.5663706144;local_position=mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*VERTEX*INSTANCE_CUSTOM.a+INSTANCE_CUSTOM.gb;}
 else{
  ivec2 pixel=ivec2((INSTANCE_ID%256)*2,INSTANCE_ID/256);
  vec4 pose=texelFetch(state_texture,pixel,0);
  float radius=texelFetch(state_texture,pixel+ivec2(1,0),0).x;
  kind=pose.w;tint=kind>=0.0?vec4(1.0):vec4(0.0);
  float co=cos(pose.z),si=sin(pose.z);
  VERTEX=mat2(vec2(co,si),vec2(-si,co))*VERTEX*radius+pose.xy;
 }
 if(!cpu_instances)local_position=VERTEX;
 COLOR=vec4(1.0);
}
void fragment(){
 if(kind<0.0)discard;
 vec2 mask_uv=local_position/(2.0*focus_extent)+vec2(.5);
 if(any(lessThan(mask_uv,vec2(0)))||any(greaterThan(mask_uv,vec2(1)))||texture(focus_mask,mask_uv).r<.5)discard;
 COLOR=texture(glyph_atlas,vec2((UV.x+(int(kind)==0?0.0:1.0))*.5,UV.y))*tint;
}
