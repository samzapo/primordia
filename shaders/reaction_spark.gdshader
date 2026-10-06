shader_type canvas_item;
render_mode unshaded, blend_add;
varying float age;
varying float phase;
void vertex() {
	age = INSTANCE_CUSTOM.r;
	phase = INSTANCE_CUSTOM.g;
}
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float a = phase * 6.2831853;
	p = mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a))) * p;
	float radius = length(p);
	float extent = mix(0.25,0.90,sqrt(age));
	float width = max(0.014,fwidth(p.x) * 0.9);
	float star = (exp(-abs(p.x)/width) + exp(-abs(p.y)/width)) * (1.0-smoothstep(extent*0.35,extent,radius));
	float core = exp(-radius*radius/0.009);
	float glow = exp(-radius*radius/0.13)*0.13;
	float fade = (1.0-age)*(1.0-age);
	vec3 tint = mix(vec3(1.0,0.64,0.22),vec3(1.0,0.97,0.84),clamp(star+core,0.0,1.0));
	COLOR = vec4(tint,clamp((star*0.65+core+glow)*fade,0.0,1.0));
}
