uniform sampler2D glyph_atlas : filter_linear_mipmap, repeat_disable;
vec4 vacuole_art(vec2 uv,vec3 contents){
 vec2 at=(uv-.5)*14.0;
 float edge=length(at);
 if(edge>7.0)return vec4(0);
 vec3 membrane=mix(vec3(.56,.89,.75),vec3(.96,.59,.77),1.0-contents.x);
 vec4 out_color=vec4(membrane,.065);
 float rim=smoothstep(6.1,6.6,edge)*(1.0-smoothstep(6.6,7.0,edge));
 out_color=vec4(membrane,max(out_color.a,rim*.9));
 // Fixed illustrations inside a single carrier. No content poses or contacts.
 for(int i=0;i<7;i++){
  if(float(i)>=contents.y)break;
  float angle=float(i-1)*1.04719755;
  vec2 center=i==0?vec2(0):vec2(cos(angle),sin(angle))*3.5;
  bool food=float(i)<floor(contents.y*contents.x+.5);
  float r=(food?2.0:1.5)*contents.z; // half the external radius at the illustrated dose
  vec2 glyph_uv=(at-center)/(2.0*r)+.5;
  if(all(greaterThanEqual(glyph_uv,vec2(0)))&&all(lessThanEqual(glyph_uv,vec2(1)))){
   vec4 glyph=texture(glyph_atlas,vec2((glyph_uv.x+(food?0.0:1.0))*.5,glyph_uv.y));
   out_color.rgb=mix(out_color.rgb,glyph.rgb,glyph.a);out_color.a=max(out_color.a,glyph.a);
  }
 }
 return out_color;
}
