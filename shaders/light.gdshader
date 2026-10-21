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
// Positive cubic B-spline weights reconstruct the 4x4 field neighborhood.
// Pairing adjacent weights lets four hardware-linear reads evaluate all 16
// contributions. Their convex weights cannot invent acid/alkaline overshoot.
vec4 cubic_weights(float v) {
	float v2 = v*v, v3 = v2*v;
	return vec4(1.0-3.0*v+3.0*v2-v3, 4.0-6.0*v2+3.0*v3,
		1.0+3.0*v+3.0*v2-3.0*v3, v3)/6.0;
}
float bicubic_acidity(vec2 uv) {
	vec2 size = vec2(textureSize(acidity_map,0));
	vec2 grid = uv*size-0.5, base = floor(grid), f = fract(grid);
	vec4 wx = cubic_weights(f.x), wy = cubic_weights(f.y);
	vec2 gx = vec2(wx.x+wx.y,wx.z+wx.w);
	vec2 gy = vec2(wy.x+wy.y,wy.z+wy.w);
	vec2 x = (base.x+vec2(-1.0+wx.y/gx.x,1.0+wx.w/gx.y)+0.5)/size.x;
	vec2 y = (base.y+vec2(-1.0+wy.y/gy.x,1.0+wy.w/gy.y)+0.5)/size.y;
	float a = mix(texture(acidity_map,vec2(x.x,y.x)).r,
		texture(acidity_map,vec2(x.y,y.x)).r,gx.y);
	float b = mix(texture(acidity_map,vec2(x.x,y.y)).r,
		texture(acidity_map,vec2(x.y,y.y)).r,gx.y);
	return mix(a,b,gy.y);
}
void fragment() {
	vec2 delta = (UV-screen_center)*view_size;
	float c = cos(camera_rotation), s = sin(camera_rotation);
	vec2 p = camera + vec2(c*delta.x+s*delta.y,-s*delta.x+c*delta.y);
	vec2 habitat_uv = fract(p/vec2(4096.0,2560.0));
	float light = texture(light_map,habitat_uv).r;
	// Reconstruct equivalents smoothly before the existing logarithmic pH palette.
	float acid = bicubic_acidity(habitat_uv);
	float excess = abs(acid)*0.001;
	float major = (excess+sqrt(excess*excess+4e-14))*0.5;
	float ph = clamp(-log(acid>=0.0 ? major : 1e-14/major)/log(10.0),0.0,14.0);
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
	vec3 tint;
	// Universal-indicator-inspired player palette; low pH deliberately pinker.
	if (ph<2.0) tint=mix(vec3(0.937,0.220,0.635),vec3(0.961,0.184,0.510),clamp(ph-1.0,0.0,1.0));
	else if (ph<3.0) tint=mix(vec3(0.961,0.184,0.510),vec3(0.980,0.333,0.486),ph-2.0);
	else if (ph<4.0) tint=mix(vec3(0.980,0.333,0.486),vec3(1.0,0.588,0.227),ph-3.0);
	else if (ph<5.0) tint=mix(vec3(1.0,0.588,0.227),vec3(1.0,0.886,0.471),ph-4.0);
	else if (ph<6.0) tint=mix(vec3(1.0,0.886,0.471),vec3(0.875,0.914,0.612),ph-5.0);
	else if (ph<7.0) tint=mix(vec3(0.875,0.914,0.612),vec3(0.910,0.929,0.737),ph-6.0);
	else if (ph<8.0) tint=mix(vec3(0.910,0.929,0.737),vec3(0.749,0.851,0.267),ph-7.0);
	else if (ph<9.0) tint=mix(vec3(0.749,0.851,0.267),vec3(0.090,0.710,0.271),ph-8.0);
	else if (ph<10.0) tint=mix(vec3(0.090,0.710,0.271),vec3(0.188,0.655,0.561),ph-9.0);
	else if (ph<11.0) tint=mix(vec3(0.188,0.655,0.561),vec3(0.459,0.847,0.922),ph-10.0);
	else if (ph<12.0) tint=mix(vec3(0.459,0.847,0.922),vec3(0.141,0.663,0.776),ph-11.0);
	else if (ph<13.0) tint=mix(vec3(0.141,0.663,0.776),vec3(0.471,0.380,0.710),ph-12.0);
	else tint=mix(vec3(0.471,0.380,0.710),vec3(0.455,0.169,0.816),clamp(ph-13.0,0.0,1.0));
	water = mix(water,tint*(0.65+0.2*light),smoothstep(0.25,2.0,abs(ph-7.0))*0.82);
	COLOR = vec4(water,1.0);
}
