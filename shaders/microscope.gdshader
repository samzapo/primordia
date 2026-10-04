shader_type canvas_item;
render_mode unshaded;
void fragment() {
    float radius = length((UV - vec2(0.5)) * 2.0);
    float darkness = smoothstep(0.66, 1.0, radius);
    COLOR = vec4(vec3(0.025, 0.055, 0.085), darkness * 0.985);
}
