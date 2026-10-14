shader_type canvas_item;
render_mode unshaded;
uniform sampler2D state_texture : filter_nearest, repeat_disable;
uniform bool cpu_instances = false;
uniform vec4 palette[19];
varying flat float kind;
varying flat vec4 tint;
void vertex(){
 if(cpu_instances){kind=INSTANCE_CUSTOM.r;tint=COLOR;}
 else{
  ivec2 pixel=ivec2((INSTANCE_ID%256)*2,INSTANCE_ID/256);
  vec4 pose=texelFetch(state_texture,pixel,0);
  float radius=texelFetch(state_texture,pixel+ivec2(1,0),0).x;
  kind=pose.w;tint=kind>=0.0?palette[int(kind)]*COLOR:vec4(0.0);
  float co=cos(pose.z),si=sin(pose.z);
  VERTEX=mat2(vec2(co,si),vec2(-si,co))*VERTEX*radius+pose.xy;
 }
 COLOR=vec4(1.0);
}
void fragment(){
 if(kind<0.0)discard;
 vec2 at=(UV-vec2(.5))*4.0;
 float circle=1.0-smoothstep(.85,1.05,length(at));
 float tail=(1.0-smoothstep(.08,.25,abs(at.y)))*step(0.0,at.x)*(1.0-smoothstep(1.3,1.8,at.x));
 if(int(kind)==14||int(kind)==15||int(kind)==17)tail=0.0;
 COLOR=vec4(tint.rgb,tint.a*max(circle,tail));
}
