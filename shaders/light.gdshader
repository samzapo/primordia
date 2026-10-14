shader_type canvas_item;
render_mode unshaded;
uniform vec2 camera;
uniform float camera_rotation = 0.0;
uniform vec2 view_size;
uniform vec2 screen_center = vec2(0.5,0.52);
uniform sampler2D acidity_map : filter_linear, repeat_enable;
uniform sampler2D light_map : filter_linear, repeat_enable;
uniform float habitat_seed = 0.0;
uniform bool fractal_color = true;
uniform bool water_ripples = true;
uniform float clock = 0.0;
float lattice(vec2 p, vec2 period) {
	p = mod(p,period);
	return fract(sin(dot(p,vec2(127.1,311.7))+habitat_seed*0.13)*43758.5453);
}
float tile_noise(vec2 uv, vec2 period) {
	vec2 p = uv*period;
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(lattice(i,period),lattice(i+vec2(1,0),period),f.x),
		mix(lattice(i+vec2(0,1),period),lattice(i+vec2(1,1),period),f.x),f.y);
}
float fractal(vec2 uv) {
	return tile_noise(uv,vec2(4,3))*0.54+tile_noise(uv,vec2(8,6))*0.27+
		tile_noise(uv,vec2(16,12))*0.13+tile_noise(uv,vec2(32,24))*0.06;
}
void fragment() {
	vec2 delta = (UV-screen_center)*view_size;
	float c = cos(camera_rotation), s = sin(camera_rotation);
	vec2 p = camera + vec2(c*delta.x+s*delta.y,-s*delta.x+c*delta.y);
	vec2 habitat_uv = fract(p/vec2(4096.0,2560.0));
	float light = texture(light_map,habitat_uv).r;
	float acid = texture(acidity_map,habitat_uv).r;
	// Quiet blue water leaves luminance headroom for anatomy and lit tips.
	vec3 water = mix(vec3(0.018,0.032,0.105),vec3(0.025,0.25,0.32),smoothstep(0.12,0.96,light));
	if (fractal_color) {
		float terrain = fractal(p/vec2(4096.0,2560.0));
		vec3 reef = mix(vec3(0.025,0.105,0.17),vec3(0.115,0.065,0.25),smoothstep(0.3,0.7,terrain));
		water = mix(water,reef,0.44);
		water = mix(water,vec3(0.065,0.42,0.45),smoothstep(0.60,0.81,terrain)*smoothstep(0.38,0.9,light)*0.75);
	}
	vec3 acidic_water = mix(vec3(0.20,0.035,0.22),vec3(0.48,0.045,0.23),smoothstep(0.35,0.95,acid));
	acidic_water *= 0.65+light*0.35;
	water = mix(water,acidic_water,smoothstep(0.02,0.85,acid)*0.85);
	if (water_ripples) {
		// Slow world-anchored light caustics: no screen sampling or geometry warp.
		vec2 phase = habitat_uv*6.283185;
		float a = sin(phase.x*8.0+phase.y*6.0-clock*0.34);
		float b = sin(phase.x*5.0-phase.y*7.0+clock*0.23);
		float caustic = pow(max(0.0,a*b),3.0);
		water = water*(1.0+0.035*a*b)+vec3(0.012,0.035,0.045)*caustic;
	}
	COLOR = vec4(water,1.0);
}
