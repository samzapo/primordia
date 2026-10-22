extends RefCounted
## Runtime raster cache from the same vector artwork, for tiny external organs.
## No generated images in source and no substitute click/physics geometry.
const KINDS:=["protection","poreforming","counterattack","mitochondrion","photosynthesis","toxin","neutralizing","acidifying","regenerative","family_toward","family_away","sensing","hunting"]
const TILE:=96
const SPAN:=64.0
static var cached: Texture2D
class Ink extends RefCounted:
	var output: String=""
	var transform:=Transform2D.IDENTITY
	func draw_set_transform(at: Vector2,angle: float=0,scale: Vector2=Vector2.ONE) -> void:
		transform=Transform2D(angle,scale,0,at)
	func paint(color: Color) -> String:return "#"+color.to_html(false)
	func group(shape: String) -> void:
		output+='<g transform="matrix(%s %s %s %s %s %s)">%s</g>' % [transform.x.x,transform.x.y,transform.y.x,transform.y.y,transform.origin.x,transform.origin.y,shape]
	func draw_circle(at: Vector2,radius: float,color: Color) -> void:
		group('<circle cx="%s" cy="%s" r="%s" fill="%s" fill-opacity="%s"/>' % [at.x,at.y,radius,paint(color),color.a])
	func points_text(points: PackedVector2Array) -> String:
		var parts:=PackedStringArray()
		for point in points:parts.append("%s,%s" % [point.x,point.y])
		return " ".join(parts)
	func draw_polyline(points: PackedVector2Array,color: Color,width: float=-1,_antialias: bool=false) -> void:
		group('<polyline points="%s" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="%s" stroke-linejoin="round"/>' % [points_text(points),paint(color),color.a,maxf(1,width)])
	func draw_line(a: Vector2,b: Vector2,color: Color,width: float=-1,antialias: bool=false) -> void:
		draw_polyline(PackedVector2Array([a,b]),color,width,antialias)
	func draw_arc(at: Vector2,radius: float,start: float,end: float,count: int,color: Color,width: float=-1,antialias: bool=false) -> void:
		var points:=PackedVector2Array()
		for i in count:points.append(at+Vector2.from_angle(lerpf(start,end,i/float(count-1)))*radius)
		draw_polyline(points,color,width,antialias)
	func draw_colored_polygon(points: PackedVector2Array,color: Color) -> void:
		group('<polygon points="%s" fill="%s" fill-opacity="%s"/>' % [points_text(points),paint(color),color.a])
static func texture() -> Texture2D:
	if cached!=null:return cached
	var svg: String='<svg xmlns="http://www.w3.org/2000/svg" width="384" height="384" viewBox="0 0 256 256">'
	for i in KINDS.size():
		var ink:=Ink.new()
		preload("res://scripts/visuals.gd").icon(ink,Vector2.ZERO,KINDS[i],0,1,0,"graze",0,true)
		svg+='<g transform="translate(%s %s)">%s</g>' % [(i%4)*SPAN+SPAN/2,int(i/4)*SPAN+SPAN/2,ink.output]
	svg+="</svg>"
	var image:=Image.new()
	if image.load_svg_from_string(svg)!=OK:return null
	image.generate_mipmaps();cached=ImageTexture.create_from_image(image)
	return cached
static func draw(canvas: Node2D,at: Vector2,kind: String,angle: float,scale: float) -> bool:
	var index:=KINDS.find(kind)
	if index<0:return false
	var sheet:=texture()
	if sheet==null:return false
	canvas.draw_set_transform(at,angle,Vector2.ONE*scale)
	canvas.draw_texture_rect_region(sheet,Rect2(-Vector2.ONE*SPAN/2,Vector2.ONE*SPAN),Rect2(Vector2(index%4,int(index/4))*TILE,Vector2.ONE*TILE))
	canvas.draw_set_transform(Vector2.ZERO)
	return true

static var nucleus_cache: Dictionary={}
static func nucleus(core: PackedVector2Array,palette: Array,detail: bool) -> Texture2D:
	var key:=var_to_bytes([core,palette,detail])
	if nucleus_cache.has(key):return nucleus_cache[key]
	var ink:=Ink.new()
	preload("res://scripts/visuals.gd").nucleus_art(ink,Vector2.ZERO,1.0,core,palette,detail)
	var svg: String='<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="-2 -2 4 4">'+ink.output+'</svg>'
	var image:=Image.new()
	if image.load_svg_from_string(svg)!=OK:return null
	image.generate_mipmaps()
	var texture:=ImageTexture.create_from_image(image)
	if nucleus_cache.size()>=64:nucleus_cache.clear()
	nucleus_cache[key]=texture
	return texture
