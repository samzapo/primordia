shader_type canvas_item;
render_mode unshaded;
void fragment(){if(UV.x>1.0)discard;COLOR=vec4(.025,.065,.16,1.0);}
