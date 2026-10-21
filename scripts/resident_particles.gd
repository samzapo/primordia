extends RefCounted
const Catalog=preload("res://scripts/chemistry_catalog.gd")
## Main-device resident particles. All RD work is ordered on the render thread.
## No synchronous readback in advance(); snapshots are validation-only.
signal ready(ok: bool, reason: String)
signal snapshot_ready(data: PackedFloat32Array)
signal contacts_ready(data: Dictionary)
signal exchange_ready(receipt: Dictionary)
signal closed
var texture := Texture2DRD.new()
var rd: RenderingDevice
var state := RID()
var flow := RID()
var _mouth_count:=0 # Render-thread-owned descriptor count.
var shader := RID()
var pipeline := RID()
var bindings := RID()
var count := 0
var upload_bytes := 0
var dispatches := 0
var readbacks := 0
var thinning_readback_bytes:=0
var width := 768
var height := 1
var _publication
var publication_busy := false
signal publication_ready(data: Dictionary)
var _initialized:=false
var _started:=false
var _closing := false
var _close_queued := false
var _source := ""
var interaction_mode := 0
var acidity := 0.4
var contact_sources: Array[String] = []
var contact_shaders: Array[RID] = []
var contact_pipelines: Array[RID] = []
var contact_sets: Array[RID] = []
var contact_buffers: Array[RID] = []
var padded_count := 1
var reaction_tick := 0
var _grid_valid := false
const Radix=preload("res://scripts/resident_grid.gd")
var grid_backend:="radix"
var grid_dispatches:=0
var grid_builds:=0
var _radix: RefCounted
var _radix_source:=""
func configure_grid(backend: String) -> bool:
	if _started or backend not in ["bitonic","radix"]: return false
	grid_backend=backend
	return true
const Perception=preload("res://scripts/resident_perception.gd")
var perception_enabled:=false
var perception_spread_queries:=true
var perception_time:=0.0
var _perception: RefCounted
var _perception_source:=""
var _perception_initial:=PackedByteArray()
func configure_perception(now: float=0.0) -> bool:
	if _started or not exchange_enabled or exchange_queue_depth!=1 or exchange_resident_capacity or not is_finite(now) or now<0: return false
	perception_enabled=true;perception_time=now
	_perception=Perception.new()
	return true
const Transfer=preload("res://scripts/resident_transfer.gd")
var bounded_dispatch:=true
var _high_water:=1
var work_count:=1
var work_padded:=1
func _set_work_count(value: int) -> void:
	work_count=clampi(value,1,count) if transfer_enabled and bounded_dispatch else count
	work_padded=1
	while work_padded<work_count: work_padded*=2
	for component in [_exchange,_perception,_exposure,_transfer,_chemistry]:
		if component!=null: component.count=work_count
	if _radix!=null:
		_radix.count=work_padded;_radix.groups=ceili(work_padded/128.0)
	_grid_valid=false
var transfer_enabled:=false
var _transfer
var _transfer_source:=""
var _transfer_pending: Dictionary={}
var transfer_readback_bytes:=0
var transfer_calls:=0
func configure_transfer(local_sources: bool=true) -> bool:
	if _started or not perception_enabled: return false
	transfer_enabled=true;_perception.local_sources=local_sources
	return true
func take_outside(region: Vector4,views: Array=[],use_union: bool=false) -> Dictionary:
	if not _transfer_pending.is_empty(): return _transfer_pending
	if not transfer_enabled or not _initialized or _closing:
		return {"error":"Transfer unavailable or unacknowledged"}
	if not Vector2(region.x,region.y).is_finite() or not Vector2(region.z,region.w).is_finite() or region.z<0 or region.w<0:
		return {"error":"Invalid transfer bounds"}
	if use_union:
		if views.size()>8: return {"error":"At most eight camera regions"}
		for view in views:
			if not view is Vector4 or not Vector2(view.x,view.y).is_finite() or not Vector2(view.z,view.w).is_finite() or view.z<0 or view.w<0: return {"error":"Invalid camera bounds"}
	RenderingServer.call_on_render_thread(func():
		_transfer_pending=_transfer.take(region,views,use_union);_grid_valid=false;_sync_semaphore.post())
	_sync_semaphore.wait()
	transfer_calls+=1;transfer_readback_bytes+=_transfer_pending.readback_bytes
	_transfer_pending["ticket"]=transfer_calls
	_transfer_pending["time"]=perception_time
	return _transfer_pending
func acknowledge_transfer(ticket: int) -> bool:
	if _transfer_pending.get("ticket",-1)!=ticket: return false
	_transfer_pending={}
	return true
const Exposure=preload("res://scripts/resident_exposure.gd")
var exposure_enabled:=false
var _exposure: RefCounted
var _exposure_source:=""
var _sync_receipt: Dictionary={}
var _export_data: Dictionary={}
func export_sync() -> Dictionary:
	if not _initialized: return {}
	RenderingServer.call_on_render_thread(_export_rd)
	_sync_semaphore.wait()
	var result:=_export_data;_export_data={}
	return result
