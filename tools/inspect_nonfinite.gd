extends SceneTree
const Store=preload("res://scripts/network/world_store.gd")
var invalid: Array=[]
func _initialize() -> void:
 for argument in OS.get_cmdline_user_args():
  if not argument.begins_with("--state-dir="):continue
  var directory:=argument.trim_prefix("--state-dir=")
  var store:=Store.new();store.directory=directory
  var saved:=store.load_latest()
  if saved.is_empty():print("FINITE_INSPECTION "+JSON.stringify({"path":directory,"error":store.last_error}));continue
  invalid.clear()
  var objects: Array=saved.get("graph",{}).get("objects",[])
  var bodies: Array=[]
  for index in objects.size():
   var record: Dictionary=objects[index];var fields: Dictionary=record.get("fields",{})
   var kind: String=record.get("kind","")
   for field in fields:
    if kind=="membrane" and field=="oral_angle":continue
    scan(fields[field],str(index)+":"+kind+"."+str(field))
   if kind=="cell":
    var value: Dictionary={}
    for field in ["id","lineage","dead","age","body","biomass","energy","brood_energy","health","position","velocity","angular_velocity","mass","inertia","radius"]:
     value[field]=str(fields.get(field))
    bodies.append(value)
  print("FINITE_INSPECTION "+JSON.stringify({"path":directory,"world_id":saved.get("world_id"),"epoch":saved.get("epoch"),"tick":saved.get("tick"),"invalid_count":invalid.size(),"invalid":invalid.slice(0,160),"bodies":bodies}))
 quit()
func scan(value,path: String) -> void:
 if value is float:
  if not is_finite(value):invalid.append({"path":path,"value":str(value)})
 elif value is Vector2:
  if not value.is_finite():invalid.append({"path":path,"value":str(value)})
 elif value is Array or value is PackedVector2Array or value is PackedFloat32Array or value is PackedFloat64Array:
  var count:=0;var first:=""
  for i in value.size():
   var item=value[i]
   if (item is float and not is_finite(item)) or (item is Vector2 and not item.is_finite()):
    count+=1
    if first=="":first=str(i)+":"+str(item)
   elif item is Dictionary or item is Array:scan(item,path+"["+str(i)+"]")
  if count:invalid.append({"path":path,"nonfinite":count,"first":first})
 elif value is Dictionary:
  for key in value:
   if key=="oral_angle":continue
   scan(value[key],path+"."+str(key))
