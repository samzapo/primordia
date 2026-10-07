shader_type canvas_item;
render_mode unshaded;
uniform float heading = 0.0;
uniform float clock = 0.0;
uniform vec2 slip = vec2(0.0);
varying vec2 direction;
void vertex() { direction = COLOR.rg*2.0-1.0; }
void fragment() {
	vec2 local = direction/max(length(direction),0.0001);
	vec2 normal_xy = mat2(vec2(cos(heading),sin(heading)),vec2(-sin(heading),cos(heading)))*local;
	float speed = length(slip);
	float downstream = max(0.0,dot(normal_xy,-slip/max(speed,0.001)));
	float distance = UV.x-1.0;
	float phase = distance*4.5-clock*0.55;
	float bands = pow(0.5+0.5*cos(phase*6.283185),8.0);
	float halo = smoothstep(0.03,0.09,distance)*(1.0-smoothstep(0.25,0.92,distance));
	float wake = clamp(speed/32.0,0.0,1.0)*(0.25+0.75*downstream)*halo*bands*0.28;
	COLOR = vec4(0.64,0.94,1.0,wake);
}
