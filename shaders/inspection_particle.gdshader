shader_type canvas_item;
render_mode unshaded;
uniform vec2 lens_center;
uniform float lens_radius;
uniform float canvas_aspect;
void fragment() {
	float distance_from_center = length((SCREEN_UV-lens_center)*vec2(1.0,canvas_aspect));
	COLOR.a *= 1.0-smoothstep(lens_radius*0.96,lens_radius,distance_from_center);
}
