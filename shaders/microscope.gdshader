shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Share one screen copy for bloom and peripheral defocus; the UI draws afterward.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform bool bloom_enabled = true;
uniform vec2 lens_center = vec2(-1.0);
uniform float lens_amount = 0.0;
uniform float lens_radius = 0.047222; // Fraction of canvas width; stable through window stretching.
uniform float lens_magnification = 3.5;
uniform float edge_blur_pixels : hint_range(0.0,12.0) = 6.0;
uniform sampler2D light_map : filter_linear, repeat_enable;
uniform vec2 camera;
uniform float camera_rotation = 0.0;
uniform vec2 view_size;
uniform vec2 screen_center = vec2(0.5,0.52);
vec3 radiance(vec3 color) {
	float peak = max(color.r,max(color.g,color.b));
	float luminance = dot(color,vec3(0.2126,0.7152,0.0722));
	return color*smoothstep(0.72,0.96,peak)*smoothstep(0.34,0.72,luminance);
}
vec3 bright(vec2 at) {
	return radiance(textureLod(screen_texture,at,0.0).rgb);
}
void fragment() {
	vec2 sample_uv = SCREEN_UV;
	float lens_distance = length((SCREEN_UV-lens_center)*vec2(1.0,view_size.y/view_size.x));
	float lens_weight = (1.0-smoothstep(lens_radius*0.62,lens_radius,lens_distance))*lens_amount;
	sample_uv = lens_center+(SCREEN_UV-lens_center)/mix(1.0,lens_magnification,lens_weight);
	vec2 delta = (sample_uv-screen_center)*view_size;
	float c = cos(camera_rotation), s = sin(camera_rotation);
	vec2 world = camera + vec2(c*delta.x+s*delta.y,-s*delta.x+c*delta.y);
	float light = texture(light_map,fract(world/vec2(4096.0,2560.0))).r;
	float sunlit = smoothstep(0.4,0.9,light);
	vec3 base = textureLod(screen_texture,sample_uv,0.0).rgb;
	vec3 glow = vec3(0.0);
	if (bloom_enabled && sunlit > 0.001) {
		vec2 small = SCREEN_PIXEL_SIZE*2.5;
		vec2 wide = SCREEN_PIXEL_SIZE*5.0;
		glow = radiance(base)*0.28;
		glow += (bright(sample_uv+vec2(small.x,0.0))+bright(sample_uv-vec2(small.x,0.0))
			+bright(sample_uv+vec2(0.0,small.y))+bright(sample_uv-vec2(0.0,small.y)))*0.12;
		glow += (bright(sample_uv+wide)+bright(sample_uv-wide)
			+bright(sample_uv+vec2(wide.x,-wide.y))+bright(sample_uv+vec2(-wide.x,wide.y)))*0.06;
	}
	float fringe = smoothstep(0.66,1.0,length((UV-screen_center)*2.0))*(1.0-lens_weight);
	if (fringe > 0.001 && edge_blur_pixels > 0.0) {
		// Filtered mip levels give smooth defocus without repeated silhouettes.
		float level = log2(1.0+edge_blur_pixels*fringe);
		base = mix(base,textureLod(screen_texture,sample_uv,level).rgb,fringe);
	}
	// Preserve the light halo without tinting or darkening the edges.
	COLOR = vec4(base+(vec3(1.0)-base)*glow*sunlit*0.8,1.0);
}
