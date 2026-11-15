extends Control
var game
var items: Array=[]
var styles: Dictionary={}
func initialize(owner_game) -> void:
	game=owner_game;game.ui.add_child(self);mouse_filter=Control.MOUSE_FILTER_IGNORE;z_index=-1
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func sync(alpha: float) -> void:
	items.clear()
	var owners: Dictionary={}
	for owner in game.lineage_names:owners[int(owner.root)]=owner
	var size:=get_viewport_rect().size
	var pixels: float=size.x/maxf(1,game.get_window().size.x)
	var font_size:=maxi(12,roundi(16*pixels))
	var font: Font=ThemeDB.fallback_font
	for cell in game.world.cells:
		if cell.dead or not owners.has(cell.lineage_id()):continue
		if game.merge_selecting() and not game._merge_bright(cell):continue
		if game.perception=="interoception" and cell!=game._follow_cell():continue
		var owner: Dictionary=owners[cell.lineage_id()]
		var at: Vector2=cell.previous_position+game.Simulation.Medium.offset(cell.previous_position,cell.position)*game._cell_render_alpha(cell,alpha)
		var center: Vector2=game._world_screen(at)
		var family_label:=str(owner.get("name","")).strip_edges()
		var fav_label: String=str(cell.favorite_name).strip_edges() if cell.favorite else ""
		var text: String=fav_label+" · "+family_label if fav_label!="" and family_label!="" else fav_label if fav_label!="" else family_label
		if text=="":continue
		var width: float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var bounds:=Rect2(Vector2(center.x-width*.5-7*pixels,center.y-cell.extent()*game.zoom-font_size-13*pixels),Vector2(width+14*pixels,font_size+10*pixels))
		if not Rect2(Vector2.ZERO,size).intersects(bounds):continue
		items.append({"cell":cell.id,"root":cell.lineage_id(),"name":text,"online":owner.online,"bounds":bounds,"font_size":font_size,"pixels":pixels})
	queue_redraw()
func _draw() -> void:
	var font: Font=ThemeDB.fallback_font
	for item in items:
		var color:=Color("9ce9d5") if item.online else Color("77909e")
		var background:=Color(.03,.13,.18,.88 if item.online else .58)
		draw_style_box(_style(background,color,item.pixels),item.bounds)
		draw_string(font,item.bounds.position+Vector2(7*item.pixels,item.bounds.size.y-6*item.pixels),item.name,HORIZONTAL_ALIGNMENT_LEFT,-1,item.font_size,color)
func _style(background: Color,color: Color,pixels: float) -> StyleBoxFlat:
	var key: String=str(background)+str(color)+str(pixels)
	if styles.has(key):return styles[key]
	if styles.size()>4:styles.clear()
	var style:=StyleBoxFlat.new();style.bg_color=background;style.border_color=color;style.set_border_width_all(maxi(1,roundi(pixels)));style.set_corner_radius_all(roundi(5*pixels));styles[key]=style;return style
