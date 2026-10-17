shader_type canvas_item;
render_mode unshaded;
uniform sampler2D flow_map : filter_linear, repeat_enable;
uniform sampler2D flow_map_old : filter_linear, repeat_enable;
uniform float field_mix = 1.0;
uniform vec2 world_size = vec2(4096.0,2560.0);
uniform vec2 camera = vec2(0.0);
uniform float clock = 0.0;
uniform float zoom = 1.0;
uniform vec4 eddy_sources[6];
varying float opacity;
varying vec2 water_position;
vec2 flow(vec2 p) { return mix(texture(flow_map_old,p/world_size).rg,texture(flow_map,p/world_size).rg,field_mix); }
void vertex() {
	vec2 p = INSTANCE_CUSTOM.xy;
	float age = fract(clock/20.0+INSTANCE_CUSTOM.z)*20.0;
	float duration = max(0.0,age-(1.0-UV.x)*8.4);
	float dt = duration/16.0;
	// Bounded midpoint integration in the cached real fluid field, entirely on GPU.
	for (int i=0; i<16; i++) {
		vec2 v = flow(p);
		p += flow(p+v*dt*0.5)*dt;
	}
	water_position=p;
	vec2 v = flow(p);
	float speed = length(v);
	vec2 normal = vec2(-v.y,v.x)/max(speed,0.001);
	// One periodic image for the entire strip avoids a seam-spanning triangle.
	vec2 relative = mod(INSTANCE_CUSTOM.xy-camera+world_size*0.5,world_size)-world_size*0.5 + p-INSTANCE_CUSTOM.xy;
	VERTEX = relative+normal*(UV.y-0.5)*0.90/max(zoom,0.001);
	opacity = smoothstep(0.2,4.0,age)*(1.0-smoothstep(18.5,20.0,age));
	opacity *= smoothstep(1.0,8.0,speed)*INSTANCE_CUSTOM.w;
}
void fragment() {
	float taper = smoothstep(0.0,0.18,UV.x)*(1.0-smoothstep(0.94,1.0,UV.x));
	float core = 1.0-smoothstep(0.16,0.50,abs(UV.y-0.5));
	float head = mix(0.35,1.0,UV.x);
	float local_source=0.0;
	for (int i=0; i<6; i++) {
		vec2 d=mod(water_position-eddy_sources[i].xy+world_size*.5,world_size)-world_size*.5;
		float near_source=1.0-smoothstep(eddy_sources[i].z*.35,eddy_sources[i].z,length(d));
		local_source=max(local_source,near_source*eddy_sources[i].w);
	}
	vec3 tint=mix(vec3(0.68,0.94,0.97),vec3(1.0,0.76,0.22),local_source);
	COLOR = vec4(tint,opacity*taper*core*head*mix(.16,.34,local_source));
}
