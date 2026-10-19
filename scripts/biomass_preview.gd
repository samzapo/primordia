extends Control
## Editing-only tissue comparison. Both silhouettes have equal area per unit.
var game
var blob := ArrayMesh.new()
var outline := PackedVector2Array()
var quote: Dictionary = {}
var rate_quote: Dictionary = {}

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
	visible = not game.touch_zoom.enabled and game.build_open and not game.settings_panel.visible and not game.world.player.dead
	if not visible: return
	var amount: float = maxf(0,game.world.player.biomass)
	var price: Dictionary = game.cell_ui.hovered_price
	var showing_cost: bool = not price.is_empty() or game.selected >= 0
	var cost: float = float(price.tissue) if not price.is_empty() else 0.0
	var ap_needed: int = int(price.ap) if not price.is_empty() else game.world.player.construction_price(game.Simulation.KINDS[game.selected]) if game.selected >= 0 else 0
	var s: float = game.preferences.hud_scale
	var view := get_viewport_rect().size
	var maximum := minf(68*s,minf(view.x*0.095,view.y*0.14))
	var factor := minf(sqrt(game.Simulation.Cell.TISSUE_AREA/PI)*game.zoom,maximum/sqrt(maxf(1,maxf(amount,cost))))
	quote = {"available":amount,"cost":cost,"stock_radius":sqrt(amount)*factor,
		"cost_radius":sqrt(cost)*factor,"maximum":maximum,
		"ap_count":maxi(0,game.world.player.ap),"ap_needed":ap_needed,"show_cost":showing_cost,
		"enough":amount+0.000001 >= cost,"ap_ready":not game.world.evolution.enabled or game.world.player.ap >= ap_needed}
	var cell = game.world.player
	var rates: Dictionary = cell.energy_budget.rates(cell.age)
	var model: Dictionary = price.get("rate_model",{})
	if model.is_empty() and game.cell_ui.hovered.get("kind","") == "organ":
		model = cell.organ_by_id(game.cell_ui.hovered.id)
	if model.is_empty() and game.cell_ui.keyboard_target.get("kind","") == "organ":
		model = cell.organ_by_id(game.cell_ui.keyboard_target.id)
	var upkeep: float = game.Simulation.Cell.organ_upkeep(model) if not model.is_empty() else 0.0
	var actual: float = rates.organs.get(model.get("id",-2),0.0)
	var preview: bool = not price.is_empty() or game.selected >= 0
	if model.is_empty() and game.selected >= 0:
		model = {"kind":game.Simulation.KINDS[game.selected],"scale":1.0,"mutation":""}
		upkeep = game.Simulation.Cell.organ_upkeep(model)
	var shown_rate: float = upkeep if preview else actual
	var rate_factor: float = minf(18*s,28*s/sqrt(maxf(1,maxf(shown_rate,maxf(rates.production,rates.spent)))))
	rate_quote = {"rates":rates,"upkeep":upkeep,"actual":actual,"shown":shown_rate,"preview":preview,"has_organ":not model.is_empty(),"factor":rate_factor}
	queue_redraw()

