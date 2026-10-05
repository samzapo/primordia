shader_type canvas_item;
render_mode unshaded;
uniform vec2 camera;
uniform vec2 view_size;
uniform vec2 screen_center = vec2(0.5,0.52);
uniform sampler2D acidity_map : filter_linear, repeat_enable;
uniform sampler2D light_map : filter_linear, repeat_enable;
void fragment() {
    vec2 p = camera + (UV-screen_center)*view_size;
    float light = texture(light_map,fract(p/vec2(4096.0,2560.0))).r;
    vec3 dark = vec3(0.025,0.06,0.12);
    vec3 bright = vec3(0.18,0.35,0.31);
    float acid = texture(acidity_map,fract(p/vec2(4096.0,2560.0))).r;
    COLOR = vec4(mix(mix(dark,bright,light*light),vec3(0.45,0.12,0.28),acid*0.65),1.0);
}
