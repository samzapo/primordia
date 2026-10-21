shader_type canvas_item;
render_mode unshaded, world_vertex_coords;
#include "res://shaders/cell_motion.gdshaderinc"
void vertex(){VERTEX=gel_world_point(VERTEX);}