func _export_rd() -> void:
	_export_data={"state":rd.texture_get_data(state,0).to_float32_array().slice(0,count*12),
		"metadata":rd.buffer_get_data(_perception.buffers[0])}
	readbacks+=1
	_sync_semaphore.post()
func slot_handle_sync(slot: int) -> Vector2i:
	if slot<0 or slot>=count or not _initialized or _closing: return Vector2i(-1,-1)
	RenderingServer.call_on_render_thread(func():
		_export_data={"identity":rd.buffer_get_data(_exchange.buffers[4],slot*8,8)}
		_sync_semaphore.post())
	_sync_semaphore.wait()
	var data: PackedByteArray=_export_data.identity;_export_data={}
	return Vector2i(slot,data.decode_u32(0))
func report_sync(slot: int) -> PackedByteArray:
	RenderingServer.call_on_render_thread(func():
		_export_data={"metadata":rd.buffer_get_data(_perception.buffers[0],slot*64,64)}
		_sync_semaphore.post())
	_sync_semaphore.wait()
	var result: PackedByteArray=_export_data.metadata;_export_data={}
	return result
var _sync_semaphore:=Semaphore.new()
var exchange_prepare_usec:=0
var exchange_wait_usec:=0
func configure_exposure() -> bool:
	if _started or not perception_enabled: return false
	exposure_enabled=true
	return true
# A bounded blocking fence avoids multi-frame biology lag. Only compact receipts
# cross the device boundary; render-thread ownership remains unchanged.
func exchange_sync(cells: Array, emissions: Array=[], handles: Array=[], queries: Array=[], options: Dictionary={}) -> Dictionary:
	var started:=Time.get_ticks_usec()
	var prior_prepare:=exchange_prepare_usec
	options=options.duplicate();options["synchronous"]=true
	if not exchange(cells,emissions,handles,false,queries,options): return {"error":"Resident exchange refused: "+exchange_error}
	_sync_semaphore.wait()
	exchange_wait_usec+=Time.get_ticks_usec()-started-(exchange_prepare_usec-prior_prepare)
	var result:=_sync_receipt
	_sync_receipt={}
	_exchange_main(result)
	return result
const Chemistry=preload("res://scripts/resident_chemistry.gd")
var chemistry_enabled:=false
var chemistry_seed:=0
var environment_upload_bytes:=0
var _chemistry: RefCounted
var _chemistry_source:=""
var _initial_acid:=PackedFloat32Array()
func configure_chemistry(values: PackedFloat32Array, random_seed: int=0) -> bool:
	if _started or not perception_enabled or interaction_mode!=3 or values.size()!=2560: return false
	for value in values:
		if not is_finite(value) or value<0 or value>1: return false
	chemistry_enabled=true;chemistry_seed=random_seed;_initial_acid=values.duplicate()
	return true
func environment(velocity: PackedVector2Array, values: PackedFloat32Array) -> bool:
	if not _initialized or not chemistry_enabled or _closing or (velocity.size()<2560 or velocity.size()>2688 or (velocity.size()-2560)%2!=0) or values.size()!=2560: return false
	for vector in velocity:
		if not vector.is_finite(): return false
	for value in values:
		if not is_finite(value) or value<0 or value>1: return false
	var acid:=PackedFloat32Array([1]);acid.append_array(values)
	RenderingServer.call_on_render_thread(_environment_rd.bind(velocity.to_byte_array(),acid.to_byte_array()))
	return true
func _environment_rd(velocity: PackedByteArray, values: PackedByteArray) -> void:
	# Main-device mutation belongs on the render thread. Clear on-device instead
	# of allocating/uploading one megabyte of zeros on every gameplay tick.
	rd.buffer_clear(contact_buffers[8],0,count*16)
	rd.buffer_clear(contact_buffers[5],0,64)
	_mouth_count=(velocity.size()/8-2560)/2
	rd.buffer_update(flow,0,velocity.size(),velocity)
	rd.buffer_update(contact_buffers[7],0,values.size(),values)
	environment_upload_bytes+=velocity.size()+values.size()
const Exchange=preload("res://scripts/resident_exchange.gd")
var exchange_enabled:=false
var exchange_error:=""
var exchange_busy:=false
var exchange_serial:=0
var exchange_queue_depth:=1
var exchange_inflight:=0
var exchange_peak_inflight:=0
var exchange_resident_capacity:=false
var exchange_parallel_oxygen:=true
var _exchange_slots: Array[bool]=[]
var _received: Dictionary={}
var _next_receipt:=1
var _account_ids: Array[int]=[]
var _account_instances: Array[int]=[]
var _account_caps: Array[Vector3]=[]
var _accounts_started:=false
var exchange_readback_bytes:=0
var exchange_upload_bytes:=0
var exchange_fallbacks:=0
var _exchange_source:=""
var _exchange: RefCounted
func configure_exchange(queue_depth: int=1, resident_capacity: bool=false) -> bool:
	if _started or perception_enabled or interaction_mode==0 or queue_depth<1 or queue_depth>8 or (queue_depth>1 and not resident_capacity): return false
	exchange_enabled=true;exchange_queue_depth=queue_depth;exchange_resident_capacity=resident_capacity
	_exchange_slots.resize(queue_depth);_exchange_slots.fill(false)
	return true
