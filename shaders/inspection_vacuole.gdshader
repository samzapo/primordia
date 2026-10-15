shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/vacuole_art.gdshaderinc"
uniform vec3 contents=vec3(1,7,1);
uniform vec2 lens_center;
uniform float lens_radius;
uniform float canvas_aspect;
uniform float opacity=1.0;
void fragment(){
 COLOR=vacuole_art(UV,contents);
 float d=length((SCREEN_UV-lens_center)*vec2(1,canvas_aspect));
 COLOR.a*=opacity*(1.0-smoothstep(lens_radius*.96,lens_radius,d));
}
