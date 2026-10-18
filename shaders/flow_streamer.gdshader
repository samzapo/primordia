shader_type canvas_item;
render_mode unshaded;
uniform sampler2D curve_map : filter_nearest, repeat_disable;
uniform vec2 world_size=vec2(4096.0,2560.0);
uniform vec2 camera=vec2(0.0);
uniform float zoom=1.0;
uniform vec4 eddy_sources[64];
uniform bool gold_only=false;
varying float opacity;
varying vec2 water_position;
vec2 point(float column,float row) {
 return texture(curve_map,vec2((column+.5)/33.0,(row+.5)/96.0)).rg;
}
void vertex() {
 float column=round(UV.x*32.0);
 vec2 p=point(column,INSTANCE_CUSTOM.z);
 vec2 first=point(0.0,INSTANCE_CUSTOM.z);
 vec2 delta=point(min(32.0,column+1.0),INSTANCE_CUSTOM.z)-point(max(0.0,column-1.0),INSTANCE_CUSTOM.z);
 vec2 direction=delta/max(length(delta),.001);
 vec2 normal=vec2(-direction.y,direction.x);
 vec2 anchor=mod(first-camera+world_size*.5,world_size)-world_size*.5;
 vec2 relative=anchor+p-first+INSTANCE_CUSTOM.xy;
 VERTEX=relative+normal*(UV.y-.5)*(gold_only?3.0:2.0)/max(zoom,.001);
 water_position=relative+camera;
 opacity=INSTANCE_CUSTOM.w;
}
void fragment() {
 float ends=smoothstep(0.0,0.18,UV.x)*(1.0-smoothstep(0.94,1.0,UV.x))*mix(.35,1.0,UV.x);
 float ink=1.0-smoothstep(.35,.50,abs(UV.y-.5));
 float mask=1.0;
 if (gold_only) {
  mask=0.0;
  for (int i=0;i<64;i++) {
   vec2 d=mod(water_position-eddy_sources[i].xy+world_size*.5,world_size)-world_size*.5;
   mask=max(mask,(1.0-smoothstep(eddy_sources[i].z*.45,eddy_sources[i].z,length(d)))*eddy_sources[i].w);
  }
 }
 vec3 tint=gold_only?vec3(1.0,.76,.22):vec3(.78,.94,.98);
 COLOR=vec4(tint,opacity*ends*ink*mask*(gold_only?.8:.28));
}