func comparison_bounds() -> Rect2:
	if quote.is_empty() or game == null or not game.build_open: return Rect2()
	var scale: float = game.preferences.hud_scale
	var maximum: float = quote.maximum
	var rows := maxi(1,ceili(float(mini(24,quote.ap_count))/8))
	var left: float = get_viewport_rect().size.x-68*scale-4*maximum
	var bottom: float = 76*scale+2*maximum+(214+18*(rows-1))*scale
	return Rect2(Vector2(left,60*scale),Vector2(get_viewport_rect().size.x-left,bottom-60*scale))

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
	if not quote.show_cost and game.cell_ui.hovered.get("kind","") not in ["organ","atp"]: return
	var s: float = game.preferences.hud_scale
	var maximum: float = quote.maximum
	var stock := Vector2(get_viewport_rect().size.x-24*s-maximum,76*s+maximum)
	var needed := stock-Vector2(maximum*2+32*s,0)
	_blob(stock,quote.stock_radius,Color("a3f5dc"))
	if quote.available == 0:
		draw_arc(stock,12*s,0,TAU,32,Color("a3f5dc"),1.5*s,true)
		_caption("Empty",stock+Vector2(0,5*s),Color("d3fff1"))
	_caption("Available tissue",stock+Vector2(0,maximum+24*s),Color("d3fff1"))
	# Available AP lives inside the cell, one gold vacuole per point.
	if quote.show_cost:
		var tint := Color("ffd68a") if quote.enough else Color("ff829e")
		_blob(needed,quote.cost_radius,tint)
		_caption("AP only" if quote.cost == 0 and quote.ap_needed > 0 else "Free" if quote.cost == 0 else "Needed tissue",needed+Vector2(0,maximum+24*s),tint)
		if not quote.enough: _caption("Need more tissue",needed+Vector2(0,maximum+44*s),tint)
		elif not quote.ap_ready: _caption("Needs AP",needed+Vector2(0,maximum+44*s),Color("ff829e"))
		_draw_ap(needed+Vector2(0,maximum+60*s),s,quote.ap_needed,"Needed AP",quote.ap_ready)
	_draw_rates(stock,needed,s)


func _draw_ap(at: Vector2, scale: float, count: int, label: String, enough: bool = true) -> void:
	var tint := Color("ffe6a1") if enough else Color("ff829e")
	_caption(label,at-Vector2(0,8*scale),tint)
	if count == 0:
		if label == "Needed AP":
			_caption("Free",at+Vector2(0,16*scale),tint)
			return
		draw_arc(at+Vector2(0,10*scale),6*scale,0,TAU,24,Color("aa8b52"),1.3*scale,true)
		return
	# The expedition's finite grants bound this cluster; each blob is exactly 1 AP.
	var columns := mini(8,count)
	for i in count:
		var p := at+Vector2((i%columns-(columns-1)*0.5)*18,(floori(float(i)/columns))*18+10)*scale
		var radius := (6.5+0.3*sin(i*2.4))*scale
		draw_mesh(blob,null,Transform2D(0,Vector2.ONE*radius,0,p),(Color("f4bb46") if enough else Color("ff829e")))
		draw_polyline(Transform2D(0,Vector2.ONE*radius,0,p)*outline,tint,1.2*scale,true)
		draw_circle(p+Vector2(-2,-2.5)*scale,1.8*scale,Color("fff4c3"))

func _draw_rates(stock: Vector2, needed: Vector2, scale: float) -> void:
	var rows := maxi(1,ceili(float(mini(24,quote.ap_count))/8))
	var top: float = stock.y+quote.maximum+(126+18*(rows-1))*scale
	var factor: float = rate_quote.factor
	var rates: Dictionary = rate_quote.rates
	var income := Vector2(stock.x,top)
	var expense := Vector2(needed.x,top)
	var share := income.lerp(expense,0.5)
	for item in [{"p":income,"rate":rates.production,"label":"ATP in/s","color":Color("a3f5dc")},
		{"p":expense,"rate":rates.spent,"label":"ATP out/s","color":Color("ffb583")}]:
		if item.rate > 0: _blob(item.p,sqrt(item.rate)*factor,item.color)
		else: draw_arc(item.p,5*scale,0,TAU,24,Color(item.color,0.6),1.2*scale,true)
		_caption(item.label,item.p+Vector2(0,45*scale),item.color)
	if rate_quote.has_organ:
		if rate_quote.shown > 0: _blob(share,sqrt(rate_quote.shown)*factor,Color("ffd68a"))
		else: draw_arc(share,5*scale,0,TAU,24,Color("ffd68a"),1.2*scale,true)
		_caption("Steady/s" if rate_quote.preview else "Organ/s",share+Vector2(0,45*scale),Color("ffd68a"))
	_caption("Surplus" if rates.net >= 0 else "Deficit",income+Vector2(0,66*scale),Color("a3f5dc") if rates.net >= 0 else Color("ff829e"))
