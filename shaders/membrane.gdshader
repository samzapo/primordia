shader_type canvas_item;
render_mode unshaded;
uniform vec4 gel : source_color;
uniform vec4 body : source_color;
uniform vec4 rim : source_color;
uniform vec4 shine : source_color;
uniform vec4 edge : source_color;
uniform float heading = 0.0;
uniform float hurt = 0.0;
uniform float clock = 0.0;
uniform vec2 slip = vec2(0.0);
uniform bool wakes = true;
varying vec2 direction;
void vertex() { direction = COLOR.rg*2.0-1.0; }
void fragment() {
	float r = UV.x;
	vec2 local = direction / max(length(direction),0.0001);
	vec2 normal_xy = mat2(vec2(cos(heading),sin(heading)),vec2(-sin(heading),cos(heading)))*local;
	float facing = dot(normal_xy,normalize(vec2(-1.0,-1.0)));
	float aa = max(fwidth(r),0.001);
	// A broad gel dome and rounded colored lip; light stays fixed as cells rotate.
	float dome = sqrt(max(0.0,1.0-r*r));
	vec3 color = mix(gel.rgb,body.rgb,0.34+0.22*dome+0.10*facing*r);
	color *= 0.87+0.16*dome+0.07*facing*r;
	float lip = smoothstep(0.78,0.90,r)*(1.0-smoothstep(0.98,1.0,r));
	color = mix(color,rim.rgb*(0.68+0.30*max(facing,0.0)),lip*0.88);
	float glint = smoothstep(0.25,0.95,facing)*exp(-pow((r-0.91)/0.044,2.0));
	color = mix(color,shine.rgb,glint*0.82);
	float contour = smoothstep(0.974,1.0,r);
	color = mix(color,edge.rgb,contour*0.62);
	color = mix(color,vec3(1.0),hurt*0.50);
	float inside = 1.0-smoothstep(1.0-aa,1.0+aa,r);
	// Submerged disturbance glints, not literal surface waves or extra armor.
	float speed = length(slip);
	float downstream = max(0.0,dot(normal_xy,-slip/max(speed,0.001)));
	float distance = r-1.0;
	float phase = distance*7.0-clock*0.8;
	float bands = pow(0.5+0.5*cos(phase*6.283185),7.0);
	float halo = smoothstep(0.015,0.045,distance)*(1.0-smoothstep(0.10,0.38,distance));
	float wake = (wakes ? 1.0 : 0.0)*clamp(speed/45.0,0.0,1.0)*downstream*halo*bands*0.17;
	COLOR = vec4(mix(vec3(0.64,0.94,1.0),color,inside),inside+(1.0-inside)*wake);
}
