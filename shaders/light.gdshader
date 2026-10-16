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
// Separate spatial contrast from the hourly brightness multiplier. The texture
// remains the actual gameplay light; this exposure only makes its pattern readable.
uniform float illumination_scale = 1.0;
float caustics(vec2 phase, float time) {
	// Animated, warped cellular focusing curves, rather than intersecting sine
	// stripes or regularly placed point glows. Periodic seeds wrap with the pond.
	vec2 period = vec2(26.0,16.0);
	vec2 warp = vec2(
		sin(phase.y*3.0+sin(phase.x*2.0)+time*0.17),
		cos(phase.x*3.0-phase.y+time*0.13));
	vec2 p = phase/6.283185*period+warp*1.15;
	vec2 cell = floor(p), local = fract(p);
	float nearest = 100.0, second = 100.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 step = vec2(float(x),float(y));
			vec2 id = mod(cell+step,period);
			vec2 seed = vec2(dot(id,vec2(127.1,311.7)),dot(id,vec2(269.5,183.3)));
			vec2 point = 0.5+0.43*sin(seed+habitat_seed*0.13+vec2(time*0.31,-time*0.27));
			vec2 offset = step+point-local;
			float distance = dot(offset,offset);
			if (distance < nearest) {second=nearest;nearest=distance;}
			else {second=min(second,distance);}
		}
	}
	float edge = sqrt(second)-sqrt(nearest);
	float ridge = 1.0-smoothstep(0.018,0.09,edge);
	float halo = 1.0-smoothstep(0.06,0.24,edge);
	return ridge*0.60+halo*0.16;
}
void fragment() {
	vec2 delta = (UV-screen_center)*view_size;
	float c = cos(camera_rotation), s = sin(camera_rotation);
	vec2 p = camera + vec2(c*delta.x+s*delta.y,-s*delta.x+c*delta.y);
	vec2 habitat_uv = fract(p/vec2(4096.0,2560.0));
	float light = texture(light_map,habitat_uv).r;
	// A bounded nine-tap display footprint makes real acid patches readable
	// beyond one grid square. This does not change chemistry or transport.
	vec2 texel = vec2(1.5/64.0,1.5/40.0);
	float acid = texture(acidity_map,habitat_uv).r*0.28;
	acid += (texture(acidity_map,habitat_uv+vec2(texel.x,0.0)).r+
		texture(acidity_map,habitat_uv-vec2(texel.x,0.0)).r+
		texture(acidity_map,habitat_uv+vec2(0.0,texel.y)).r+
		texture(acidity_map,habitat_uv-vec2(0.0,texel.y)).r)*0.12;
	acid += (texture(acidity_map,habitat_uv+texel).r+
		texture(acidity_map,habitat_uv-texel).r+
		texture(acidity_map,habitat_uv+vec2(texel.x,-texel.y)).r+
		texture(acidity_map,habitat_uv+vec2(-texel.x,texel.y)).r)*0.06;
	vec2 phase = habitat_uv*6.283185;
	float local_light = clamp(light/max(illumination_scale,0.06),0.0,1.0);
	float sunlit = smoothstep(0.18,0.78,local_light);
	float daylight = 0.55+0.45*sqrt(clamp(illumination_scale,0.0,1.0));
	// Broad deep indigo shade and luminous turquoise sunlight. Every bright
	// region follows the shared light field, never an independent grid of glows.
	vec3 water = mix(vec3(0.008,0.013,0.048),vec3(0.055,0.38,0.44),sunlit)*daylight;
	if (fractal_color) {
		float hue = 0.5+0.5*sin(phase.y+0.9*sin(phase.x+habitat_seed*0.13));
		water *= mix(vec3(0.83,0.92,1.08),vec3(1.10,1.04,0.93),hue);
	}
	if (water_ripples) {
		water += vec3(0.22,0.33,0.27)*caustics(phase,clock)*sunlit*sunlit*daylight;
	}
	vec3 acidic_water = mix(vec3(0.32,0.045,0.32),vec3(0.62,0.07,0.36),smoothstep(0.05,0.45,acid));
	acidic_water *= 0.85+light*0.15;
	// Buffers remove actual acid, visibly restoring the original blue water.
	water = mix(water,acidic_water,(1.0-exp(-acid*24.0))*0.94);
	COLOR = vec4(water,1.0);
}
