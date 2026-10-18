shader_type canvas_item;
render_mode unshaded;
uniform sampler2D curve_map : filter_nearest, repeat_disable;
uniform vec2 world_size=vec2(4096.0,2560.0);
uniform vec2 camera=vec2(0.0);
uniform float zoom=1.0;
uniform vec4 eddy_sources[32];
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
 VERTEX=relative+normal*(UV.y-.5)*4.0/max(zoom,.001);
 water_position=relative+camera;
 opacity=INSTANCE_CUSTOM.w;
}
void fragment() {
 float ends=smoothstep(0.0,0.08,UV.x)*(1.0-smoothstep(0.92,1.0,UV.x));
 float ink=1.0-smoothstep(.35,.50,abs(UV.y-.5));
 float local_source=0.0;
 for (int i=0;i<32;i++) {
  vec2 d=mod(water_position-eddy_sources[i].xy+world_size*.5,world_size)-world_size*.5;
  local_source=max(local_source,(1.0-smoothstep(eddy_sources[i].z*.35,eddy_sources[i].z,length(d)))*eddy_sources[i].w);
 }
 vec3 tint=mix(vec3(.78,.94,.98),vec3(1.0,.76,.22),local_source);
 COLOR=vec4(tint,opacity*ends*ink*mix(.40,.64,local_source));
}
