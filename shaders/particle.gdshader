shader_type canvas_item;
render_mode unshaded;
// Stable oriented glyphs: colors and transforms belong to the particle batch.
varying vec4 packet_tint;
void vertex() { packet_tint = COLOR; }
void fragment() { COLOR = texture(TEXTURE,UV)*packet_tint; }