func _reserve_accounts(cells: Array) -> bool:
	# A bounded capacity epoch. Cells may move/deform, but births/death/resizing and
	# physiology require draining and a new epoch; they cannot reset live budgets.
	var ids: Array[int]=[]
	var instances: Array[int]=[]
	var capacities: Array[Vector3]=[]
	for cell in cells:
		ids.append(cell.id);instances.append(cell.get_instance_id())
		capacities.append(Vector3(cell.gut_capacity(),cell.oxygen_capacity(),float(preload("res://scripts/chemistry_catalog.gd").data().ecology.carbon_capacity)*cell.growth_scale()))
	if _accounts_started:
		return ids==_account_ids and instances==_account_instances and capacities==_account_caps
	_account_ids=ids;_account_instances=instances;_account_caps=capacities
	return true
func end_capacity_epoch() -> bool:
	# Caller must first credit every delivered receipt. No outstanding reservation
	# may be forgotten or reassigned to another organism.
	if not exchange_resident_capacity or exchange_inflight>0 or _closing: return false
	_accounts_started=false;_account_ids.clear();_account_instances.clear();_account_caps.clear()
	return true
func exchange(cells: Array, emissions: Array=[], handles: Array=[], asynchronous: bool=true, queries: Array=[], options: Dictionary={}) -> bool:
	var prepare_started:=Time.get_ticks_usec()
	exchange_error="Unavailable or busy"
	if not exchange_enabled or exchange_inflight>=exchange_queue_depth or _closing or not _initialized: return false
	var batch:=Exchange.prepare(cells,emissions,handles,options.get("feeding",true),options.get("coarse",{}))
	if batch.has("error"): exchange_error=batch.error;return false
	batch["scope"]=options.get("scope",Vector4(0,0,-1,-1))
	batch["count_scope"]=options.get("count_scope",batch.scope)
	batch["chemistry"]=chemistry_enabled and options.get("chemistry",true)
	batch["summaries"]=options.get("summaries",false)
	batch["projection"]=options.get("projection",true)
	batch["synchronous"]=options.get("synchronous",false)
	batch["exposure"]=options.get("exposure",false) and exposure_enabled
	if batch.exposure:
		var exposure_batch:=Exposure.prepare(cells)
		if exposure_batch.has("error"): exchange_error=exposure_batch.error;return false
		batch.merge(exposure_batch)
	if not perception_enabled and not queries.is_empty(): return false
	if not chemistry_enabled and batch.body_count+batch.emit_count+batch.inspect_count+queries.size()==0: return false
	var perception_batch: Dictionary={}
	if perception_enabled:
		perception_batch=_perception.prepare_batch(emissions,queries)
		if perception_batch.has("error"): exchange_error=perception_batch.error;return false
	if exchange_resident_capacity and not _reserve_accounts(cells): return false
	if perception_enabled:
		_perception.sources=perception_batch.sources
		perception_batch.erase("sources")
		batch.merge(perception_batch)
		batch["source_count"]=Perception.MAX_SOURCES if _perception.local_sources else _perception.sources.size()
		batch["now"]=perception_time
		batch["spread_queries"]=perception_spread_queries
	var slot:=_exchange_slots.find(false)
	_exchange_slots[slot]=true
	exchange_inflight+=1;exchange_peak_inflight=maxi(exchange_peak_inflight,exchange_inflight)
	exchange_busy=exchange_inflight>=exchange_queue_depth;exchange_serial+=1
	batch["serial"]=exchange_serial;batch["ring_slot"]=slot
	# Only a sole blocking exchange can safely shrink work. Older asynchronous
	# receipts may arrive after later emissions and must keep the monotonic bound.
	batch["trim_work"]=batch.synchronous and exchange_inflight==1
	batch["summary_offset"]=batch.body_count+batch.feed_count+batch.emit_count+batch.inspect_count*4+batch.get("query_count",0)*5
	batch["chemistry_offset"]=batch.summary_offset+(batch.get("query_count",0)*Perception.SUMMARY_VECTORS if batch.summaries else 0)
	batch["exposure_offset"]=batch.chemistry_offset+(Chemistry.RECEIPT_VECTORS if batch.chemistry else 0)
	batch["parallel_oxygen"]=exchange_parallel_oxygen
	batch["accounts"]=0 if not exchange_resident_capacity else (2 if _accounts_started else 1)
	if exchange_resident_capacity: _accounts_started=true
	exchange_prepare_usec+=Time.get_ticks_usec()-prepare_started
	RenderingServer.call_on_render_thread(_exchange_rd.bind(batch,asynchronous))
	return true
