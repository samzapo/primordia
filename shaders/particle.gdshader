shader_type canvas_item;
render_mode unshaded;
void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float edge = max(fwidth(radius), 0.04);
	COLOR.a *= 1.0 - smoothstep(1.0 - edge, 1.0, radius);
}
