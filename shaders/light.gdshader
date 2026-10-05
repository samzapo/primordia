shader_type canvas_item;
render_mode unshaded;
uniform vec2 camera;
uniform vec2 view_size;
uniform vec2 screen_center = vec2(0.5,0.52);
uniform sampler2D acidity_map : filter_linear, repeat_enable;
uniform sampler2D light_map : filter_linear, repeat_enable;
uniform float habitat_seed = 0.0;
uniform bool fractal_color = true;
float lattice(vec2 p, vec2 period) {
    p = mod(p,period);
    return fract(sin(dot(p,vec2(127.1,311.7))+habitat_seed*0.13)*43758.5453);
}
float tile_noise(vec2 uv, vec2 period) {
    vec2 p = uv*period;
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(lattice(i,period),lattice(i+vec2(1,0),period),f.x),
               mix(lattice(i+vec2(0,1),period),lattice(i+vec2(1,1),period),f.x),f.y);
}
float fractal(vec2 uv) {
    return tile_noise(uv,vec2(4,3))*0.54+tile_noise(uv,vec2(8,6))*0.27+
           tile_noise(uv,vec2(16,12))*0.13+tile_noise(uv,vec2(32,24))*0.06;
}
void fragment() {
    vec2 p = camera + (UV-screen_center)*view_size;
    float light = texture(light_map,fract(p/vec2(4096.0,2560.0))).r;
    vec3 dark = vec3(0.07,0.22,0.42);
    vec3 bright = vec3(0.15,0.78,0.82);
    float acid = texture(acidity_map,fract(p/vec2(4096.0,2560.0))).r;
    vec3 water = mix(dark,bright,0.32+light*0.68);
    if (fractal_color) {
        float terrain = fractal(p/vec2(4096.0,2560.0));
        vec3 reef = mix(vec3(0.10,0.55,0.53),vec3(0.34,0.34,0.68),smoothstep(0.3,0.68,terrain));
        reef = mix(reef,vec3(0.30,0.82,0.77),smoothstep(0.6,0.79,terrain));
        water = mix(water,reef*(0.64+light*0.36),0.58);
        water *= 0.88+0.24*smoothstep(0.25,0.75,terrain);
    }
    vec3 acidic_water = mix(vec3(0.76,0.35,0.66),vec3(0.96,0.25,0.46),smoothstep(0.4,0.95,acid));
    acidic_water *= 0.72+light*0.28;
    COLOR = vec4(mix(water,acidic_water,smoothstep(0.02,0.85,acid)*0.85),1.0);
}