func _exchange_rd(batch: Dictionary, asynchronous: bool) -> void:
	if batch.emit_count>0: _set_work_count(_high_water+batch.emit_count)
	# Expiry is global, independent of camera or receptor presence.
	if perception_enabled: _perception.dispatch(1,batch,batch.now,ceili(work_count/64.0))
	# Sensing samples the same pre-feeding state for every receptor in this batch.
	if (batch.feed_count>0 or batch.get("query_count",0)>0) and not _grid_valid: _prepare_grid_rd()
	if perception_enabled:
		exchange_upload_bytes+=_perception.upload(batch)
		if batch.query_count>0: _perception.dispatch(4 if batch.spread_queries else 3,batch,batch.now,batch.query_count if batch.spread_queries else ceili(batch.query_count/64.0))
	exchange_upload_bytes+=_exchange.upload(batch)
	if batch.feed_count>0 and batch.parallel_oxygen: _exchange.dispatch(4,batch,ceili(work_count/128.0))
	_exchange.dispatch(1,batch,1)
	if perception_enabled and batch.emit_count>0:
		_perception.dispatch(2,batch,batch.now,ceili(batch.emit_count/64.0))
		_perception.dispatch(1,batch,batch.now,ceili(work_count/64.0))
	if batch.emit_count>0: _grid_valid=false
	if batch.exposure and batch.body_count>0:
		if not _grid_valid: _prepare_grid_rd()
		exchange_upload_bytes+=_exposure.upload(batch)
		_exposure.dispatch(0,batch);_exposure.dispatch(1,batch)
	if batch.body_count>0 and batch.projection: _exchange.dispatch(2,batch,ceili(work_count/128.0))
	if (batch.body_count>0 and batch.projection) or batch.emit_count>0: _grid_valid=false
	if batch.inspect_count>0: _exchange.dispatch(3,batch,ceili(batch.inspect_count/128.0))
	var size: int=batch.chemistry_offset*16
	if batch.chemistry:
		_chemistry.receipt(batch)
		batch["chemistry_tick"]=_chemistry.last_tick
		size+=Chemistry.RECEIPT_VECTORS*16
	if batch.exposure: size+=(batch.body_count*(Exposure.HITS_PER_BODY+1)+batch.decoy_count)*16
	var callback:=_exchange_received.bind(batch)
	if asynchronous:
		var error:=rd.buffer_get_data_async(_exchange.receipt_buffers[batch.ring_slot],callback,0,size)
		if error==OK: return
		exchange_fallbacks+=1
	# Preserve already-committed receipts if async readback is unsupported.
	callback.call(rd.buffer_get_data(_exchange.receipt_buffers[batch.ring_slot],0,size))
func thin_sync(probability: float,serial: int) -> Dictionary:
	if exchange_inflight>0 or not chemistry_enabled or not _initialized or _closing or not is_finite(probability) or probability<0 or probability>1:return {"error":"Invalid resident thinning request"}
	RenderingServer.call_on_render_thread(func():
		_export_data=_chemistry.thin(probability,serial)
		thinning_readback_bytes+=_export_data.readback_bytes
		_high_water=maxi(1,_export_data.high_water);_set_work_count(_high_water)
		_sync_semaphore.post())
	_sync_semaphore.wait()
	return _export_data

