shader_type canvas_item;
render_mode unshaded, blend_disabled;
// A bounded nine-sample halo avoids a full-screen mipmap/blur pyramid.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D light_map : filter_linear, repeat_enable;
uniform vec2 camera;
uniform vec2 view_size;
uniform vec2 screen_center = vec2(0.5,0.52);
vec3 bright(vec2 at) {
	return max(textureLod(screen_texture,at,0.0).rgb-vec3(0.35),vec3(0.0));
}
void fragment() {
	vec2 world = camera + (UV-screen_center)*view_size;
	float light = texture(light_map,fract(world/vec2(4096.0,2560.0))).r;
	float sunlit = smoothstep(0.4,0.9,light);
	vec3 base = textureLod(screen_texture,SCREEN_UV,0.0).rgb;
	vec3 glow = vec3(0.0);
	if (sunlit > 0.001) {
		vec2 small = SCREEN_PIXEL_SIZE*2.5;
		vec2 wide = SCREEN_PIXEL_SIZE*5.0;
		glow = max(base-vec3(0.35),vec3(0.0))*0.28;
		glow += (bright(SCREEN_UV+vec2(small.x,0.0))+bright(SCREEN_UV-vec2(small.x,0.0))
			+bright(SCREEN_UV+vec2(0.0,small.y))+bright(SCREEN_UV-vec2(0.0,small.y)))*0.12;
		glow += (bright(SCREEN_UV+wide)+bright(SCREEN_UV-wide)
			+bright(SCREEN_UV+vec2(wide.x,-wide.y))+bright(SCREEN_UV+vec2(-wide.x,wide.y)))*0.06;
	}
	// Screen-style blending preserves saturated colors and crisp source edges.
	COLOR = vec4(base+(vec3(1.0)-base)*glow*sunlit*0.8,1.0);
}
