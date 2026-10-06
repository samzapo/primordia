shader_type canvas_item;
render_mode unshaded;
// Optical response only. Contact envelopes, packet transforms and chemistry stay authoritative.
uniform float beat_pulse = 0.0;
uniform float canvas_aspect = 0.625;
uniform vec4 pulse_sources[6];
varying vec4 packet_tint;
void vertex() {
	packet_tint = COLOR;
}
void fragment() {
	float local = 0.0;
	if (beat_pulse > 0.001) {
		for (int i=0;i<6;i++) {
			vec4 source = pulse_sources[i];
			if (source.z <= 0.0 || source.w <= 0.0) continue;
			float distance = length((SCREEN_UV-source.xy)*vec2(1.0,canvas_aspect));
			local = max(local,source.w*(1.0-smoothstep(source.z*0.15,source.z,distance)));
		}
	}
	float pulse = local*beat_pulse;
	vec2 at = (UV-vec2(0.5))/(1.0+pulse*0.075)+vec2(0.5);
	vec4 glyph = texture(TEXTURE,at)*packet_tint;
	glyph.rgb = mix(glyph.rgb,vec3(1.0),pulse*0.12);
	COLOR = glyph;
}
