extends RefCounted
## Conservative presentation broad phase, not simulation contact or packet movement.
const WIDTH:=32
const HEIGHT:=20
const TILE:=128.0
const WORLD:=Vector2(4096,2560)
static func masks(cells: Array) -> PackedInt64Array:
 var result:=PackedInt64Array();result.resize(WIDTH*HEIGHT)
 var b:=0
 for cell in cells:
  if cell.dead:continue
  assert(b<64)
  var start: Vector2=cell.previous_position
  var delta: Vector2=(cell.position-start+WORLD*.5).posmodv(WORLD)-WORLD*.5
  var reach: float=cell.extent()+8.01
  var low: Vector2=start.min(start+delta)-Vector2.ONE*reach
  var high: Vector2=start.max(start+delta)+Vector2.ONE*reach
  var x0:=floori(low.x/TILE);var y0:=floori(low.y/TILE)
  var nx:=mini(WIDTH,floori(high.x/TILE)-x0+1)
  var ny:=mini(HEIGHT,floori(high.y/TILE)-y0+1)
  for y in ny:
   for x in nx:
    var index:=posmod(y0+y,HEIGHT)*WIDTH+posmod(x0+x,WIDTH)
    result[index]=result[index] | (1<<b)
  b+=1
 return result
static func pixels(cells: Array) -> PackedFloat32Array:
 var bits:=masks(cells)
 var result:=PackedFloat32Array();result.resize(WIDTH*HEIGHT*4)
 for i in bits.size():
  for channel in 4:result[i*4+channel]=(bits[i]>>(channel*16))&65535
 return result
