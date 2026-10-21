shader_type canvas_item;
render_mode unshaded, world_vertex_coords;
#include "res://shaders/cell_motion.gdshaderinc"
void vertex(){VERTEX=gel_world_point(VERTEX);}
void fragment(){if(UV.x>1.0)discard;COLOR=vec4(.025,.065,.16,1.0);}