func carbon_supply_sync(cold: PackedFloat32Array,factor: float,target: float,phase: int=-1,phase_seed: int=0,kind: int=5,factors: PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	if kind not in [1,5] or phase < -1 or phase>=20 or (not factors.is_empty() and factors.size()!=2560) or cold.size()!=2560 or exchange_inflight>0 or not chemistry_enabled or not _initialized or _closing or not is_finite(factor) or factor<0 or factor>1 or not is_finite(target) or target<0:return {"error":"Invalid atmospheric carbon request"}
	for value in factors:
		if not is_finite(value) or value<0 or value>1:return {"error":"Invalid atmospheric exchange factor"}
	for value in cold:
		if not is_finite(value) or value<0:return {"error":"Invalid cold carbon inventory"}
	RenderingServer.call_on_render_thread(func():
		if not _grid_valid:_prepare_grid_rd()
		_export_data=_chemistry.carbon_supply(cold,factor,target,phase,phase_seed,kind,factors)
		_grid_valid=false
		_sync_semaphore.post())
	_sync_semaphore.wait()
	return _export_data

func project_cached(cells: int) -> void:
	# The last completed exposure exchange owns these immutable body buffers.
	# Queue projection without another readback after every contact was delivered.
	if cells>0 and _initialized:
		RenderingServer.call_on_render_thread(func():
			_exchange.dispatch(2,{"body_count":cells,"ring_slot":0},ceili(work_count/128.0))
			_grid_valid=false)
func _exchange_received(bytes: PackedByteArray,batch: Dictionary) -> void:
	var receipt:=Exchange.decode(bytes,batch)
	for emission in receipt.emissions:
		if emission.accepted: _high_water=maxi(_high_water,emission.handle.x+1)
	if batch.emit_count>0: _set_work_count(_high_water)
	if perception_enabled:
		var at: int=(batch.body_count+batch.feed_count+batch.emit_count+batch.inspect_count*4)*16
		receipt["senses"]=Perception.decode(bytes,at,batch.query_count)
		if batch.summaries: receipt["summaries"]=Perception.summaries(bytes,batch.summary_offset,batch.query_count)
	if batch.chemistry:
		receipt["chemistry"]=Chemistry.decode(bytes,batch.chemistry_offset)
		receipt.chemistry["tick"]=batch.chemistry_tick
		if transfer_enabled and batch.get("trim_work",false):
			# Compact receipt bounds work by the last live slot. Neither slot
			# allocation nor generation counters move or reset.
			_high_water=maxi(1,receipt.chemistry.high_water);_set_work_count(_high_water)
	if batch.exposure: receipt["exposure"]=Exposure.decode(bytes,batch)
	receipt["serial"]=batch.serial;receipt["readback_bytes"]=bytes.size();receipt["ring_slot"]=batch.ring_slot
	if batch.synchronous:
		_sync_receipt=receipt;_sync_semaphore.post()
	else: _exchange_main.call_deferred(receipt)
func _exchange_main(receipt: Dictionary) -> void:
	# Readback callbacks need not arrive in serial order. Deliver each exactly once.
	assert(receipt.serial>=_next_receipt and receipt.serial<=exchange_serial and not _received.has(receipt.serial))
	_received[receipt.serial]=receipt
	while _received.has(_next_receipt):
		var next: Dictionary=_received[_next_receipt]
		_received.erase(_next_receipt);_next_receipt+=1
		_exchange_slots[next.ring_slot]=false;exchange_inflight-=1
		exchange_busy=exchange_inflight>=exchange_queue_depth
		exchange_readback_bytes+=next.readback_bytes
		exchange_ready.emit(next)
	if _closing and exchange_inflight==0: _finish_close()

func configure_interactions(mode: String, acid: float = 0.4) -> bool:
	if _started or (chemistry_enabled and mode!="chemistry") or (exchange_enabled and mode=="off") or mode not in ["off","contacts","collisions","chemistry"] or not is_finite(acid) or acid<0 or acid>1: return false
	interaction_mode=["off","contacts","collisions","chemistry"].find(mode)
	acidity=acid
	return true
func initialize(values: PackedFloat32Array, velocity: PackedVector2Array, metadata: Array=[]) -> void:
	if _started:
		push_error("Resident pool already initialized");return
	_started=true
	count = values.size()/12
	if count < 1 or count > 100000 or values.size()%12 != 0 or (velocity.size()<2560 or velocity.size()>2688 or (velocity.size()-2560)%2!=0):
		_ready_main.call_deferred(false,"Invalid resident particle capacity or flow")
		return
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()=="gl_compatibility":
		_ready_main.call_deferred(false,"Requires Mobile/Forward+ and a real RenderingDevice display")
		return
	for k in range(0,values.size(),12):
		if values[k+7]>=0: _high_water=k/12+1
		for j in 12:
			if not is_finite(values[k+j]):
				_ready_main.call_deferred(false,"Nonfinite particle state");return
		if values[k+7]<-1 or values[k+7]>25 or values[k+7]!=floor(values[k+7]) or values[k+9]<0 or values[k+10]<0 or (values[k+7]>=0 and (values[k+8]<=0 or values[k+8]>17)):
			_ready_main.call_deferred(false,"Invalid particle kind, material or diameter");return
		if exchange_enabled and values[k+11]!=0:
			_ready_main.call_deferred(false,"Product reserves are not supported by the exchange prototype");return
	if not perception_enabled and not metadata.is_empty():
		_ready_main.call_deferred(false,"Metadata requires resident perception");return
	if perception_enabled:
		var initial: Dictionary=_perception.prepare_initial(values,metadata)
		if initial.has("error"):
			_ready_main.call_deferred(false,initial.error);return
		_perception_initial=initial.bytes
		_perception_source=FileAccess.get_file_as_string("res://shaders/compute/resident_perception.glsl.txt").replace("#[compute]","")
	while padded_count<count: padded_count*=2
	if transfer_enabled: _transfer_source=FileAccess.get_file_as_string("res://shaders/compute/resident_transfer.glsl.txt").replace("#[compute]","")
	if exposure_enabled:
		_exposure_source=FileAccess.get_file_as_string("res://shaders/compute/resident_exposure.glsl.txt").replace("#[compute]","")
	if chemistry_enabled:
		_chemistry_source=FileAccess.get_file_as_string("res://shaders/compute/resident_chemistry.glsl.txt").replace("#[compute]","")
	if exchange_enabled:
		_exchange_source=FileAccess.get_file_as_string("res://shaders/compute/resident_exchange.glsl.txt").replace("#[compute]","")
	if interaction_mode>0:
		if grid_backend=="radix": _radix_source=FileAccess.get_file_as_string("res://shaders/compute/resident_grid.glsl.txt").replace("#[compute]","")
		for name in ["resident_contacts","resident_commit","resident_vote"]:
			contact_sources.append(FileAccess.get_file_as_string("res://shaders/compute/"+name+".glsl.txt").replace("#[compute]",""))
	height = ceili(count/256.0)
	_source = FileAccess.get_file_as_string("res://shaders/compute/resident_particles.glsl.txt").replace("#[compute]","")
	var padded := values.duplicate()
	padded.resize(width*height*4)
	RenderingServer.call_on_render_thread(_initialize_rd.bind(padded.to_byte_array(),velocity.to_byte_array()))
func _initialize_rd(bytes: PackedByteArray, velocities: PackedByteArray) -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		_ready_main.call_deferred(false,"Main RenderingDevice unavailable")
		return
	var required_buffers:=12 if exchange_enabled else (9 if interaction_mode>0 else 1)
	if rd.limit_get(RenderingDevice.LIMIT_MAX_COMPUTE_WORKGROUP_INVOCATIONS)<128 or rd.limit_get(RenderingDevice.LIMIT_MAX_STORAGE_BUFFERS_PER_SHADER_STAGE)<required_buffers or rd.limit_get(RenderingDevice.LIMIT_MAX_STORAGE_BUFFERS_PER_UNIFORM_SET)<required_buffers:
		_ready_main.call_deferred(false,"Device needs 128 compute invocations and %d storage buffers per stage/set" % required_buffers)
		return
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if not rd.texture_is_format_supported_for_usage(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,usage):
		_ready_main.call_deferred(false,"RGBA32F storage/sampling unsupported")
		return
	var source := RDShaderSource.new()
	source.source_compute = Catalog.glsl(_source)
	var spirv := rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "":
		_ready_main.call_deferred(false,spirv.compile_error_compute)
		return
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var format := RDTextureFormat.new()
	format.width=width;format.height=height
	format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits=usage
	state=rd.texture_create(format,RDTextureView.new(),[bytes])
	_mouth_count=(velocities.size()/8-2560)/2
	flow=rd.storage_buffer_create(2688*8)
	rd.buffer_update(flow,0,velocities.size(),velocities)
	if not pipeline.is_valid() or not state.is_valid() or not flow.is_valid():
		_ready_main.call_deferred(false,"Resident pipeline/resource allocation failed")
		return
	var a := RDUniform.new()
	a.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;a.binding=0;a.add_id(state)
	var b := RDUniform.new()
	b.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;b.binding=1;b.add_id(flow)
	bindings=rd.uniform_set_create([a,b],shader,0)
	if not bindings.is_valid():
		_ready_main.call_deferred(false,"Resident bindings invalid")
		return
	if interaction_mode>0 and not _initialize_contacts():
		_ready_main.call_deferred(false,"Contact pipeline creation failed");return
	if interaction_mode>0 and grid_backend=="radix":
		_radix=Radix.new()
		if not _radix.initialize(rd,contact_buffers[0],padded_count,_radix_source):
			_ready_main.call_deferred(false,"Radix grid creation failed");return
	if exchange_enabled:
		_exchange=Exchange.new()
		if not _exchange.initialize(rd,state,count,contact_buffers[0],contact_buffers[1],_exchange_source,exchange_queue_depth):
			_ready_main.call_deferred(false,"Cell exchange pipeline creation failed");return
	if perception_enabled:
		if not _perception.initialize(rd,state,_exchange.buffers[4],contact_buffers[0],contact_buffers[1],_exchange.receipt_buffers,_perception_initial,_perception_source,count):
			_ready_main.call_deferred(false,"Resident perception creation failed");return
		upload_bytes+=_perception_initial.size()
		_perception_initial.clear()
	if exposure_enabled:
		_exposure=Exposure.new()
		if not _exposure.initialize(rd,state,_exchange.buffers[4],_perception.buffers[0],_exchange.buffers[0],_exchange.buffers[1],contact_buffers[0],contact_buffers[1],_exchange.receipt_buffers,count,_exposure_source):
			_ready_main.call_deferred(false,"Resident exposure creation failed");return
	if transfer_enabled:
		_transfer=Transfer.new()
		if not _transfer.initialize(rd,state,_perception.buffers[0],_exchange.buffers[4],count,_transfer_source):
			_ready_main.call_deferred(false,"Could not initialize bounded transfers");return
	if chemistry_enabled:
		_chemistry=Chemistry.new()
		if not _chemistry.initialize(rd,state,contact_buffers[7],contact_buffers[0],contact_buffers[1],_exchange.receipt_buffers,contact_buffers[5],_exchange.buffers[4],contact_buffers[8],count,chemistry_seed,_chemistry_source):
			_ready_main.call_deferred(false,"Resident chemistry creation failed");return
	_set_work_count(_high_water)
	upload_bytes += bytes.size()+velocities.size()
	_ready_main.call_deferred(true,"")
func _initialize_contacts() -> bool:
	for size in [padded_count*8,40960*8,count*8,count*64*4,count*4,16*4,count*8,2561*4,count*16]:
		var buffer := rd.storage_buffer_create(size)
		contact_buffers.append(buffer)
		if not buffer.is_valid(): return false
	var zero:=PackedByteArray();zero.resize(count*16)
	rd.buffer_update(contact_buffers[8],0,zero.size(),zero)
	var zero_stats:=PackedByteArray();zero_stats.resize(64)
	rd.buffer_update(contact_buffers[5],0,64,zero_stats)
	var acid:=PackedFloat32Array([1 if chemistry_enabled else -1])
	if chemistry_enabled: acid.append_array(_initial_acid)
	else: acid.resize(2561)
	rd.buffer_update(contact_buffers[7],0,acid.size()*4,acid.to_byte_array())
	for text in contact_sources:
		var source := RDShaderSource.new()
		source.source_compute=Catalog.glsl(text)
		var spirv := rd.shader_compile_spirv_from_source(source)
		if spirv.compile_error_compute!="":
			push_error(spirv.compile_error_compute);return false
		var sh := rd.shader_create_from_spirv(spirv)
		contact_shaders.append(sh)
		var pipe := rd.compute_pipeline_create(sh)
		contact_pipelines.append(pipe)
		var uniforms: Array[RDUniform] = []
		for binding in 10:
			var u := RDUniform.new()
			u.binding=binding
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if binding==0 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id(state if binding==0 else contact_buffers[binding-1])
			uniforms.append(u)
		var uniform_set := rd.uniform_set_create(uniforms,sh,0)
		contact_sets.append(uniform_set)
		if not pipe.is_valid() or not uniform_set.is_valid(): return false
	return true
func interact_only() -> void:
	assert(interaction_mode>0 and not _closing)
	RenderingServer.call_on_render_thread(_contacts_rd)
func _contact_pass(stage: int, groups: int, level: int = 0, stride: int = 0, commit: bool = false) -> void:
	var params := PackedByteArray()
	params.resize(32)
	params.encode_u32(0,work_count);params.encode_u32(4,work_padded);params.encode_u32(8,stage)
	params.encode_u32(12,level);params.encode_u32(16,stride);params.encode_u32(20,interaction_mode)
	params.encode_float(24,acidity);params.encode_u32(28,(1 if perception_enabled else 0) if stage==0 else reaction_tick)
	var index := (2 if stage==5 else 1) if commit else 0
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,contact_pipelines[index])
	rd.compute_list_bind_uniform_set(list,contact_sets[index],0)
	rd.compute_list_set_push_constant(list,params,32)
	rd.compute_list_dispatch(list,groups,1,1)
	rd.compute_list_end()
