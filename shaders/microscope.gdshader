shader_type canvas_item;
render_mode unshaded;
uniform vec2 center = vec2(0.5);
void fragment() {
    float radius = length((UV - center) * 2.0);
    float darkness = smoothstep(0.66, 1.0, radius);
    COLOR = vec4(vec3(0.055, 0.15, 0.31), darkness * 0.88);
}
