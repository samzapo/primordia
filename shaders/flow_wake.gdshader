shader_type canvas_item;
render_mode unshaded;
uniform sampler2D flow_map : filter_linear, repeat_enable;
uniform sampler2D flow_map_old : filter_linear, repeat_enable;
uniform float field_mix = 1.0;
uniform vec2 world_size = vec2(4096.0,2560.0);
uniform vec2 camera = vec2(0.0);
uniform float clock = 0.0;
varying float strength;
varying float seed;
void vertex() {
	vec2 p = INSTANCE_CUSTOM.xy;
	vec2 v = mix(texture(flow_map_old,p/world_size).rg,texture(flow_map,p/world_size).rg,field_mix);
	float speed = length(v);
	vec2 axis = v/max(speed,0.001);
	vec2 side = vec2(-axis.y,axis.x);
	float radius = INSTANCE_CUSTOM.z;
	// Only a few stout-stem samples; never imply impermeable fine foliage.
	vec2 local = vec2((UV.x-0.24)*(radius*7.0+min(speed,70.0)*1.5),(UV.y-0.5)*radius*6.0);
	VERTEX = mod(p-camera+world_size*0.5,world_size)-world_size*0.5+axis*local.x+side*local.y;
	strength = smoothstep(2.0,20.0,speed);
	seed = INSTANCE_CUSTOM.w;
}
void fragment() {
	vec2 q = vec2(UV.x,abs(UV.y-0.5));
	float edge = 0.28*exp(-UV.x*1.6);
	float aa = max(fwidth(q.y),0.009);
	float contour = 1.0-smoothstep(aa,aa*3.0,abs(q.y-edge));
	float drift = 0.5+0.5*sin(UV.x*24.0-clock*1.2+seed);
	float fade = smoothstep(0.02,0.20,UV.x)*(1.0-smoothstep(0.64,1.0,UV.x));
	COLOR = vec4(0.62,0.94,0.96,contour*fade*strength*(0.16+drift*0.12));
}