func _prepare_grid_rd() -> void:
	_contact_pass(0,ceili(maxi(work_padded,40960)/128.0))
	grid_builds+=1;grid_dispatches+=2
	if grid_backend=="radix":
		_radix.sort();grid_dispatches+=12
	else:
		var level := 2
		while level<=work_padded:
			var stride := level/2
			while stride>0:
				_contact_pass(1,ceili(work_padded/128.0),level,stride)
				grid_dispatches+=1;stride/=2
			level*=2
	_contact_pass(2,ceili(work_padded/128.0))
	_grid_valid=true
func _contacts_rd() -> void:
	if not _grid_valid: _prepare_grid_rd()
	var zeros:=PackedByteArray();zeros.resize(64)
	rd.buffer_update(contact_buffers[5],0,64,zeros)
	_contact_pass(3,ceili(work_count/128.0))
	if interaction_mode>=2:
		_contact_pass(5,ceili(work_count/128.0),0,0,true)
		_contact_pass(4,ceili(work_count/128.0),0,0,true)
	reaction_tick+=1
func contact_snapshot() -> void:
	RenderingServer.call_on_render_thread(_contact_snapshot_rd)
func _contact_snapshot_rd() -> void:
	var result := {}
	if not contact_buffers.is_empty():
		result={"counts":rd.buffer_get_data(contact_buffers[2],0,work_count*4).to_int32_array(),
			"pairs":rd.buffer_get_data(contact_buffers[3]).to_int32_array(),
			"choices":rd.buffer_get_data(contact_buffers[4]).to_int32_array(),
			"stats":rd.buffer_get_data(contact_buffers[5]).to_int32_array(),
			"order":rd.buffer_get_data(contact_buffers[0]).to_int32_array(),
			"ranges":rd.buffer_get_data(contact_buffers[1]).to_int32_array()}
	readbacks+=1
	_contact_snapshot_main.call_deferred(result)
