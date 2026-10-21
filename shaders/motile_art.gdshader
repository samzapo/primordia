shader_type canvas_item;
render_mode unshaded;
uniform float clock = 0.0;
varying vec4 canvas_tint;
varying flat float kind;
varying flat float dimmed;
void vertex(){
 canvas_tint=COLOR;
 kind=INSTANCE_CUSTOM.x;
 float phase=INSTANCE_CUSTOM.y;
 float reach=INSTANCE_CUSTOM.z;
 float width=abs(INSTANCE_CUSTOM.w);
 dimmed=INSTANCE_CUSTOM.w<0.0 ? 1.0 : 0.0;
 float t=UV.x;
 float wave=t*(kind<.5 ? 7.0 : 4.0)-clock*(kind<.5 ? 9.0 : 10.0)+phase;
 float amplitude=kind<.5 ? 9.0 : 6.0;
 vec2 at=vec2(t*reach,sin(wave)*t*amplitude);
 vec2 tangent=vec2(reach,amplitude*(sin(wave)+t*(kind<.5 ? 7.0 : 4.0)*cos(wave)));
 if(kind>1.5){
  at=vec2(t*reach*(1.0+.15*sin(clock*7.0+phase)),0.0);
  tangent=vec2(1.0,0.0);
 }
 vec2 normal=normalize(vec2(-tangent.y,tangent.x));
 VERTEX=at+normal*(UV.y*2.0-1.0)*width*.5;
}
void fragment(){
 float edge=abs(UV.y*2.0-1.0);
 vec3 ink=kind<.5 ? mix(vec3(.208,.855,.694),vec3(.075,.471,.537),smoothstep(.55,.85,edge)) : (kind<1.5 ? vec3(.169,.886,.902) : vec3(.792,.969,.745));
 if(dimmed>.5){
  float gray=dot(ink,vec3(.2126,.7152,.0722));
  ink=mix(ink,vec3(gray),.85)*.82;
 }
 COLOR=canvas_tint*vec4(ink,1.0-smoothstep(.80,1.0,edge));
}
