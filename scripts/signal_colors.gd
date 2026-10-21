extends RefCounted
const CellArt=preload("res://scripts/cell_art.gd")
const ALPHA:=0.65
const LIMIT:=1024
static var cached: Dictionary={}
var texture:=ImageTexture.new()
var signature:=""
static func family(game,lineage: int) -> Color:
 if lineage<0:return Color(1,1,1,ALPHA)
 var paint: String=game.lineage_color(lineage)
 var key:=str(game.world.seed_value)+":"+str(lineage)+":"+paint
 if not cached.has(key):
  if cached.size()>=LIMIT:cached.erase(cached.keys()[0])
  var color: Color=CellArt.make(game.world.seed_value,lineage,paint).colors[1]
  color.a=ALPHA;cached[key]=color
 return cached[key]
static func root(packet: Dictionary) -> int:
 return int(packet.get("signal_lineage",packet.get("report",{}).get("lineage",-1)))
static func packed(color: Color) -> int:
 return (roundi(color.r*255)<<16)|(roundi(color.g*255)<<8)|roundi(color.b*255)
static func native_style(game) -> Dictionary:
 var colors={"_seed":game.world.seed_value,"_bases":PackedColorArray(CellArt.PALETTES.map(func(p):return Color(p[1])))}
 for cell in game.world.cells:colors[cell.lineage_id()]=family(game,cell.lineage_id())
 for row in game.lineage_names:colors[int(row.root)]=family(game,int(row.root))
 return colors
func palette(game,roots: Dictionary) -> Texture2D:
 var values: Dictionary={}
 for root_id in roots:values[int(root_id)]=family(game,int(root_id))
 for cell in game.world.cells:values[cell.lineage_id()]=family(game,cell.lineage_id())
 var keys=values.keys();keys.sort()
 var next:=str(game.world.seed_value)+str(keys)+str(values.values())
 if signature==next:return texture
 signature=next
 var slots:=2
 while slots<values.size()*2:slots*=2
 var pixels:=PackedFloat32Array();pixels.resize(slots*8)
 for key in keys:
  var slot:=int((int(key)*2654435761)&0xffffffff)&(slots-1)
  while pixels[slot*8+3]>0:slot=(slot+1)&(slots-1)
  var at:=slot*8;var color: Color=values[key]
  pixels[at]=int(key)&65535;pixels[at+1]=(int(key)>>16)&65535;pixels[at+3]=1
  pixels[at+4]=color.r;pixels[at+5]=color.g;pixels[at+6]=color.b;pixels[at+7]=color.a
 var image:=Image.create_from_data(slots*2,1,false,Image.FORMAT_RGBAF,pixels.to_byte_array())
 if texture.get_width()==slots*2:texture.update(image)
 else:texture.set_image(image)
 return texture