func _contact_snapshot_main(result: Dictionary) -> void: contacts_ready.emit(result)
func _ready_main(ok: bool, reason: String) -> void:
	if _closing: ready.emit(false,"Initialization cancelled");return
	_initialized=ok
	if ok: texture.texture_rd_rid=state
	ready.emit(ok,reason)
func advance(dt: float, tick: int) -> void:
	assert(dt>0 and dt<=2 and tick>=0 and tick<=0xffffffff and not _closing)
	if perception_enabled: perception_time+=dt
	RenderingServer.call_on_render_thread(_advance_rd.bind(dt,tick,perception_time))
func _advance_rd(dt: float, tick: int, now: float) -> void:
	_grid_valid=false
	var params := PackedByteArray()
	params.resize(16);params.encode_u32(0,work_count);params.encode_float(4,dt);params.encode_u32(8,tick);params.encode_u32(12,_mouth_count)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,bindings,0)
	rd.compute_list_set_push_constant(list,params,16)
	rd.compute_list_dispatch(list,ceili(work_count/128.0),1,1)
	rd.compute_list_end()
	if perception_enabled: _perception.dispatch(1,{},now,ceili(work_count/64.0))
	if chemistry_enabled:
		_prepare_grid_rd()
		_chemistry.advance(dt,tick,now)
	if interaction_mode>0: _contacts_rd()
	dispatches += 1
	# Main device submission and barriers are owned by the renderer. No submit/sync.
