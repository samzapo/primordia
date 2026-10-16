extends RefCounted
## Canonical durable biology at the stopped/reloaded boundary, before any tick.
## Ignore only implementation caches; keep anatomy, membrane state, resources,
## particles, history, random state, dormant bodies and pending elapsed time.
const CACHE := {
 "cell":["render_revision"],
 "membrane":["native_constraints","native_compression","native_outline","normals","rest_points","rest_lengths","gradients","arcs","cached_outline","geometry_dirty","outline_dirty"],
}
static func canonical(value,objects: Array,path: Array=[]):
 if value is Dictionary:
  if value.has("$ref"):
   var index:=int(value["$ref"])
   if index<0 or index>=objects.size():return ["invalid-reference"]
   var record: Dictionary=objects[index]
   if index in path:return ["cycle",record.kind]
   var next:=path.duplicate();next.append(index)
   var fields: Dictionary=record.fields.duplicate()
   for key in CACHE.get(record.kind,[]):fields.erase(key)
   return [record.kind,canonical(fields,objects,next)]
  var keys: Array=value.keys();keys.sort_custom(func(a,b):return var_to_str(a)<var_to_str(b))
  var result: Array=[]
  for key in keys:result.append([key,canonical(value[key],objects,path)])
  return result
 if value is Array:
  var result: Array=[]
  for item in value:result.append(canonical(item,objects,path))
  return result
 return value

static func digest(value) -> String:
 var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(value));return hash.finish().hex_encode()

static func manifest(saved: Dictionary) -> Dictionary:
 var graph: Dictionary=saved.get("graph",{})
 var objects: Array=graph.get("objects",[])
 var cells: Dictionary={}
 var duplicate_ids:=false
 for record in objects:
  if record.get("kind","")!="cell":continue
  var identity:=str(record.fields.get("id",-1))
  if cells.has(identity):duplicate_ids=true
  var hashes: Dictionary={}
  for key in record.fields:
   if key not in CACHE.cell:hashes[key]=digest(canonical(record.fields[key],objects))
  cells[identity]=hashes
 return {"world_id":saved.get("world_id",""),"tick":saved.get("tick",-1),"cells":cells,"duplicate_ids":duplicate_ids,"digest":digest(canonical(cells,[]))}

static func compare(before: Dictionary,after: Dictionary) -> Dictionary:
 var missing: Array=[];var changed: Dictionary={}
 for identity in before.cells:
  if not after.cells.has(identity):missing.append(identity);continue
  var fields: Array=[]
  for field in before.cells[identity]:
   if after.cells[identity].get(field,"")!=before.cells[identity][field]:fields.append(field)
  if not fields.is_empty():changed[identity]=fields
 return {"ok":before.world_id==after.world_id and before.tick==after.tick and not before.duplicate_ids and not after.duplicate_ids and missing.is_empty() and changed.is_empty(),"world_id":before.world_id,"tick":before.tick,"before_cells":before.cells.size(),"after_cells":after.cells.size(),"before_digest":before.digest,"after_digest":after.digest,"missing":missing,"changed":changed}
