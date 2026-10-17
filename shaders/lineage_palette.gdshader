shader_type canvas_item;
render_mode unshaded;
uniform float hue=0.0;
vec3 hsv(vec3 c){
 vec3 p=abs(fract(c.xxx+vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0);
 return c.z*mix(vec3(1.0),clamp(p-1.0,0.0,1.0),c.y);
}
void fragment(){
 vec2 p=(UV-.5)*2.0;float r=length(p);
 vec3 col=vec3(0.0);float alpha=0.0;
 if(r>=.82 && r<=1.0){col=hsv(vec3(fract(atan(p.y,p.x)/6.2831853+1.0),1.0,1.0));alpha=1.0;}
 else if(r<=.72){
  vec2 u=p/.72;
  vec2 square=u*length(u)/max(.00001,max(abs(u.x),abs(u.y)));
  col=hsv(vec3(hue,(square.x+1.0)*.5,(1.0-square.y)*.5));alpha=1.0;
 }
 COLOR=vec4(col,alpha);
}