func upload(values: PackedFloat32Array) -> void:
	if exchange_enabled or values.size()!=count*12 or _closing:
		push_error("Whole-pool upload is unavailable for exchange-owned slots");return
	var padded := values.duplicate()
	padded.resize(width*height*4)
	RenderingServer.call_on_render_thread(_upload_rd.bind(padded.to_byte_array()))
func _upload_rd(bytes: PackedByteArray) -> void:
	_grid_valid=false
	rd.texture_update(state,0,bytes)
	upload_bytes += bytes.size()
func snapshot() -> void:
	RenderingServer.call_on_render_thread(_snapshot_rd)
func _snapshot_rd() -> void:
	# Explicit blocking diagnostic, outside timed windows. Never used by gameplay.
	var values := rd.texture_get_data(state,0).to_float32_array()
	values.resize(count*12)
	readbacks += 1
	_snapshot_main.call_deferred(values)
func _snapshot_main(values: PackedFloat32Array) -> void:
	snapshot_ready.emit(values)
func close() -> void:
	if _closing: return
	release_cytoplasms()
	_closing=true
	if exchange_inflight>0: return
	_finish_close()
func _finish_close() -> void:
	if publication_busy: return
	if _close_queued: return
	_close_queued=true
	texture.texture_rd_rid=RID()
	RenderingServer.call_on_render_thread(_close_rd)
func _close_rd() -> void:
	if rd != null:
		if _publication!=null: _publication.close()
		if _transfer!=null: _transfer.close()
		if _exposure!=null: _exposure.close()
		if _chemistry!=null: _chemistry.close()
		if _perception!=null: _perception.close()
		if _exchange!=null: _exchange.close()
		if _radix!=null: _radix.close()
		for resource in contact_sets+contact_pipelines+contact_shaders+contact_buffers+[bindings,pipeline,shader,state,flow]:
			if resource.is_valid(): rd.free_rid(resource)
	rd=null # Main RenderingDevice belongs to Godot; never free it.
	_closed_main.call_deferred()
func _closed_main() -> void: closed.emit()

func publish_views(views: Array) -> bool:
	if not _initialized or _closing or publication_busy or views.size()>8 or _perception==null or _exchange==null: return false
	publication_busy=true
	RenderingServer.call_on_render_thread(func():
		if _publication==null:
			_publication=preload("res://scripts/network/gpu_publication.gd").new()
			if not _publication.initialize(rd,state,_exchange.buffers[4],_perception.buffers[0]):
				_publication.close();_publication=null
				_publication_done.call_deferred({"error":"GPU publication initialization failed"})
				return
		if not _publication.request(views,work_count,_publication_done):
			_publication_done.call_deferred({"error":"GPU publication request failed"}))
	return true

func _publication_done(data: Dictionary) -> void:
	publication_busy=false
	publication_ready.emit(data)
	if _closing: _finish_close()

func set_activity_views(views: Array,enabled: bool) -> void:
	if not _initialized or _closing or views.size()>8: return
	RenderingServer.call_on_render_thread(func():
		_exchange.set_views(views,enabled)
		if _exposure!=null: _exposure.set_views(views,enabled))

var cytoplasms: Array=[]
var cytoplasm_error:=""
func attach_cytoplasm(chem,cell) -> bool:
	if not _initialized or _closing:return false
	var component=preload("res://scripts/resident_cytoplasm.gd").new()
	if not component.attach(self,chem,cell):
		cytoplasm_error=component.error;push_error(component.error);return false
	cytoplasms=cytoplasms.filter(func(item):return not item.closed)
	cytoplasms.append(component)
	return true

func release_cytoplasms() -> void:
	for component in cytoplasms:
		if not component.closed:component.release()
	cytoplasms.clear()
