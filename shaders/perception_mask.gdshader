shader_type canvas_item;
render_mode unshaded, blend_disabled;
// MembraneArt includes an outer wake/halo ring out to 1.95. Only the body is
// a mask; filling that halo produced the old square crop at the texture edge.
void fragment(){if(UV.x>1.0)discard;COLOR=vec4(1.0);}
