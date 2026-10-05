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
    vec3 dark = vec3(0.07,0.22,0.42);
    vec3 bright = vec3(0.15,0.78,0.82);
    float acid = texture(acidity_map,fract(p/vec2(4096.0,2560.0))).r;
    vec3 water = mix(dark,bright,0.32+light*0.68);
    vec3 acidic_water = mix(vec3(0.76,0.35,0.66),vec3(0.96,0.25,0.46),smoothstep(0.4,0.95,acid));
    acidic_water *= 0.72+light*0.28;
    COLOR = vec4(mix(water,acidic_water,smoothstep(0.02,0.85,acid)*0.85),1.0);
}
