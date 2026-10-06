extends Control
## Editing-only tissue comparison. Both silhouettes have equal area per unit.
var game
var blob := ArrayMesh.new()
var outline := PackedVector2Array()
var quote: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var points := PackedVector2Array()
	for i in 48:
		var angle := TAU*i/48.0
		points.append(Vector2.from_angle(angle)*(1+0.035*sin(3*angle)+0.015*cos(5*angle)))
	var area := 0.0
	for i in points.size(): area += points[i].cross(points[(i+1)%points.size()])*0.5
	for i in points.size(): points[i] *= sqrt(PI/area)
	outline = points.duplicate()
	outline.append(points[0])
	var vertices := PackedVector3Array([Vector3.ZERO])
	for point in points: vertices.append(Vector3(point.x,point.y,0))
	var indices := PackedInt32Array()
	for i in points.size(): indices.append_array(PackedInt32Array([0,i+1,(i+1)%points.size()+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	blob.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

func sync() -> void:
	if game == null: return
	visible = game.build_open and not game.settings_panel.visible and not game.world.player.dead
	if not visible: return
	var amount: float = maxf(0,game.world.player.biomass)
	var cost: float = game.Simulation.Cell.organ_cost(game.Simulation.KINDS[game.selected]) if game.selected >= 0 else 0.0
	var s: float = game.preferences.hud_scale
	var view := get_viewport_rect().size
	var maximum := minf(68*s,minf(view.x*0.095,view.y*0.14))
	var factor := minf(10*s,maximum/sqrt(maxf(1,maxf(amount,cost))))
	quote = {"available":amount,"cost":cost,"stock_radius":sqrt(amount)*factor,
		"cost_radius":sqrt(cost)*factor,"maximum":maximum,
		"enough":amount+0.000001 >= cost,"ap_ready":not game.world.evolution.enabled or game.world.evolution.points >= 1}
	queue_redraw()

func _blob(at: Vector2, radius: float, tint: Color) -> void:
	if radius <= 0: return
	draw_mesh(blob,null,Transform2D(0,Vector2.ONE*radius,0,at),Color(tint,0.30))
	draw_polyline(Transform2D(0,Vector2.ONE*radius,0,at)*outline,Color(tint,0.80),1.6*game.preferences.hud_scale,true)
	draw_arc(at,radius*0.82,3.65,4.9,14,Color(1,1,1,0.55),2.4*game.preferences.hud_scale,true)

func _caption(value: String, at: Vector2, tint: Color) -> void:
	var font := ThemeDB.fallback_font
	var pixels := roundi(15*game.preferences.hud_scale)
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
	var origin := at-Vector2(width*0.5,0)
	draw_string_outline(font,origin,value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,5,Color("102340"))
	draw_string(font,origin,value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,tint)

func _draw() -> void:
	if quote.is_empty() or game == null: return
	var s: float = game.preferences.hud_scale
	var maximum: float = quote.maximum
	var stock := Vector2(get_viewport_rect().size.x-24*s-maximum,76*s+maximum)
	var needed := stock-Vector2(maximum*2+32*s,0)
	_blob(stock,quote.stock_radius,Color("a3f5dc"))
	if quote.available == 0:
		draw_arc(stock,12*s,0,TAU,32,Color("a3f5dc"),1.5*s,true)
		_caption("Empty",stock+Vector2(0,5*s),Color("d3fff1"))
	_caption("Available tissue",stock+Vector2(0,maximum+24*s),Color("d3fff1"))
	if game.selected >= 0:
		var tint := Color("ffd68a") if quote.enough else Color("ff829e")
		_blob(needed,quote.cost_radius,tint)
		_caption("Needed tissue",needed+Vector2(0,maximum+24*s),tint)
		if not quote.enough: _caption("Need more tissue",needed+Vector2(0,maximum+44*s),tint)
		elif not quote.ap_ready: _caption("Needs AP",needed+Vector2(0,maximum+44*s),Color("ffd68a"))
