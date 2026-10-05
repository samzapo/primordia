shader_type canvas_item;
render_mode unshaded;
void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float edge = max(fwidth(radius), 0.04);
	// A bright cap marks the reactive face, rotated by the particle transform.
	float cap = smoothstep(0.62,0.78,UV.x);
	COLOR.rgb = mix(COLOR.rgb,vec3(1.0,0.98,0.85),cap*0.85);
	COLOR.a *= 1.0 - smoothstep(1.0 - edge, 1.0, radius);
}
