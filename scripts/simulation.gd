extends RefCounted
## Authoritative fixed-step ecology, independent of input and scene nodes.
const Catalog = preload("res://scripts/chemistry_catalog.gd")
const Evolution = preload("res://scripts/evolution.gd")
const Lineage = preload("res://scripts/lineage.gd")
var lineage = Lineage.new()
const Genes = preload("res://scripts/mutations.gd")
var evolution
var server_mode := false
var remote_client := false
var command_sink: Callable
var camera_views: Array = [] # External particle detail footprints.
var external_offscreen := false
var perception_modes_enabled := false # Explicit old-reference fixtures retain coupled stepping.
var interoceptive_cells: Dictionary = {}
var family_ledgers: Array = []
var automatic_reproduction := true
const MAX_LIVE_CELLS := 64
const REPRODUCTION_RATE := 10.0
const REPRODUCTION_TISSUE_FLOOR := 12.0
const REPRODUCTION_ATP_FLOOR := 20.0
var build_original = null
var build_state: Dictionary = {}
var build_waste := 0.0
const Backend = preload("res://scripts/backend.gd")
var kernels = Backend.create()
var gpu_transport = null
var resident = null
# Only the explicit fluid comparison harness attaches this backend.
var experimental_fluid = null
const Offscreen = preload("res://scripts/offscreen_ecology.gd")
var offscreen_ecology = Offscreen.new()
var background_biology := true
var coarse_mode := false
var coarse_event_at := 0.0
var ecology_rng := RandomNumberGenerator.new()
const Transport = preload("res://scripts/particle_transport.gd")
var native_particle_pipeline := kernels != null
var native_particle_render_cache := kernels != null
var packed_particle_frame := false
var native_particles := kernels != null
var native_background_chemistry := kernels != null
var native_chemical_timestamps := true
var native_chemistry_writes := true
# Ordinary gameplay retains particle collisions; overlap is diagnostic only.
var particle_collisions := true
var native_chemistry_bounds := true
var native_chemistry_lazy_acid := true
var native_transport_bookkeeping := kernels != null
var native_particle_compaction := kernels != null
var native_fluid := kernels != null
var native_body_fluid: bool = kernels != null and kernels.has_method("fluid_body_exchange")
var native_traction: bool = kernels != null and kernels.has_method("fluid_traction")
var native_render := kernels != null
var native_exclusion := kernels != null
var native_feeding := kernels != null
var native_contacts := kernels != null
var spatial_queries := true
var stagger_sensing := true
var cell_index = preload("res://scripts/cell_index.gd").new()

const Contacts = preload("res://scripts/contacts.gd")
const Habitat = preload("res://scripts/habitat.gd")
var habitat_geometry

const Grid = preload("res://scripts/spatial_grid.gd")
const Cell = preload("res://scripts/cell.gd")
const Medium = preload("res://scripts/medium.gd")
const WORLD := Medium.WORLD
const VIEW := Vector2(1016,632)
const KINDS := Cell.KINDS
const COST := Cell.COST
const NUTRIENT := 0
const OXYGEN := 1
const WASTE := 2
const PHEROMONE := 3
const PHEROMONE_RATE := 8.0
const PHEROMONE_DECAY := 0.2 # Exponential lifetime: mean 5 s, half-life 3.47 s.
const PHEROMONE_DIFFUSION := 120.0 # World units squared / second (material: 6).
const TOXIN := 4
const CARBON := 5
const ENZYME := 6
const ANTITOXIN := 7
const ACID := 8
const BUFFER := 9
const DECOY := 10
const TAG := 11
const PORE_SUBUNIT := 12
const SPECIES_COUNT := 26
const Acidity = preload("res://scripts/acidity.gd")
const HABITATS := ["BALANCED TIDE", "LEAN HUNTING GROUNDS", "RICH / ARMORED HUNTERS"]
# Transport changes resolution outside the view, never the rate of elapsed time.
var background_transport := true
var background_period := 0.5 # Benchmark override; ordinary play uses 2 Hz.
var transport_clock := 0.0
var background_cursor := 0
var background_credit := 0.0
var background_particles := 0
var foreground_particle_ids: Array[int] = []
var background_field_clock := 0.0
var background_rng := RandomNumberGenerator.new()
var rng := RandomNumberGenerator.new()
var grid = Grid.new()
var reaction_grid = Grid.new(16.0)
var fluid = Medium.new()
var acidity = Acidity.new()
var player = Cell.new(0,Vector2(2048,1280))
var cells: Array = []
var particles: Array = []
# References to signal packets only; expiry never scans all material each tick.
var pheromones: Array = []
var events: Array = []
# Bounded, read-only presentation journal; audio never consumes gameplay events.
const SOUND_EVENT_LIMIT := 64
var sound_events: Array = []
const REACTION_SPARK_LIMIT := 128
var reaction_sparks: Array[Dictionary] = []
var reaction_serial := 0
# Immutable, bounded presentation snapshots; no extra mass or random draws.
var death_bursts: Array[Dictionary] = []
var death_serial := 0
var sound_sequence := 0
var sound_recent: Dictionary = {}
var pending_replacements: Array = []
var next_id := 1
var inherited_lineages: Dictionary = {}
var time := 0.0
var habitat := 0
var seed_value := 20261004
var spawn_clock := 0.0
var won := false
var recycled := 0.0
var external_input := 0.0
var respiration_loss := 0.0
var kills := 0
var active_cells := 0
var active_particles := 0
var view_half := VIEW*0.5
var revision := 0
var profile_usec: Dictionary = {}
var profiling := false
var profile_counts: Dictionary = {}
var camera_position := Vector2(2048,1280)
var camera_follows_player := true
var chemistry_events := {"decay":0,"combine":0,"recycle":0,"detox":0,"spoil":0,"enzyme":0,"neutralize":0}


# Native ownership is explicit: fixture dictionaries are imported once, and
# thereafter empty. Snapshots are detached diagnostics, never an implicit getter.
# Diagnostic particle engines pin the simulation footprint at configuration.
# Display zoom remains presentation-only; switching engine resets no resources.
var particle_engine := "current"
var transport_parcels := false
var integration_half := Vector2.ZERO
var particle_pool := false
var last_spawn: Dictionary = {}
var emitted_particles := 0

func enable_particle_pool() -> bool:
	if resident != null: return false
	if particle_pool: return true
	if not _pool_supported(): return false
	kernels.pool_start(particles)
	particle_pool = true
	grid.pool = kernels
	particles = []
	pheromones = []
	grid.rebuild(particles)
	return true

func configure_particle_engine(engine: String, radius: float = 4.0, iterations: int = 1) -> bool:
	if engine not in ["current","uniform","liquidfun"] or kernels == null or not _pool_supported(): return false
	if not kernels.particle_engine_configure(engine,radius,iterations): return false
	particle_engine = engine
	if engine != "current" or transport_parcels:
		if integration_half == Vector2.ZERO: integration_half = view_half
	else: integration_half = Vector2.ZERO
	return enable_particle_pool()

func configure_parcels(enabled: bool) -> bool:
	if kernels == null or not _pool_supported(): return false
	transport_parcels = enabled
	kernels.parcel_configure(enabled)
	if enabled and integration_half == Vector2.ZERO: integration_half = view_half
	if not enabled and particle_engine == "current": integration_half = Vector2.ZERO
	return enable_particle_pool()

func disable_particle_pool() -> void:
	if not particle_pool: return
	particles = kernels.pool_stop()
	particle_pool = false
	grid.pool = null
	pheromones = particles.filter(func(p): return p.kind == PHEROMONE and p.alive)
	grid.rebuild(particles)

func _pool_supported() -> bool:
	return kernels != null and native_particle_pipeline and native_particles and native_transport_bookkeeping and native_chemistry_writes and native_chemical_timestamps and native_background_chemistry and native_feeding and native_exclusion and native_particle_compaction and native_render and grid.native != null and grid.native_enabled and grid.incremental and gpu_transport == null and (not habitat_geometry.enabled or habitat_geometry.particles_permeable)

func particle_count() -> int:
	if resident != null: return resident.alive
	return kernels.pool_size() if particle_pool else particles.size()

func pheromone_count() -> int:
	if resident != null: return resident.signals
	return int(kernels.pool_metrics().signal_slots) if particle_pool else pheromones.size()

func particle_snapshots() -> Array:
	if resident != null: return resident.snapshots()
	return kernels.pool_snapshots() if particle_pool else particles

func particle_snapshot(index: int) -> Dictionary:
	if resident != null: return resident.inspect_slot(index)
	return kernels.pool_snapshot(index) if particle_pool else particles[index]

func _commit_spawn_metadata() -> void:
	if particle_pool: kernels.pool_patch(particle_count()-1,last_spawn)

func _init(seed_number: int = 20261004, profile: int = 0, populate: bool = true) -> void:
	seed_value = seed_number
	rng.seed = seed_number
	background_rng.seed = seed_number ^ 0x51a7
	ecology_rng.seed = seed_number ^ 0x719ab
	evolution = Evolution.new(seed_number)
	if not populate: return
	habitat = clampi(profile,0,2)
	player.role = "player"
	player.biomass = 36
	player.update_geometry()
	player.membrane = Cell.Membrane.new(player.radius,absi(seed_value*1000003))
	player.add_organ("feeding",0,"graze",false)
	cells.append(player)
	# Whole habitats are stored. Only organisms inside the microscope advance.
	for i in 18:
		if habitat == 0 and i%5 == 3:
			pending_replacements.append({"role":"hunter","id":-1,"not_before":150.0+240.0*(i/5)})
			continue
		var p = player.position + Vector2.from_angle(i*2.4)* (1050+i*45 if i%5 == 3 else 220 if i == 0 else 340+i*94)
		_make_cell(Medium.wrap_position(p), "hunter" if i%5 == 3 else "grazer")
	habitat_geometry = Habitat.new(seed_number,cells)
	# Initial clouds are retained products of these cells' pre-observation life.
	# No environmental spawner runs after initialization.
	for cell in cells: _seed_cell_products(cell)
	grid.rebuild(particles)
	fluid.set_camera(player.position if camera_follows_player else camera_position,view_half)
	lineage.initialize(self)

func _make_cell(p: Vector2, role: String):
	var cell = Cell.new(next_id,p)
	next_id += 1
	cell.role = role
	cell.angle = rng.randf()*TAU
	cell.body = 135.0 if role == "hunter" else rng.randf_range(14,32)
	cell.biomass = 35 if role == "hunter" else 10
	cell.update_geometry()
	cell.membrane = Cell.Membrane.new(cell.radius,absi(seed_value*1000003+cell.id*9176))
	cell.add_organ("feeding",1.1 if role == "hunter" else 1.4,"graze",false)
	cell.add_organ("propulsion",PI,"graze",false)
	if role == "hunter":
		cell.add_organ("poreforming",0,"graze",false)
		cell.add_organ("hunting",0.48,"hunt",false)
		if habitat == 2:
			cell.add_organ("toxin",1.8,"graze",false)
			cell.biomass = 90
			cell.update_geometry()
			cell.membrane = Cell.Membrane.new(cell.radius,absi(seed_value*1000003+cell.id*9176))
			for a in [0.6,1.9,2.6,3.7,5.65]: cell.add_organ("protection",a,"graze",false)
			cell.add_organ("regenerative",4.4,"graze",false)
	else:
		cell.add_organ("photosynthesis",0,"graze",false)
	cell.update_geometry()
	cell.previous_angle = cell.angle
	if stagger_sensing: cell.sense_clock = (cell.id%9)/60.0
	cells.append(cell)
	return cell

func screen_position(p: Vector2) -> Vector2:
	return view_half+Medium.offset(camera_position if not camera_follows_player else player.position,p)

func activity_at(p: Vector2) -> float:
	if external_offscreen:return 0.0
	if resident != null and resident.full_detail: return 1.0
	if server_mode and not remote_client:
		var detail := 0.0
		for view in camera_views: detail = maxf(detail,Medium.visibility(p,Vector2(view.x,view.y),Vector2(view.z,view.w)))
		return detail
	return Medium.visibility(p,player.position if camera_follows_player else camera_position,view_half)

func activity_for_cell(cell) -> float:
	# Viewing an interior still observes its membrane/body at full fidelity.
	# Only the unrequested external particle domain goes to the cold path.
	if interoceptive_cells.has(cell.id):return 1.0
	if external_offscreen:return 0.0
	if resident != null and resident.full_detail: return 1.0
	# A visible membrane or appendage must not freeze when its center is outside.
	var half: Vector2 = view_half+Vector2.ONE*(cell.extent()+80)
	if server_mode and not remote_client:
		var detail := 0.0
		for view in camera_views: detail = maxf(detail,Medium.visibility(cell.position,Vector2(view.x,view.y),Vector2(view.z,view.w)+Vector2.ONE*(cell.extent()+80)))
		return detail
	return Medium.visibility(cell.position,player.position if camera_follows_player else camera_position,half)

func local_particle_ids(margin: float = 0.0) -> Array[int]:
	return visible_particle_ids(margin+Medium.ACTIVE_PAD+Medium.ACTIVE_FADE)

func visible_particle_ids(margin: float = 0.0) -> Array[int]:
	if resident != null: return [] # Rendering reads the resident texture directly.
	if grid.source_size != particle_count(): grid.rebuild(particles)
	if server_mode and not remote_client:
		var union: Dictionary = {}
		for view in camera_views:
			for index in grid.query_rect(Vector2(view.x,view.y),Vector2(view.z,view.w)+Vector2.ONE*margin): union[index] = true
		var result: Array[int] = []
		for index in union: result.append(index)
		result.sort()
		return result
	return grid.query_rect(player.position if camera_follows_player else camera_position,view_half+Vector2.ONE*margin)

func visible_particle_census() -> Dictionary:
	if resident != null:
		return resident.last_chemistry.get("visible",{"chemicals":0,"material":0,"signals":0})
	var center: Vector2 = player.position if camera_follows_player else camera_position
	var ids := visible_particle_ids()
	if kernels != null: return kernels.particle_census(particles,ids,center,view_half)
	var counts := {"chemicals":0,"material":0,"signals":0}
	for index in ids:
		var p: Dictionary = particles[index]
		var d: Vector2 = Medium.offset(center,p.p)
		if not p.alive or absf(d.x)>view_half.x or absf(d.y)>view_half.y: continue
		if p.kind==PHEROMONE: counts.signals+=1
		else: counts.chemicals+=1
		if Catalog.material(p.kind)>0: counts.material+=1
	return counts

func local_particle_kind(kind: int) -> Array[int]:
	if grid.source_size != particle_count(): grid.rebuild(particles)
	return grid.query_kind_rect(particles,player.position if camera_follows_player else camera_position,view_half+Vector2.ONE*(Medium.ACTIVE_PAD+Medium.ACTIVE_FADE),kind)

func install(kind: String, local_angle: float, mode: String = "graze", size: float = 1.0) -> bool:
	if kind=="photosynthesis":return false # Retired intracellular pathway.
	if remote_client: return edit("install",{"kind":kind,"angle":local_angle})
	var cost := Evolution.install_price(size)
	if evolution.terminal() or (evolution.enabled and evolution.points < cost): return false
	if not player.add_organ(kind,local_angle,mode,true,size): return false
	evolution.spend(cost,"Install "+kind)
	return true

func remove(index: int) -> bool:
	if remote_client: return edit("remove",{"id":player.organs[index].id}) if index>=0 and index<player.organs.size() else false
	var debris: float = player.recycle(index)
	if debris < 0: return false
	_build_debris(debris)
	return true

func spawn_particle(kind: int, p: Vector2, v: Vector2 = Vector2.ZERO, amount: float = 1.0, owner: int = -1, source_radius: float = 0.0) -> void:
	if amount <= 0: return
	emitted_particles += 1
	if resident == null and grid.source_size != particle_count(): grid.rebuild(particles)
	last_spawn = {"kind":kind,"p":Medium.wrap_position(p),"previous":Medium.wrap_position(p),"v":v,"amount":amount,"age":0.0,"alive":true,"owner":owner,"source_radius":source_radius,"angle":rng.randf()*TAU,"previous_angle":0.0,"spin":rng.randfn(0,0.8),"direction":Vector2.RIGHT,"capacity":amount}
	last_spawn.previous_angle = last_spawn.angle
	last_spawn.direction = Vector2.from_angle(last_spawn.angle)
	if kind == PHEROMONE:
		# Dissolved point tracers have no momentum, binding face or material budget.
		last_spawn.v = Vector2.ZERO
		last_spawn.angle = 0.0
		last_spawn.previous_angle = 0.0
		last_spawn.spin = 0.0
		last_spawn.direction = Vector2.ZERO
		last_spawn.expires_at = time-log(maxf(rng.randf(),0.000000001))/PHEROMONE_DECAY
		if not particle_pool and resident == null: pheromones.append(last_spawn)
	last_spawn.chemical_at = time
	last_spawn.transport_at = transport_clock
	if resident != null:
		resident.enqueue(last_spawn)
		return
	if particle_pool: kernels.pool_spawn(last_spawn)
	else:
		particles.append(last_spawn)
		if kernels != null: kernels.invalidate_particle_render(particle_count()-1)
	grid.insert(particle_count()-1,last_spawn.p)

func _emit_aimed(kind: int, at: Vector2, aim: Vector2, speed: float, quantity: float, identity: int) -> void:
	spawn_particle(kind,at,aim*speed,quantity,identity)
	last_spawn.angle = aim.angle()
	last_spawn.previous_angle = last_spawn.angle
	last_spawn.direction = aim
	_commit_spawn_metadata()

func _record_reaction(at: Vector2) -> void:
	if activity_at(at) <= 0: return
	var event := {"at":at,"time":time,"serial":reaction_serial}
	var slot := reaction_serial%REACTION_SPARK_LIMIT
	if reaction_sparks.size() < REACTION_SPARK_LIMIT: reaction_sparks.append(event)
	else: reaction_sparks[slot] = event
	reaction_serial += 1

func _record_sound(kind: String, at: Vector2, source: int, amount: float = 1.0) -> void:
	var key := kind+":"+str(source)
	if sound_recent.has(key) and time-sound_recent[key].time < 0.1:
		sound_recent[key].amount = minf(8,sound_recent[key].amount+amount)
		return
	sound_sequence += 1
	var event := {"sequence":sound_sequence,"kind":kind,"at":Medium.wrap_position(at),"source":source,"amount":amount,"time":time,"key":key}
	if sound_events.size() < SOUND_EVENT_LIMIT:
		sound_events.append(event)
	else:
		var slot := (sound_sequence-1)%SOUND_EVENT_LIMIT
		var old: Dictionary = sound_events[slot]
		if sound_recent.has(old.key) and sound_recent[old.key].sequence == old.sequence: sound_recent.erase(old.key)
		sound_events[slot] = event
	sound_recent[key] = event

func _emit_pheromone(cell, emitted_at: float = -1.0) -> Dictionary:
	if emitted_at < 0: emitted_at = time
	var direction := Vector2.from_angle(rng.randf()*TAU)
	var at: Vector2 = cell.position+cell.local_point(direction.angle()).rotated(cell.angle)
	spawn_particle(PHEROMONE,at,Vector2.ZERO,0.2,cell.id,cell.radius)
	var p: Dictionary = last_spawn
	var hostile := false
	var armored := false
	for organ in cell.organs:
		if organ.kind in ["poreforming","toxin"] and organ.hp > 0: hostile = true
		if organ.kind in ["protection","neutralizing"] and organ.hp > 0: armored = true
	# Value snapshots, never a Cell reference. Coordinates are deliberately old
	# once the source moves; size and hostile anatomy can only update via new cues.
	p.report = {"id":cell.id,"lineage":cell.lineage_id(),"at":cell.position,
		"mass":cell.organic_mass(),"radius":cell.radius,"hostile":hostile,"defended":hostile or armored,"emitted_at":emitted_at}
	p.expires_at -= maxf(0,time-emitted_at)
	p.transport_at = maxf(0,transport_clock-(time-emitted_at))
	if p.expires_at <= time: p.alive = false
	_commit_spawn_metadata()
	return p

func _pheromone_alive(p: Dictionary) -> bool:
	return p.alive and (p.kind != PHEROMONE or p.get("expires_at",0.0) > time)

func _expire_pheromones() -> void:
	if particle_pool:
		chemistry_events.decay += kernels.pool_expire(time)
		return
	# Only signal references are visited, including offscreen ones. Global-clock
	# expiry prevents dormant clouds from reviving obsolete reports.
	for p in pheromones:
		if p.alive and p.expires_at <= time:
			p.alive = false
			chemistry_events.decay += 1

func _emit_material(kind: int, at: Vector2, amount: float, motion: Vector2 = Vector2.ZERO, owner: int = 0) -> void:
	# Packet merging requires oriented contact, never an emission shortcut.
	var count := maxi(1,ceili(amount/float(Catalog.data().ecology.packet_quantum)))
	for i in count: spawn_particle(kind,at,motion,amount/count,owner)

func step(dt: float) -> void:
	if remote_client: return
	if resident != null:
		var shown_half:=view_half
		var shown_camera:=camera_position
		var shown_follow:=camera_follows_player
		# Fixed widest playable footprint prevents zoom from changing feeding.
		resident.display_scope=Vector4(player.position.x,player.position.y,shown_half.x,shown_half.y) if shown_follow else Vector4(shown_camera.x,shown_camera.y,shown_half.x,shown_half.y)
		view_half=resident.detail_half
		resident.step(dt)
		view_half=shown_half;camera_position=shown_camera;camera_follows_player=shown_follow
		return
	var display_half := view_half
	var display_camera := camera_position
	var display_follow := camera_follows_player
	if integration_half != Vector2.ZERO:
		view_half = integration_half
		camera_follows_player = true
	_step_simulation(dt)
	view_half = display_half
	camera_position = display_camera
	camera_follows_player = display_follow

func _step_simulation(dt: float) -> void:
	if not server_mode and (evolution.terminal() or build_original != null): return
	if not server_mode and player.dead and not evolution.enabled: return
	if profiling:
		profile_counts.clear()
		profile_usec["sensing"] = 0
		profile_usec["membrane"] = 0
		profile_usec["coarse_chemistry"] = 0
		profile_usec["coarse_feeding"] = 0
		profile_usec["coarse_motion"] = 0
		profile_usec["feeding"] = 0
		profile_usec["organ_geometry"] = 0
		profile_usec["traction"] = 0
	time += dt
	revision += 1
	_step_internal_chemistry(dt)
	if particle_pool and not _pool_supported(): disable_particle_pool()
	if grid.source_size != particle_count(): grid.rebuild(particles)
	var mark := Time.get_ticks_usec()
	if external_offscreen:fluid.set_views([])
	elif server_mode: fluid.set_views(camera_views)
	else: fluid.set_camera(player.position if camera_follows_player else camera_position,view_half)
	if experimental_fluid != null:
		fluid.velocity = experimental_fluid.step(fluid.velocity,cells,habitat_geometry,dt)
		if profiling:
			for key in ["pack_us","submit_wait_us","readback_apply_us"]:
				profile_usec["fluid_gpu."+key] = experimental_fluid.metrics.get(key,0)
		if revision%6 == 0:
			if native_fluid: acidity.values = kernels.acid_step(acidity.values,fluid.velocity,fluid.activity,dt*6)
			else: acidity.step(dt*6,fluid)
	elif native_fluid:
		fluid.velocity = kernels.fluid_step(fluid.velocity,fluid.activity,fluid.tide,dt,fluid.driven)
		if revision%6 == 0: acidity.values = kernels.acid_step(acidity.values,fluid.velocity,fluid.activity,dt*6)
	else:
		fluid.step(dt)
		if revision%6 == 0: acidity.step(dt*6,fluid)
	_step_background_fluid(dt)
	active_cells = 0
	for cell in cells:
		cell.previous_position = cell.position
		cell.previous_angle = cell.angle
		cell.activity = activity_for_cell(cell)
		if background_biology: cell.activity = 1.0 if cell.activity > 0 else 0.0
		if cell.activity > 0 and not cell.dead:
			active_cells += 1
			var local_dt: float = dt*cell.activity
			cell.age += local_dt
			cell.hurt_flash = maxf(0,cell.hurt_flash-local_dt*2)
			cell.reaction_flash = maxf(0,cell.reaction_flash-local_dt*2)
	_suction(dt)
	profile_usec["fluid"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	_expire_pheromones()
	packed_particle_frame = native_particle_pipeline and native_particles and native_transport_bookkeeping and native_chemistry_writes and native_chemical_timestamps and grid.native != null and grid.native_enabled and grid.incremental and gpu_transport == null and (not habitat_geometry.enabled or habitat_geometry.particles_permeable)
	var packed_render_tick := packed_particle_frame and native_feeding and native_exclusion and native_background_chemistry
	if packed_particle_frame: kernels.packet_begin(particles)
	_move_particles(dt)
	if profiling: profile_usec["transport"] = Time.get_ticks_usec()-mark
	var plant_mark := Time.get_ticks_usec() if profiling else 0
	habitat_geometry.move_particles(particles,foreground_particle_ids,revision,grid,native_particles)
	_settle_transport(foreground_particle_ids,false)
	if profiling: profile_usec["particle_plants"] = Time.get_ticks_usec()-plant_mark
	var chem_mark := Time.get_ticks_usec() if profiling else 0
	_chemistry(dt)
	if profiling: profile_usec["chemistry"] = Time.get_ticks_usec()-chem_mark
	var publish_mark := Time.get_ticks_usec() if profiling else 0
	if packed_particle_frame:
		kernels.packet_end()
		packed_particle_frame = false
	if profiling: profile_usec["particle_publish"] = Time.get_ticks_usec()-publish_mark
	profile_usec["particles"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	if background_biology: offscreen_ecology.step(self,dt)
	profile_usec["offscreen_biology"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		var local_dt: float = dt*cell.activity
		cell.animate_resources(local_dt)
		_clear_receptors(cell,local_dt)
		var sense_mark := Time.get_ticks_usec() if profiling else 0
		_sense(cell,local_dt)
		if profiling: profile_usec["sensing"] = profile_usec.get("sensing",0)+Time.get_ticks_usec()-sense_mark
		var feed_mark := Time.get_ticks_usec() if profiling else 0
		_feed(cell)
		if profiling: profile_usec["feeding"] = profile_usec.get("feeding",0)+Time.get_ticks_usec()-feed_mark
		_biology_after_feed(cell,local_dt)
	profile_usec["biology"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	_step_cell_motion(dt)
	profile_usec["motion"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	if spatial_queries: cell_index.rebuild(cells)
	_toxin_contacts()
	_receptor_contacts()
	var exclude_mark := Time.get_ticks_usec() if profiling else 0
	_exclude_particles()
	if profiling: profile_usec["exclusion"] = Time.get_ticks_usec()-exclude_mark
	for cell in cells.duplicate():
		if cell.activity > 0 and cell.health <= 0 and not cell.dead: _die(cell)
	spawn_clock += dt
	if spawn_clock >= 0.5:
		spawn_clock -= 0.5
		if not particle_pool: pheromones = pheromones.filter(func(p): return p.alive)
		_compact_particles()
		grid.rebuild(particles)
		_replace_population()
	_step_reproduction()
	profile_usec["ecology"] = Time.get_ticks_usec()-mark
	mark = Time.get_ticks_usec()
	if not server_mode and evolution.enabled and (player.dead or player.health <= 0):
		if not player.dead: _die(player)
		lineage.recover(self,dt)
	evolution.advance(dt,self)
	profile_usec["evolution"] = Time.get_ticks_usec()-mark
	won = evolution.status == "won"
	if packed_render_tick: kernels.particle_render_ready(particles,revision)

func _biology_after_feed(cell, local_dt: float) -> void:
	_acid_stress(cell,local_dt)
	_photosynthesize(cell,local_dt)
	_metabolize(cell,local_dt)
	cell.heal(local_dt)
	for leak in cell.leaks:
		var normal := Vector2.from_angle(cell.angle+leak.a)
		_emit_material(NUTRIENT,cell.position+cell.local_point(leak.a).rotated(cell.angle)+normal*12,leak.amount,normal*12,cell.id)
	cell.chemistry.excrete(self,cell,local_dt)
	var organ_mark := Time.get_ticks_usec() if profiling else 0
	cell.update_geometry()
	# Shrinkage can shed crowded organs, releasing their remaining material.
	while cell.occupied() > cell.perimeter() and not cell.organs.is_empty():
		var index: int = cell.organs.size()-1
		while index >= 0 and cell.inherent(cell.organs[index]): index -= 1
		if index < 0: break
		var organ: Dictionary = cell.organs[index]
		cell.organs.remove_at(index)
		cell.lost_organs.append(organ.duplicate(true))
		spawn_particle(WASTE,cell.organ_position(organ),Vector2.ZERO,organ.material,cell.id)
	if profiling: profile_usec["organ_geometry"] = profile_usec.get("organ_geometry",0)+Time.get_ticks_usec()-organ_mark
	var traction_mark := Time.get_ticks_usec() if profiling else 0
	var traction := PackedVector2Array()
	if native_traction:
		traction = kernels.fluid_traction(fluid.velocity,cell.membrane.points,cell.position,cell.angle,cell.velocity,cell.angular_velocity)
	else:
		for point in cell.membrane.points:
			var arm: Vector2 = point.rotated(cell.angle)
			traction.append((fluid.sample(cell.position+arm)-cell.velocity-Vector2(-arm.y,arm.x)*cell.angular_velocity).rotated(-cell.angle).limit_length(90))
	if profiling: profile_usec["traction"] = profile_usec.get("traction",0)+Time.get_ticks_usec()-traction_mark
	var membrane_mark := Time.get_ticks_usec() if profiling else 0
	cell.membrane.step(local_dt,cell.radius,cell.shape_acceleration.rotated(-cell.angle),cell.age+cell.id*1.7,1.0,traction)
	if profiling:
		profile_usec["membrane"] = profile_usec.get("membrane",0)+Time.get_ticks_usec()-membrane_mark
		profile_counts["membrane_updates"] = profile_counts.get("membrane_updates",0)+1
	cell.render_revision += 1
	_emit_and_attack(cell,local_dt)
	_fund_reproduction(cell,local_dt)

func _step_cell_motion(dt: float) -> void:
	# Short motion substeps plus swept contacts avoid crossing from one side to the other.
	var contacts_us := 0
	var before_motion: Dictionary = {}
	for cell in cells: before_motion[cell.id] = cell.velocity
	for cell in cells:
		cell.feeding_feedback = ""
		for organ in cell.organs:
			if organ.kind == "poreforming": organ.feeding = false
	for substep in 3:
		var starts: Dictionary = {}
		for cell in cells: starts[cell.id] = {"p":cell.position,"angle":cell.angle}
		_motion(dt/3.0)
		var contact_mark := Time.get_ticks_usec() if profiling else 0
		_contacts(dt/3.0)
		if profiling: contacts_us += Time.get_ticks_usec()-contact_mark
		for cell in cells:
			if cell.dead or cell.activity <= 0: continue
			habitat_geometry.move_cell(cell,cell.position,cell.position,dt/3.0)
	for cell in cells:
		cell.shape_acceleration = ((cell.velocity-before_motion[cell.id])/dt).limit_length(600)
	if profiling: profile_usec["contacts"] = contacts_us

func _step_background_fluid(dt: float) -> void:
	if not background_transport: return
	background_field_clock += dt
	if background_field_clock < 0.25: return
	# Complement the foreground field activity. Small, stable coarse field steps
	# relax old wakes and carry the maintained tide throughout the torus.
	var saved_activity: PackedFloat32Array = fluid.activity
	var saved_indices: PackedInt32Array = fluid.active_indices
	var far_activity := PackedFloat32Array()
	var far_indices := PackedInt32Array()
	far_activity.resize(saved_activity.size())
	for i in far_activity.size():
		far_activity[i] = 1.0-saved_activity[i]
		if far_activity[i] > 0: far_indices.append(i)
	while background_field_clock >= 0.25:
		background_field_clock -= 0.25
		if experimental_fluid != null:
			# Experimental GPU water already advances the full torus every tick.
			# Retain the ordinary coarse acidity clock without advancing water twice.
			if background_biology:
				if native_fluid: acidity.values = kernels.acid_step(acidity.values,fluid.velocity,far_activity,0.25)
				else:
					fluid.activity = far_activity
					fluid.active_indices = far_indices
					acidity.step(0.25,fluid)
		elif native_fluid:
			fluid.velocity = kernels.fluid_step(fluid.velocity,far_activity,fluid.tide,0.25,fluid.driven)
			if background_biology: acidity.values = kernels.acid_step(acidity.values,fluid.velocity,far_activity,0.25)
		else:
			fluid.activity = far_activity
			fluid.active_indices = far_indices
			fluid.step(0.25)
			if background_biology: acidity.step(0.25,fluid)
	fluid.activity = saved_activity
	fluid.active_indices = saved_indices

func _compact_particles() -> void:
	if particle_pool:
		background_cursor = kernels.pool_compact(background_cursor)
		return
	if native_particle_compaction:
		var result: Array = kernels.compact_particles(particles,background_cursor)
		particles = result[0]
		background_cursor = result[1]
		return
	# Retain the next survivor in the round-robin sweep when indices shift.
	var kept: Array = []
	var before_cursor := 0
	for i in particle_count():
		if not particles[i].alive: continue
		if i < background_cursor: before_cursor += 1
		kept.append(particles[i])
	particles = kept
	background_cursor = before_cursor%particle_count() if particle_count() > 0 else 0

func _background_ids(dt: float) -> Array[int]:
	var ids: Array[int] = []
	if not background_transport or particle_count() == 0: return ids
	background_credit += particle_count()*dt/maxf(background_period,dt)
	var visits := mini(particle_count(),floori(background_credit+0.0000001))
	background_credit -= visits
	background_cursor %= particle_count()
	if native_particles and native_transport_bookkeeping:
		ids = kernels.background_ids(particles,background_cursor,visits,player.position if camera_follows_player else camera_position,view_half,transport_clock)
		background_cursor = (background_cursor+visits)%particle_count()
		return ids
	for i in visits:
		var index := background_cursor
		background_cursor = (background_cursor+1)%particle_count()
		var p: Dictionary = particles[index]
		if p.alive and activity_at(p.p) <= 0 and p.get("transport_at",0.0) < transport_clock:
			ids.append(index)
	return ids

func _settle_transport(ids: Array[int], background: bool) -> void:
	if native_particles and native_transport_bookkeeping:
		kernels.settle_transport(particles,ids,background)
		return
	for index in ids:
		var p: Dictionary = particles[index]
		if background or p.get("transport_jump",false):
			p.previous = p.p
			p.previous_angle = p.angle
			if not background: p.transport_jump = false

func _transport_reference(ids: Array[int], dt: float, random: RandomNumberGenerator, background: bool) -> int:
	var count := 0
	for index in ids:
		var p: Dictionary = particles[index]
		if not p.alive or (activity_at(p.p) > 0) == background: continue
		var elapsed := maxf(0,transport_clock-float(p.get("transport_at",transport_clock-dt)))
		if elapsed <= 0: continue
		Transport.advance(p,fluid,elapsed,revision,random)
		p.transport_at = transport_clock
		grid.move(index,p.previous,p.p)
		count += 1
	return count

func _move_particles(dt: float) -> void:
	transport_clock += dt
	var camera: Vector2 = player.position if camera_follows_player else camera_position
	var ids := local_particle_ids(64)
	# Keep the starting IDs for swept contacts, even if catch-up leaves the halo.
	foreground_particle_ids = ids
	if gpu_transport != null:
		active_particles = gpu_transport.step(particles,ids,fluid.velocity,camera,view_half,dt,revision,rng,transport_clock)
	elif native_particles:
		active_particles = kernels.transport(particles,ids,fluid.velocity,camera,view_half,dt,revision,rng,transport_clock,false)
	else:
		active_particles = _transport_reference(ids,dt,rng,false)
	var mark := Time.get_ticks_usec()
	var far_ids := _background_ids(dt)
	if transport_parcels:
		var centers := PackedVector2Array()
		var radii := PackedFloat32Array()
		for cell in cells:
			if not cell.dead:
				centers.append(cell.position)
				radii.append(cell.extent())
		kernels.parcel_protect(centers,radii)
	if native_particles:
		background_particles = kernels.transport(particles,far_ids,fluid.velocity,camera,view_half,dt,revision,background_rng,transport_clock,true)
	else:
		background_particles = _transport_reference(far_ids,dt,background_rng,true)
	# Colonies are permeable to packets in both transport tiers. The retained
	# historical solid-packet path is benchmark-only, never the game default.
	habitat_geometry.move_particles(particles,far_ids,revision,grid,native_particles)
	_settle_transport(far_ids,true)
	profile_usec["background_transport"] = Time.get_ticks_usec()-mark
	var grid_mark := Time.get_ticks_usec() if profiling else 0
	if native_particles or gpu_transport != null:
		if packed_particle_frame:
			var positions: PackedVector2Array = kernels.packet_positions()
			grid.native.update_positions(positions,ids)
			grid.native.update_positions(positions,far_ids)
		elif grid.incremental:
			grid.update(particles,ids)
			grid.update(particles,far_ids)
		else: grid.rebuild(particles)
	if profiling: profile_usec["transport_grid"] = Time.get_ticks_usec()-grid_mark

func _chemistry(dt: float, patch: Array[int] = [], background: bool = false) -> void:
	if native_particles and (not background or native_background_chemistry):
		var result: Dictionary = kernels.chemistry(particles,patch if background else local_particle_ids(),acidity.values,player.position if camera_follows_player else camera_position,view_half,dt,revision,rng,time if native_chemical_timestamps and (background_biology or background) else -1.0,background,native_chemistry_writes,particle_collisions,native_chemistry_bounds,native_chemistry_lazy_acid)
		acidity.values = result.acid
		respiration_loss += result.loss
		recycled += result.recycled
		for kind in result.events: chemistry_events[kind] += result.events[kind]
		for cue in result.get("neutralizations",[]): _record_sound("neutralize",cue.at,cue.source,cue.amount)
		for point in result.get("reaction_points",PackedVector2Array()): _record_reaction(point)
		if background_biology and not background and not native_chemical_timestamps:
			for index in local_particle_ids(): particles[index].chemical_at = time
		return
	# Unimolecular decay is stochastic. Pair reactions are deterministic contact
	# rules: both binding patches must face their partner within 60 degrees.
	var local_ids := patch if background else local_particle_ids()
	var spark_count := 0
	reaction_grid.clear()
	for index in local_ids:
		var p: Dictionary = particles[index]
		p.reaction_activity = (1.0 if background else activity_at(p.p)) if p.alive else 0.0
		p.contact_radius = particle_radius(p.kind)*particle_scale(p.amount)
		if p.reaction_activity > 0 and p.kind != PHEROMONE: reaction_grid.insert(index,p.p)
	for index in local_ids:
		var p: Dictionary = particles[index]
		if not p.alive or p.kind == PHEROMONE: continue
		var local_dt: float = maxf(0,time-p.get("chemical_at",time)) if background else dt*p.reaction_activity
		p.chemical_at = time
		if local_dt <= 0: continue
		if p.kind in [ACID,BUFFER]:
			var sign_value := 1.0 if p.kind == ACID else -1.0
			var used := absf(acidity.exchange(p.p,sign_value*minf(p.capacity,local_dt*0.2)))
			p.capacity -= used
			if p.capacity <= 0.000001: p.kind = WASTE
		if chance(Catalog.decay(p.kind),local_dt):
			respiration_loss += p.amount*Catalog.material(p.kind)
			p.alive = false
			chemistry_events.decay += 1
			continue
		if p.get("reacted",-1) == revision: continue
		for other_index in reaction_grid.query(p.p,18):
			if other_index <= index: continue
			var other: Dictionary = particles[other_index]
			if not other.alive or other.kind == PHEROMONE or other.get("reacted",-1) == revision: continue
			var delta := Medium.offset(p.p,other.p)
			var contact: float = p.contact_radius+other.contact_radius
			if delta.length_squared() > contact*contact: continue
			var normal := delta.normalized() if delta.length_squared() > 0.000001 else Vector2.RIGHT
			var acid := acidity.sample(p.p)
			var alignment := binding_threshold(p.kind,other.kind,acid)
			if p.direction.dot(normal) >= alignment and other.direction.dot(-normal) >= alignment and _react_pair(p,other,acid):
				if spark_count < 64:
					_record_reaction(Medium.wrap_position(p.p+delta*0.5))
					spark_count += 1
				p.reacted = revision
				other.reacted = revision
				break
			# Optional comparison: point-centered chemical particles can overlap.
			if particle_collisions:
				var push := normal*(contact-delta.length())*0.25
				p.v -= push*8
				other.v += push*8

static func particle_radius(kind: int) -> float:
	return Catalog.radius(kind)

static func particle_scale(amount: float) -> float:
	return clampf(sqrt(amount/0.3),0.8,1.7)

static func binding_threshold(a: int, b: int, acid: float) -> float:
	if ENZYME in [a,b] and WASTE in [a,b]:
		# A modeled acid hydrolase has an acidic optimum. This is an affinity
		# abstraction, not a claim that pH literally widens a molecular patch.
		return 0.5+0.46*pow(clampf(absf(acid-0.4)/0.4,0,1),2)
	return 0.5

func _acid_stress(cell, dt: float) -> void:
	var exposure := acidity.sample(cell.position)
	var demand: float = maxf(0,exposure-0.15)*dt*5*cell.growth_scale()
	var spent: float = cell.spend_energy(demand,{},"acid stress")
	var overload := maxf(0,exposure-0.5)*0.8+(demand-spent)*0.15/maxf(dt,0.00001)
	cell.acid_stress = clampf(cell.acid_stress+(overload-0.12)*dt,0,1)
	if cell.acid_stress > 0.6:
		cell.health = maxf(0,cell.health-dt*(cell.acid_stress-0.6)*8)
		cell.death_hint = "Acid stress overwhelmed the membrane"

func _react_pair(a: Dictionary, b: Dictionary, acid: float = 0.0) -> bool:
	if b.kind == ENZYME and a.kind == WASTE: return _react_pair(b,a,acid)
	if a.kind == ENZYME and b.kind == WASTE and acid < 0.9:
		b.kind = NUTRIENT
		b.capacity = 0.0 # Salvaged carbon has no restored fuel potential.
		recycled += b.amount
		chemistry_events.enzyme += 1
		return true
	if b.kind == ANTITOXIN and a.kind in [TOXIN,TAG,PORE_SUBUNIT]: return _react_pair(b,a,acid)
	if a.kind == ANTITOXIN and b.kind in [TOXIN,TAG,PORE_SUBUNIT]:
		_record_sound("neutralize",a.p,a.owner,b.amount)
		a.kind = WASTE
		a.amount += b.amount
		b.alive = false
		chemistry_events.neutralize += 1
		return true
	if a.kind in [ACID,BUFFER] and b.kind in [ACID,BUFFER] and a.kind != b.kind:
		var neutralized: float = minf(a.capacity,b.capacity)
		a.capacity -= neutralized
		b.capacity -= neutralized
		if a.capacity <= 0.000001: a.kind = WASTE
		if b.capacity <= 0.000001: b.kind = WASTE
		return true
	if a.kind == OXYGEN and b.kind in [WASTE,TOXIN]: return _react_pair(b,a,acid)
	if a.kind == WASTE and b.kind == OXYGEN and b.amount >= a.amount*0.15 and acid < 0.8:
		var amount: float = a.amount
		a.kind = NUTRIENT
		a.capacity = 0.0
		a.amount = amount*0.6
		b.kind = CARBON
		b.amount = amount*0.4
		recycled += amount*0.6
		chemistry_events.recycle += 1
		return true
	if a.kind == TOXIN and b.kind == NUTRIENT: return _react_pair(b,a,acid)
	if a.kind == NUTRIENT and b.kind == TOXIN:
		a.kind = WASTE
		chemistry_events.spoil += 1
		return true
	if a.kind == b.kind and a.kind in [NUTRIENT,WASTE,CARBON,OXYGEN] and a.amount+b.amount <= float(Catalog.data().ecology.merge_limit):
		if a.kind == TOXIN and a.owner != b.owner: return false
		var total: float = a.amount+b.amount
		if total <= 0: return false
		# Normalize weights before float-vector arithmetic: tiny photosynthetic
		# remainders can be below float32 range while their ratio is well-defined.
		a.v = a.v.lerp(b.v,b.amount/total)
		a.amount += b.amount
		a.capacity = float(a.get("capacity",0))+float(b.get("capacity",0))
		b.alive = false
		chemistry_events.combine += 1
		return true
	return false

func _event_count(rate: float, dt: float) -> int:
	if not coarse_mode: return 1 if chance(rate,dt) else 0
	# Match the expected count of the existing 60 Hz Bernoulli process.
	return Offscreen.event_count(rng,60.0*(1.0-exp(-maxf(0,rate)/60.0))*dt)

func chance(rate: float, dt: float) -> bool:
	return rng.randf() < 1.0-exp(-maxf(0,rate)*maxf(0,dt))

func light_at(at: Vector2) -> float:
	var p := Medium.wrap_position(at)
	var field := 0.5+0.28*sin(TAU*p.x/WORLD.x*3+0.4)+0.22*cos(TAU*p.y/WORLD.y*3-0.8)
	return clampf(field*(0.5 if habitat == 1 else 1.25 if habitat == 2 else 1.0)*evolution.light_factor,0.02,1.0)

func light_direction(at: Vector2) -> Vector2:
	var p := Medium.wrap_position(at)
	return Vector2(0.28*TAU*3/WORLD.x*cos(TAU*p.x/WORLD.x*3+0.4),-0.22*TAU*3/WORLD.y*sin(TAU*p.y/WORLD.y*3-0.8)).normalized()

func _photosynthesize(cell, dt: float) -> void:
	cell.chemistry.light_flux = 0.0
	for organ in cell.organs:
		if organ.kind == "photosynthesis" and organ.hp > 0:
			cell.chemistry.photosynthesize(self,cell,organ,dt)

func _seed_cell_products(cell) -> void:
	var reference := OS.get_environment("PRIMORDIA_ECOLOGY") == "reference"
	var multiplier := 1 if reference else int(Catalog.data().ecology.seed_packets)
	var parcel_scale := 1.0 if reference else float(Catalog.data().ecology.get("parcel_scale",1))
	var food_count := (55 if habitat != 1 else 14)*multiplier
	# Explicit pre-observation cell-derived inputs. No habitat spawner follows.
	for i in (food_count+180*multiplier):
		var kind := NUTRIENT if i < food_count else CARBON if i < food_count+60*multiplier else OXYGEN
		var amount: float = (0.3 if kind != CARBON else 0.4)*parcel_scale
		var at: Vector2 = cell.position+Vector2.from_angle(rng.randf()*TAU)*(cell.radius+12+rng.randf()*160)
		spawn_particle(kind,at,Vector2.ZERO,amount,cell.id)

func _suction(dt: float) -> void:
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		_suction_cell(cell,dt*cell.activity)

func _suction_cell(cell, dt: float) -> void:
	for organ in cell.organs:
		if organ.kind not in ["feeding","cilia"] or organ.hp <= 0 or cell.energy <= 0: continue
		var ciliary: bool = organ.kind == "cilia"
		var cost: float = dt*(Cell.CILIA_PUMP if ciliary else Cell.PUMP_UPKEEP)*organ.scale*organ.scale
		var health: float = organ.hp/organ.max_hp
		var power: float = (Cell.CILIA_FLOW if ciliary else Cell.ORAL_FLOW)*organ.scale*health*Genes.factor(organ,"suction")
		var paid: float = cell.spend_energy(cost,organ,"pumping")
		power *= minf(1,paid/maxf(0.000001,cost))
		var at: Vector2 = cell.organ_position(organ)+cell.organ_normal(organ).rotated(cell.angle)*8 if ciliary else cell.pore_center(organ)
		fluid.suction(cell,at,(Cell.CILIA_REACH if ciliary else Cell.ORAL_REACH)*sqrt(organ.scale),power,dt,cell.target if ciliary else Vector2.ZERO)

func _steering_weight(organ: Dictionary, mode: String) -> float:
	# Explicit flight is a safety drive, independent of feeding/hunting tuning.
	return 1.0 if mode == "flee" else Cell.steering_strength(organ)

func _signal_alive(cell, packet: Dictionary) -> bool:
	var organ: Dictionary = cell.organ_by_id(packet.organ_id)
	return not organ.is_empty() and organ.hp > 0 and packet.get("expires_at",INF) > time and (packet.mode not in ["hunt","flee"] or packet.get("lineage",-1) != cell.lineage_id()) and _steering_weight(organ,packet.mode) > 0

func _candidate_score(cell, score: float, organ_id: int, mode: String, identity: int) -> float:
	var incumbent: bool = cell.target_memory > 0 and organ_id == cell.target_organ_id and mode == cell.target_mode and identity == cell.target_id
	return score*(1.2 if incumbent else 1.0)

func _accept_signal(cell, packet: Dictionary) -> bool:
	if cell.target_memory <= 0: return true
	if packet.mode == "flee" and cell.target_mode != "flee": return true
	if packet.mode != "flee" and cell.target_mode == "flee": return false
	var same: bool = packet.organ_id == cell.target_organ_id and packet.id == cell.target_id and packet.mode == cell.target_mode
	if same: return packet.sample_at >= cell.target_sample_at
	var incoming: Dictionary = cell.organ_by_id(packet.organ_id)
	var held: Dictionary = cell.organ_by_id(cell.target_organ_id)
	# Select a coherent direction/organ rather than cancelling opposing vectors.
	# A different drive needs a 20% lead; memory and pheromone expiry stay bounded.
	return packet.score*_steering_weight(incoming,packet.mode) > cell.target_score*_steering_weight(held,cell.target_mode)*1.2

func _food_patch(bins: Dictionary, reach: float, cell) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for key in bins:
		var total := 0.0
		var center := Vector2.ZERO
		var nearest := Vector2.ZERO
		var nearest_distance := INF
		for x in range(-1,2):
			for y in range(-1,2):
				var neighbor: Dictionary = bins.get(key+Vector2i(x,y),{})
				if neighbor.is_empty(): continue
				total += neighbor.mass
				center += neighbor.moment
				if neighbor.distance < nearest_distance:
					nearest_distance = neighbor.distance
					nearest = neighbor.nearest
		if total <= 0: continue
		center /= total
		# Mild travel cost: mass wins over a nearby isolated speck.
		var score: float = total/(1.0+center.length()/reach)
		if score > best_score:
			best_score = score
			var inner: float = maxf(70,cell.extent()+22)
			best = {"at":cell.position+(nearest if center.length() <= inner else center),
				"mass":total,"inner":center.length() <= inner}
	return best

func _sense(cell, dt: float, received_by_organ: Dictionary = {}) -> void:
	# Explicit diagnostic injection of completed local receptor results. Missing
	# organs still query the authoritative CPU pool; ordinary calls are unchanged.
	# A memory or in-flight signal cannot outlive its source organ.
	cell.signals = cell.signals.filter(func(packet): return _signal_alive(cell,packet))
	var held_organ: Dictionary = cell.organ_by_id(cell.target_organ_id)
	if held_organ.is_empty() or held_organ.get("hp",0) <= 0 or cell.target_expires_at <= time or _steering_weight(held_organ,cell.target_mode) <= 0 or (cell.target_mode in ["hunt","flee"] and cell.target_lineage == cell.lineage_id()): cell.target_memory = 0
	cell.sense_clock -= dt
	cell.target_memory = maxf(0,cell.target_memory-dt)
	if cell.sense_clock <= 0:
		cell.sense_clock = 0.15
		cell.sensed = false
		var best: Dictionary = {}
		var best_score := -1.0
		for organ in cell.organs:
			if organ.kind not in ["feeding","sensing","hunting","photosynthesis"] or organ.hp <= 0: continue
			var mode: String = "hunt" if organ.kind == "hunting" else "light" if organ.kind == "photosynthesis" else organ.mode
			var strength: float = _steering_weight(organ,mode)
			if strength <= 0: continue
			var reach: float = (120.0 if mode == "hunt" else 90.0 if mode == "flee" else 310.0)*sqrt(organ.scale)*(1-organ.blocked*0.65)*Genes.factor(organ,"sense")
			var receptor: Vector2 = cell.organ_position(organ)
			if mode == "light":
				var direction := light_direction(receptor)
				var light_score: float = _candidate_score(cell,0.7*strength,organ.id,"light",-1)
				if best_score < light_score and direction.length_squared() > 0.01 and light_at(receptor) < 0.98:
					best_score = light_score
					best = {"score":0.7,"mode":"light","id":-1,"at":cell.position+direction*150,"a":organ.a,"organ_id":organ.id}
				continue
			var food_bins: Dictionary = {}
			var reports: Dictionary = {}
			var candidates: Array = [] if received_by_organ.has(organ.id) else grid.query_kind(particles,receptor,reach,NUTRIENT if mode == "graze" else PHEROMONE)
			if profiling:
				profile_counts["receptor_queries"] = profile_counts.get("receptor_queries",0)+1
				profile_counts["receptor_candidates"] = profile_counts.get("receptor_candidates",0)+candidates.size()
				if mode in ["hunt","flee"]: profile_counts["pheromone_queries"] = profile_counts.get("pheromone_queries",0)+1
			if received_by_organ.has(organ.id):
				food_bins = received_by_organ[organ.id].food
				reports = received_by_organ[organ.id].reports
			elif particle_pool:
				var received: Dictionary = kernels.pool_sense(candidates,receptor,reach,cell.position,cell.id,cell.lineage_id(),time,mode == "graze")
				food_bins = received.food
				reports = received.reports
			else:
				for index in candidates:
					var p: Dictionary = particles[index]
					if not p.alive or p.owner == cell.id: continue
					var distance: float = Medium.offset(receptor,p.p).length()
					if distance > reach: continue
					if mode == "graze" and p.kind == NUTRIENT:
						if p.amount <= 0: continue
						var delta: Vector2 = Medium.offset(cell.position,p.p)
						var key := Vector2i((delta/maxf(80,reach/4.0)).floor())
						if not food_bins.has(key): food_bins[key] = {"mass":0.0,"moment":Vector2.ZERO,"nearest":delta,"distance":distance}
						var bin: Dictionary = food_bins[key]
						bin.mass += p.amount
						bin.moment += delta*p.amount
						if distance < bin.distance:
							bin.nearest = delta
							bin.distance = distance
					elif p.kind == PHEROMONE and mode in ["hunt","flee"] and _pheromone_alive(p):
						var report: Dictionary = p.get("report",{})
						if report.is_empty() or report.lineage == cell.lineage_id(): continue
						# The newest locally received report from a source supersedes an
						# older one, including a report that it is now too big to attack.
						if reports.has(report.id) and reports[report.id].report.emitted_at >= report.emitted_at: continue
						reports[report.id] = {"report":report,"distance":distance,"expires_at":p.expires_at}
			for detected in reports.values():
				var report: Dictionary = detected.report
				if mode == "hunt" and report.mass >= cell.organic_mass() and report.get("defended",true): continue
				if mode == "flee" and not report.hostile and report.mass <= cell.organic_mass(): continue
				var age: float = maxf(0,time-report.emitted_at)
				var score: float = (100.0 if mode == "flee" else 2.0)+1.0/(1+age)+0.1/(1+detected.distance)
				if mode == "flee" and report.hostile: score += 1.0
				if report.id == cell.target_id: score += 0.05
				var weighted: float = _candidate_score(cell,score*strength,organ.id,mode,report.id)
				if weighted > best_score:
					best_score = weighted
					best = {"lineage":report.lineage,"score":score,"mode":mode,"id":report.id,"at":report.at,"a":organ.a,"organ_id":organ.id,"expires_at":detected.expires_at}
			var patch: Dictionary = received_by_organ[organ.id].get("patch",{}) if received_by_organ.has(organ.id) else _food_patch(food_bins,reach,cell)
			var food_score: float = _candidate_score(cell,strength,organ.id,"graze",-1)
			if not patch.is_empty() and best_score < food_score:
				best_score = food_score
				best = {"score":1.0,"mode":"graze","id":-1,"at":patch.at,"a":organ.a,"organ_id":organ.id}
		if not best.is_empty():
			cell.sensed = true
			cell.signals.append({"lineage":best.get("lineage",-1),"score":best.score,"sample_at":time,"p":cell.local_point(best.a)*0.75,"mode":best.mode,"id":best.id,"at":best.at,"fear":best.mode == "flee","organ_id":best.organ_id,"expires_at":best.get("expires_at",INF)})
	for packet in cell.signals:
		packet.p = packet.p.move_toward(Vector2.ZERO,dt*(220+cell.radius*2))
		if packet.p.length() < 5 and _accept_signal(cell,packet):
			cell.target_score = packet.score
			cell.target_sample_at = packet.sample_at
			cell.target_id = packet.id
			cell.target_lineage = packet.lineage
			cell.target_position = packet.at
			cell.target_mode = packet.mode
			cell.target_organ_id = packet.organ_id
			cell.target_expires_at = packet.expires_at
			cell.target_memory = minf(1.2,packet.expires_at-time)
	cell.signals = cell.signals.filter(func(packet): return packet.p.length() >= 5)
	var organ: Dictionary = cell.organ_by_id(cell.target_organ_id)
	var share: float = cell.response_share(organ) if not organ.is_empty() else 0.0
	var phase: float = fposmod(cell.age+cell.id*0.61803398875,cell.response_cycle)/cell.response_cycle
	cell.drive_active = cell.target_memory > 0 and (cell.target_mode == "flee" or phase < share)
	if cell.drive_active:
		cell.facing = Medium.offset(cell.position,cell.target_position).normalized()
		cell.target = -cell.facing if cell.target_mode == "flee" else cell.facing
		cell.threat = cell.facing if cell.target_id >= 0 else Vector2.ZERO
		cell.state = {"graze":"FORAGING","hunt":"FOLLOWING PREY PHEROMONE","light":"SEEKING LIGHT","flee":"FLEEING"}.get(cell.target_mode,"EXPLORING")
		cell.target_mouth = cell.organ_normal(organ).angle() if not organ.is_empty() else 0.0
	else:
		# A seeded wandering heading, independent of current body rotation and RNG.
		var turn: float = floor(cell.age/cell.response_cycle)
		var wander_hash: int = posmod((int(turn)+1)*73856093 ^ cell.id*19349663 ^ seed_value*83492791,65521)
		cell.target = Vector2.from_angle(TAU*wander_hash/65521.0+sin(cell.age*0.4+cell.id)*0.3)
		cell.facing = cell.target
		cell.threat = Vector2.ZERO
		if cell.target_memory <= 0: cell.target_id = -1
		cell.target_mouth = 0
		cell.state = "EXPLORING · RESPONSE CYCLE" if cell.target_memory > 0 else "EXPLORING"
	if cell.count("propulsion")+cell.count("cilia") == 0: cell.state = "DRIFTING · PORE PUMPING"

func _feed(cell) -> void:
	var before: float = cell.eaten
	if native_feeding:
		var camera: Vector2 = player.position if camera_follows_player else camera_position
		for organ in cell.organs:
			if organ.kind == "feeding":
				kernels.feed(particles,grid.query(cell.pore_center(organ),cell.pore_radius(organ)+8),cell,organ,camera,view_half)
		kernels.feed(particles,grid.query(cell.position,cell.extent()+12),cell,{},camera,view_half)
		if cell.eaten > before: _record_sound("feeding",cell.position,cell.id,cell.eaten-before)
		return
	for organ in cell.organs:
		if organ.kind != "feeding": continue
		var mouth: Vector2 = cell.pore_center(organ)
		var reach: float = cell.pore_radius(organ)+8
		for index in grid.query(mouth,reach):
			var p: Dictionary = particles[index]
			if not p.alive or p.kind != NUTRIENT or activity_at(p.p) <= 0: continue
			if Medium.offset(mouth,p.p).length() <= reach:
				var amount = minf(p.amount,maxf(0,cell.gut_capacity()-cell.substrate))
				p.amount -= amount
				if kernels != null: kernels.invalidate_particle_render(index)
				var fuel: float = minf(p.get("capacity",p.amount+amount),p.amount+amount)*amount/maxf(0.000001,p.amount+amount)
				cell.receive_particle(NUTRIENT,amount,fuel,p.p)
				p.capacity = maxf(0,p.get("capacity",p.amount+amount)-fuel)
				cell.eaten += amount
				if p.owner != cell.id: cell.foreign_intake += amount
				if amount > 0: cell.consumed(organ,amount)
				if p.amount <= 0.000001: p.alive = false
	for index in grid.query(cell.position,cell.extent()+12):
		var p: Dictionary = particles[index]
		if p.alive and p.kind == CARBON and cell.count("photosynthesis") > 0 and activity_at(p.p) > 0 and Medium.offset(cell.position,p.p).length() < cell.extent()+18:
			var carbon_taken: float = minf(p.amount,maxf(0,float(Catalog.data().ecology.carbon_capacity)*cell.growth_scale()-cell.carbon))
			cell.receive_particle(CARBON,carbon_taken,carbon_taken,p.p)
			if p.owner != cell.id: cell.foreign_intake += carbon_taken
			p.amount -= carbon_taken
			if kernels != null: kernels.invalidate_particle_render(index)
			if p.amount <= 0.000001: p.alive = false
		if p.alive and p.kind == OXYGEN and activity_at(p.p) > 0 and Medium.offset(cell.position,p.p).length() < cell.support(Medium.offset(cell.position,p.p).angle())+14:
			var amount = minf(p.amount,maxf(0,cell.oxygen_capacity()-cell.oxygen))
			cell.receive_particle(OXYGEN,amount,amount,p.p)
			p.amount -= amount
			if kernels != null: kernels.invalidate_particle_render(index)
			if p.amount <= 0.000001: p.alive = false

	if cell.eaten > before: _record_sound("feeding",cell.position,cell.id,cell.eaten-before)

func enable_perception_domains() -> void:
	if perception_modes_enabled:return
	# Legacy chemistry advanced inside due body updates. Preserve its unresolved
	# body interval exactly once when the independent clock takes ownership.
	for cell in cells:
		if not cell.dead:cell.chemistry.pending_time+=cell.coarse_elapsed
	perception_modes_enabled=true

func _step_internal_chemistry(dt: float) -> void:
	if not perception_modes_enabled:return
	for cell in cells:
		if cell.dead:continue
		var chemistry=cell.chemistry
		var period: float=maxf(.001,offscreen_ecology.period)
		var phase: float=period*(.25+fposmod(cell.id*.61803398875,.75))
		if chemistry.coarse_due<0:chemistry.coarse_due=maxf(0,phase-chemistry.pending_time)
		chemistry.pending_time+=dt;chemistry.coarse_due-=dt
		var detailed: bool=interoceptive_cells.has(cell.id)
		if resident!=null:
			if detailed and chemistry.accelerator==null:
				if not resident.gpu.attach_cytoplasm(chemistry,cell):return
			elif not detailed:chemistry.ensure_cpu()
		if not detailed and chemistry.coarse_due>.0000001:continue
		var elapsed: float=chemistry.pending_time;chemistry.pending_time=0
		chemistry.advance(cell,elapsed,0.15+acidity.sample(cell.position)*0.1)
		chemistry.simulated_time+=elapsed
		if detailed:
			chemistry.fine_updates+=1;chemistry.coarse_due=phase
		else:
			chemistry.coarse_updates+=1;chemistry.coarse_due=period-fposmod(-chemistry.coarse_due,period)

func _metabolize(cell, dt: float) -> void:
	cell.reserve_activity = maxf(0,cell.reserve_activity-dt)
	if not perception_modes_enabled:cell.chemistry.advance(cell,dt,0.15+acidity.sample(cell.position)*0.1)
	cell.Surface.advance(cell,dt,self)
	cell.decay_energy(dt)
	cell.spend_energy(dt*Cell.BASAL_UPKEEP*cell.growth_scale())
	for organ in cell.organs: cell.spend_energy(dt*organ.scale*organ.scale*Genes.factor(organ,"upkeep",0.0),organ)
	if cell.energy <= 0:
		cell.health = maxf(0,cell.health-dt*2)
		cell.death_hint = "ATP exhaustion; feeding and repair could not sustain this body"

func _secretion_needed(cell, organ: Dictionary, kind: int) -> bool:
	if kind == BUFFER: return acidity.sample(cell.organ_position(organ)) > 0.02 or cell.acid_stress > 0.03
	if kind not in [ENZYME,ANTITOXIN]: return true
	if resident != null: return resident.needed.get(Vector2i(cell.id,organ.id),false)
	var wanted := WASTE if kind == ENZYME else TOXIN
	var at: Vector2 = cell.organ_position(organ)
	var reach: float = 140*sqrt(organ.scale)
	if particle_pool:
		return kernels.pool_needed(grid.query(at,reach),at,reach,wanted,coarse_mode,cell.lineage_id(),inherited_lineages,player.position if camera_follows_player else camera_position,view_half)
	for index in grid.query(at,reach):
		var packet: Dictionary = particles[index]
		if not packet.alive or (packet.kind not in [TOXIN,TAG,PORE_SUBUNIT] if wanted==TOXIN else packet.kind != wanted) or (not coarse_mode and activity_at(packet.p) <= 0): continue
		if wanted == TOXIN and inherited_lineages.get(packet.owner,packet.owner) == cell.lineage_id(): continue
		if Medium.offset(at,packet.p).length_squared() <= reach*reach: return true
	return false

func _emit_and_attack(cell, dt: float) -> void:
	# Every living active creature signals, independently of energy or anatomy.
	cell.emission_clock -= dt
	while cell.emission_clock <= 0:
		cell.emission_clock += 1.0/PHEROMONE_RATE
		_emit_pheromone(cell,maxf(0,coarse_event_at+cell.emission_clock-1.0/PHEROMONE_RATE) if coarse_mode else time)
	for organ in cell.organs:
		var kind: int = {"feeding":ENZYME,"neutralizing":ANTITOXIN,"acidifying":ACID,"regenerative":BUFFER}.get(organ.kind,-1)
		var energy_cost := Cell.SECRETION_COST*Genes.factor(organ,"secretion_cost")
		if kind < 0 or cell.biomass < 0.06 or cell.energy < energy_cost: continue
		if kind != ENZYME and cell.energy < 12: continue
		var rate := 0.35 if kind == ENZYME else 2.0
		for event in _event_count(rate*organ.scale*organ.scale*Genes.factor(organ,"secretion"),dt):
			if cell.biomass < 0.06 or cell.available_energy(organ)+0.0000001 < energy_cost: break
			# Query only on a scheduled secretion attempt, rather than every tick.
			if not _secretion_needed(cell,organ,kind): continue
			cell.biomass -= 0.06
			cell.spend_energy(energy_cost,organ,"secretion")
			var direction: Vector2 = cell.organ_normal(organ).rotated(cell.angle)
			spawn_particle(kind,cell.organ_position(organ)+direction*10,direction*18*Genes.factor(organ,"dispersal"),0.06,cell.id)
			last_spawn.capacity = 0.25 if kind in [ACID,BUFFER] else 0.06
			_commit_spawn_metadata()
			organ.charge_flash = 1
			if cell == player and kind == ACID: evolution.record("acid",0.06)
	# Cellular stress also releases a material-bearing toxic byproduct.
	if cell.health < 90 and cell.biomass > 0.08:
		for event in _event_count(0.6,dt):
			if cell.biomass <= 0.08: break
			cell.biomass -= 0.08
			var direction := Vector2.from_angle(rng.randf()*TAU)
			spawn_particle(TOXIN,cell.position+direction*(cell.radius+12),direction*24,0.08,cell.id)

	for organ in cell.organs:
		if organ.kind not in ["toxin","poreforming"]: continue
		organ["burst_clock"] = maxf(0,float(organ.get("burst_clock",0))-dt)
		var aim: Vector2 = cell.threat if cell.target_mode == "flee" else Medium.offset(cell.position,cell.target_position).normalized()
		if organ.burst_clock > 0 or cell.target_id < 0 or cell.target_memory <= 0 or aim.length_squared() < 0.01: continue
		var burst: float = organ.scale*organ.scale*Genes.factor(organ,"burst")
		if cell.energy < 12 or cell.available_energy(organ)+0.0000001 < 2*burst or cell.biomass < 0.18*burst: continue
		cell.spend_energy(2*burst,organ,"combat")
		if organ.kind == "poreforming":
			_emit_aimed(TAG,cell.organ_position(organ),aim,155,0.03*burst,cell.id)
			for unit in 4: _emit_aimed(PORE_SUBUNIT,cell.organ_position(organ),aim,155+unit*4,0.0375*burst,cell.id)
		else:
			_emit_aimed(DECOY,cell.organ_position(organ),aim,145,0.03*burst,cell.id)
			_emit_aimed(TOXIN,cell.organ_position(organ),aim,170,0.15*burst,cell.id)
		cell.biomass -= 0.18*burst
		organ.consume_flash = 1
		organ.burst_clock = 0.75*Genes.factor(organ,"cooldown")

func _motion(dt: float) -> void:
	for cell in cells:
		if not cell.dead and cell.activity > 0: _motion_cell(cell,dt*cell.activity)

func _motion_cell(cell, local_dt: float) -> void:
	var previous: Vector2 = cell.position
	var steering_power := 0.0
	for organ in cell.organs:
		if cell.energy <= 0: continue
		var pursuing: bool = organ.kind in ["hunting","photosynthesis"] and organ.id == cell.target_organ_id and cell.drive_active and cell.target_memory > 0 and cell.target_mode in ["hunt","light"]
		if organ.kind not in ["propulsion","cilia"] and not pursuing: continue
		var arm: Vector2 = cell.organ_position(organ)-cell.position
		var power: float = (2600.0 if organ.kind == "propulsion" else Cell.CILIA_THRUST if organ.kind == "cilia" else 1100.0)*organ.scale*organ.scale*(organ.hp/organ.max_hp)*Genes.factor(organ,"thrust")
		var energy_cost: float = local_dt*(Cell.CILIA_MOTION if organ.kind == "cilia" else Cell.MOTION_UPKEEP)*organ.scale*organ.scale*Genes.factor(organ,"motion_cost")
		power *= minf(1,cell.available_energy(organ)/maxf(0.000001,energy_cost))
		var thrust: Vector2 = cell.organ_normal(organ).rotated(cell.angle)
		# Flagella can reverse their stroke, but force follows their mounted axis.
		if organ.kind in ["propulsion","cilia"] and thrust.dot(cell.target) < 0: thrust = -thrust
		var impulse: Vector2 = thrust*power*local_dt
		if fluid.deposit(cell.position+arm,-impulse):
			cell.velocity += impulse/cell.mass
			cell.angular_velocity += arm.cross(impulse)/cell.inertia
			steering_power += power
			cell.spend_energy(energy_cost,organ,"movement")
	# Flagella can reverse their stroke to retreat while the receptor remains
	# facing the threat. A paired steering impulse also acts on the medium.
	if steering_power > 0:
		var error := wrapf(cell.facing.angle()-cell.target_mouth-cell.angle,-PI,PI)
		var torque := clampf(cell.inertia*(error*12-cell.angular_velocity*7),-steering_power*cell.radius,steering_power*cell.radius)
		var arm: Vector2 = Vector2.from_angle(cell.angle)*cell.radius*0.8
		if fluid.can_couple(cell.position+arm) and fluid.can_couple(cell.position-arm):
			var impulse: Vector2 = Vector2(-arm.y,arm.x).normalized()*torque*local_dt/(2*arm.length())
			fluid.deposit(cell.position+arm,-impulse)
			fluid.deposit(cell.position-arm,impulse)
			cell.angular_velocity += torque*local_dt/cell.inertia
	if native_body_fluid:
		fluid.velocity = kernels.fluid_body_exchange(fluid.velocity,fluid.activity,cell,local_dt,fluid.global_coupling)
	else:
		for i in 6:
			var arm = Vector2.from_angle(TAU*i/6.0+cell.angle)*cell.radius
			fluid.exchange(cell,arm,local_dt,cell.fluid_drag()/6.0)
	cell.angle = wrapf(cell.angle+cell.angular_velocity*local_dt,-PI,PI)
	if coarse_mode:
		var moved: Array = habitat_geometry.move(previous,Medium.wrap_position(previous+cell.velocity*local_dt),cell.velocity,cell.extent())
		cell.position = moved[0]
		cell.velocity = moved[1]
	else:
		habitat_geometry.move_cell(cell,previous,Medium.wrap_position(previous+cell.velocity*local_dt),local_dt)
	# Continuous sweep against other bodies catches high-speed crossings.
	for other in cells:
		if other == cell or other.dead: continue
		var start = Medium.offset(other.position,previous)
		var travel = Medium.offset(previous,cell.position)
		if start.length() > (cell.extent()+other.extent())+travel.length(): continue
		var distance: float = cell.support((-start).angle())+other.support(start.angle())
		if start.length() < distance-0.2 or travel.length_squared() < 0.00001: continue
		var t = clampf(-start.dot(travel)/travel.length_squared(),0,1)
		if (start+travel*t).length() < distance:
			var a = travel.length_squared()
			var b = 2*start.dot(travel)
			var c = start.length_squared()-distance*distance
			var hit = (-b-sqrt(maxf(0,b*b-4*a*c)))/(2*a)
			if hit >= 0 and hit <= 1: cell.position = Medium.wrap_position(previous+travel*hit)

func _contacts(dt: float) -> void:
	if native_contacts:
		for iteration in 5:
			var result: Vector2i = kernels.contacts_pass(cells,Contacts.pair,dt,iteration == 0)
			if profiling:
				profile_counts["cell_pair_checks"] = profile_counts.get("cell_pair_checks",0)+result.x
				profile_counts["cell_contacts"] = profile_counts.get("cell_contacts",0)+result.y
		return
	var checks := 0
	var hits := 0
	for iteration in 5:
		for i in cells.size():
			var a = cells[i]
			if a.dead: continue
			for j in range(i+1,cells.size()):
				var b = cells[j]
				if b.dead or (a.activity <= 0 and b.activity <= 0): continue
				var contact: bool = Contacts.pair(a,b,dt,iteration == 0)
				if profiling:
					checks += 1
					if contact: hits += 1
	if profiling:
		profile_counts["cell_pair_checks"] = profile_counts.get("cell_pair_checks",0)+checks
		profile_counts["cell_contacts"] = profile_counts.get("cell_contacts",0)+hits

func _exclude_particles() -> void:
	if native_exclusion:
		var ids := local_particle_ids()
		kernels.exclude(particles,ids,cells,player.position if camera_follows_player else camera_position,view_half)
		grid.update(particles,ids)
		return
	if spatial_queries: cell_index.rebuild(cells)
	# Deliberate visual/gameplay projection: external packets never hide inside
	# cytoplasm. Preserve material, and move bucket/interpolation history too.
	for index in local_particle_ids():
		var p: Dictionary = particles[index]
		if not p.alive or p.kind == PHEROMONE or activity_at(p.p) <= 0: continue
		for iteration in 3:
			var moved := false
			for cell_id in cell_index.at(p.p) if spatial_queries else range(cells.size()):
				var cell = cells[cell_id]
				if cell.dead or cell.activity <= 0: continue
				var offset := Medium.offset(cell.position,p.p)
				if offset.length_squared() > pow(cell.extent()+8,2): continue
				var angle := offset.angle() if offset.length_squared() > 0.0001 else index*2.4
				var edge: float = cell.visible_support(angle-cell.angle)+7
				if offset.length() >= edge-0.001: continue
				var before: Vector2 = p.p
				p.p = Medium.wrap_position(cell.position+Vector2.from_angle(angle)*edge)
				p.previous = p.p
				if kernels != null: kernels.invalidate_particle_render(index)
				grid.move(index,before,p.p)
				moved = true
			if not moved: break

func _clear_receptors(cell, dt: float) -> void:
	for organ in cell.organs:
		if organ.blocked <= 0: continue
		# Basal unbinding never needs energy. ATP-funded cleaning and repair
		# bodies speed recovery; occupation cannot become a permanent disable.
		organ.blocked = maxf(0,organ.blocked-dt*0.045)
		var cleared: float = minf(organ.blocked,dt*0.18*(1+cell.count("regenerative")*1.5))
		var energy: float = cell.spend_energy(cleared*1.2,organ,"receptor cleaning")
		organ.blocked = maxf(0,organ.blocked-energy/1.2)

func _receptor_contacts() -> void:
	for cell in cells:
		if cell.dead or cell.activity <= 0: continue
		for organ in cell.organs:
			if organ.kind not in ["feeding","sensing","hunting"]: continue
			var at: Vector2 = cell.organ_position(organ)
			var forward: Vector2 = cell.organ_normal(organ).rotated(cell.angle)
			var radius: float = 12*organ.scale
			if particle_pool:
				kernels.pool_decoys(grid.query_kind(particles,at,radius+6,DECOY),cell,organ,inherited_lineages,player.position if camera_follows_player else camera_position,view_half)
				continue
			for index in grid.query_kind(particles,at,radius+6,DECOY):
				var p: Dictionary = particles[index]
				if not p.alive or p.kind != DECOY or inherited_lineages.get(p.owner,p.owner) == cell.lineage_id() or activity_at(p.p) <= 0: continue
				var delta := Medium.offset(at,p.p)
				if delta.length() > radius+particle_radius(p.kind)*particle_scale(p.amount): continue
				var normal := delta.normalized()
				if forward.dot(normal) < 0.25 or p.direction.dot(-normal) < 0.5: continue
				organ.blocked = minf(1,organ.blocked+0.65)
				cell.waste += p.amount
				if kernels != null: kernels.invalidate_particle_render(index)
				p.alive = false
				cell.render_revision += 1

func _surface_contacts() -> void:
	var camera: Vector2 = player.position if camera_follows_player else camera_position
	if particle_pool:
		kernels.pool_surface_contacts(grid.query(player.position,view_half.length()+180),cells,inherited_lineages,camera,view_half)
		return
	for index in local_particle_ids():
		var packet: Dictionary = particles[index]
		if not packet.alive or packet.kind not in [TAG,PORE_SUBUNIT,ANTITOXIN]: continue
		for cell in cells:
			if cell.dead or cell.activity <= 0: continue
			if packet.kind != ANTITOXIN and cell.lineage_id() == inherited_lineages.get(packet.owner,packet.owner): continue
			var d := Medium.offset(cell.position,packet.p)
			if d.length() > cell.extent()+5 or d.length() > cell.support(d.angle())+5: continue
			if packet.direction.dot(-d.normalized()) < 0.5: continue
			if cell.accept_surface(packet.kind,packet.amount,d.angle(),packet.owner):
				packet.alive = false
				break

func _toxin_contacts() -> void:
	_surface_contacts()
	if spatial_queries: cell_index.rebuild(cells)
	if particle_pool:
		kernels.pool_toxins(local_particle_kind(TOXIN),cells,cell_index.buckets,spatial_queries,inherited_lineages,player.position if camera_follows_player else camera_position,view_half,player.id,evolution)
		return
	for index in local_particle_kind(TOXIN):
		var p: Dictionary = particles[index]
		if not p.alive or p.kind != TOXIN or activity_at(p.p) <= 0: continue
		for cell_id in cell_index.at(p.p) if spatial_queries else range(cells.size()):
			var cell = cells[cell_id]
			if cell.dead or cell.activity <= 0 or cell.lineage_id() == inherited_lineages.get(p.owner,p.owner): continue
			var d = Medium.offset(cell.position,p.p)
			if d.length() <= cell.support(d.angle())+5:
				cell.waste += cell.damage(p.amount*75,d.angle()) + p.amount
				cell.death_hint = "Membrane failed after toxin exposure"
				if p.owner == player.id: evolution.record("toxin",p.amount*75)
				if kernels != null: kernels.invalidate_particle_render(index)
				p.alive = false
				break

func _die(cell, transferred: float = 0.0) -> void:
	if cell.dead: return
	if server_mode and not remote_client:
		for ledger in family_ledgers: ledger.died(cell,self)
	elif evolution.enabled: lineage.died(cell,self)
	death_serial += 1
	death_bursts.append({"serial":death_serial,"time":time,"at":cell.position,"radius":cell.radius,
		"angle":cell.angle,"outline":cell.membrane.outline(),"lineage":cell.lineage_id(),"player":cell == player})
	if death_bursts.size() > 32: death_bursts.pop_front()
	cell.chemistry.ensure_cpu()
	cell.dead = true
	cell.health = 0
	var total: float = maxf(0,cell.organic_mass()-transferred)
	var oxygen: float = cell.oxygen
	var structural: float = maxf(0,cell.body+cell.biomass+cell.organ_mass()+cell.brood_mass+cell.chemistry.reactor_mass-transferred)
	for vacuole in cell.chemistry.vacuoles: structural += vacuole.material
	# Surface complexes have already oxidized; lysis does not refuel them.
	if cell.surface_material() > 0: _emit_material(WASTE,cell.position,cell.surface_material(),Vector2.ZERO,cell.id)
	var quantum: float = Catalog.data().ecology.packet_quantum
	var count := maxi(1,ceili(structural/quantum))
	for i in count:
		var direction := Vector2.from_angle(TAU*i/count)
		spawn_particle(NUTRIENT,cell.position+direction*cell.radius*0.9,direction*24,structural/count,cell.id)
	for packet in cell.chemistry.particles:
		if not packet.alive: continue
		var key: String = "nutrient" if packet.species == "food" else "atp" if packet.species == "reserved_atp" else packet.species
		var kind := -1
		for definition in Catalog.data().external_species:
			if definition.key == key: kind = definition.id; break
		assert(kind >= 0,"Intracellular species has no lysis packet")
		var normal: Vector2 = packet.p.normalized().rotated(cell.angle)
		var at: Vector2 = Medium.wrap_position(cell.position+packet.p.rotated(cell.angle))
		spawn_particle(kind,at,normal*24,packet.amount,cell.id)
		if kind == NUTRIENT:
			last_spawn.capacity = clampf(packet.fuel/7.5,0,packet.amount)
			_commit_spawn_metadata()
		packet.alive = false
	cell.chemistry.particles.clear()
	cell.chemistry.totals.clear()
	cell.chemistry.bins.clear()
	cell.chemistry.vacuoles.clear()
	cell.surface_complexes.clear()
	cell.body = 0
	cell.biomass = 0
	cell.brood_mass = 0
	cell.organs.clear()
	cell.chemistry.reactor_mass = 0
	events.append({"time":time,"type":"death","id":cell.id,"released":total,"oxygen_released":oxygen})
	if cell == player: return
	if cell.role == "ancestor" or cell.lineage_id() == 0:
		cells.erase(cell)
		return
	kills += 1
	cells.erase(cell)
	if not server_mode:pending_replacements.append({"role":cell.role,"id":cell.id})
	_replace_population()

func _replace_population() -> void:
	if server_mode: return # Gameplay introductions/objectives are deferred.
	# At wide microscope zoom there may be no hidden space. Defer the explicit
	# replacement trigger until a full organism can fit outside the view.
	for pending in pending_replacements.duplicate():
		if time < float(pending.get("not_before",0)): continue
		if evolution.enabled and evolution.clock < float(pending.get("not_before",0)): continue
		var at := Vector2.ZERO
		var found := false
		for attempt in 24:
			at = Medium.wrap_position(player.position+Vector2.from_angle(rng.randf()*TAU)*1100)
			if attempt > 0: at = Vector2(rng.randf()*WORLD.x,rng.randf()*WORLD.y)
			var hidden := Medium.visibility(at,player.position if camera_follows_player else camera_position,view_half+Vector2.ONE*160) <= 0
			var announced: bool = evolution.enabled and evolution.arrival_budget > 0 and evolution.clock >= evolution.resistance_clock and Medium.offset(player.position,at).length() > 700+player.extent()
			if safe_birth_position(at,160) and (hidden or announced):
				found = true
				break
		if not found: continue
		var role: String = pending.role
		if evolution.enabled and evolution.tide >= 1 and evolution.newcomer_count%2 == 0: role = "hunter"
		var replacement = _make_cell(at,role)
		replacement.activity = 1.0 if activity_for_cell(replacement) > 0 else 0.0
		evolution.newcomer(replacement,self)
		evolution.arrival_budget = maxi(0,evolution.arrival_budget-1)
		external_input += replacement.organic_mass()
		events.append({"time":time,"type":"population_arrival" if pending.id < 0 else "population_replacement","id":replacement.id,"replaces":pending.id})
		pending_replacements.erase(pending)

func _build_debris(amount: float) -> void:
	if amount <= 0: return
	if build_original != null: build_waste += amount
	else: spawn_particle(WASTE,player.position,Vector2.ZERO,amount,player.id)

func begin_build() -> void:
	if server_mode: return # Live edits commit through WorldHost, never clone/freeze biology.
	if build_original != null or player.dead or evolution.terminal(): return
	build_original = player
	build_state = {"points":evolution.points,"offers":evolution.offers.duplicate(),"learned":evolution.learned.duplicate(),"chosen":evolution.chosen,"spending":evolution.spending.duplicate(true),"challenge":evolution.challenge,"challenge_mass":evolution.challenge_mass,"challenge_intake":evolution.challenge_intake,"challenge_fixed":evolution.challenge_fixed,"challenge_cell":evolution.challenge_cell,"stable_seconds":evolution.stable_seconds}
	var index := cells.find(player)
	player = Cell.clone_state(player)
	cells[index] = player
	build_waste = 0

func cancel_build() -> void:
	if build_original == null: return
	cells[cells.find(player)] = build_original
	player = build_original
	for key in build_state: evolution.set(key,build_state[key])
	build_original = null
	build_state.clear()
	build_waste = 0

func commit_build() -> void:
	if build_original == null: return
	build_original = null
	build_state.clear()
	_build_debris(build_waste)
	build_waste = 0

func undo_build() -> void:
	cancel_build()
	begin_build()

func resize_organ(identity: int, size: float) -> bool:
	var quote: Dictionary = player.resize_quote(identity,size)
	if quote.is_empty() or (evolution.enabled and evolution.points < quote.ap): return false
	var result: Dictionary = player.resize_organ(identity,size)
	if result.is_empty(): return false
	evolution.spend(result.ap,"Enlarge organ")
	_build_debris(result.debris)
	return true

func mutate_organ(identity: int, gene: String) -> bool:
	if remote_client: return edit("mutate",{"id":identity,"gene":gene})
	var organ: Dictionary = player.organ_by_id(identity)
	if gene not in evolution.learned or organ.is_empty(): return false
	var cost := Genes.adaptation_price(organ)
	if evolution.enabled and evolution.points < cost: return false
	if not player.specialize(identity,gene): return false
	evolution.spend(cost,"Apply "+gene)
	return true

func offspring_quote(subject = null) -> Dictionary:
	var parent=player if subject==null else subject
	var tissue: float = parent.chemistry.reactor_mass
	for node in parent.chemistry.nodes:
		if not node.basal: tissue += 0.025
	for organ in parent.organs: tissue += organ.get("max_material",Cell.organ_cost(organ.kind,organ.scale))
	var radius := maxf(34,parent.occupied()/(TAU*0.8))
	var body := maxf(30,pow(radius/47.0,2)*78-12)
	var inherited_body := minf(body,maxf(0,parent.body-30))
	return {"body":body,"body_transfer":inherited_body,"biomass":12.0,"material":body+12+tissue-inherited_body,"total_material":body+12+tissue,"energy":60.0,"oxygen":0.0}

func safe_birth_position(at: Vector2, radius: float) -> bool:
	if not habitat_geometry.clear_at(at,radius): return false
	for cell in cells:
		if not cell.dead and Medium.offset(cell.position,at).length() < cell.extent()+radius+20: return false
	return true

func make_offspring(parent, quote: Dictionary):
	var child = Cell.new(next_id)
	child.role = "descendant"
	child.generation = parent.generation+1
	child.lineage = parent.lineage_id()
	child.body = quote.body
	child.biomass = quote.biomass
	child.substrate = 0
	child.carbon = 0
	child.oxygen = 0
	child.energy = 40
	child.chemistry.inherit_configuration(parent.chemistry)
	child.organs = parent.organs.duplicate(true)
	child.next_organ_id = parent.next_organ_id
	child.exploration = parent.exploration
	child.response_cycle = parent.response_cycle
	for organ in child.organs:
		organ.hp = organ.max_hp
		organ.material = organ.max_material
		organ.blocked = 0
		organ.target_id = -1
		organ.burst_clock = 0.0
		organ.feeding = false
		organ.link = Vector2.ZERO
		organ.consume_flash = 0.0
		organ.consume_clock = 0.0
		organ.charge_flash = 0.0
		organ.consumed_total = 0.0
	for organ in child.organs:
		if organ.kind == "photosynthesis": child.chemistry.anchor_photosynthesis(child,organ); break
	child.update_geometry()
	child.membrane = Cell.Membrane.new(child.radius)
	child.membrane.skeleton = Cell.clone_state(parent.membrane.skeleton)
	child.membrane.skeleton.begin(child.radius)
	child.update_geometry()
	return child

func divide_lineage(dormant: bool = false, follow: bool = true) -> bool:
	if remote_client: return edit("divide",{"dormant":dormant})
	if player.dead or evolution.terminal() or build_original != null: return false
	return _divide_paid(player,lineage,dormant,follow,true)

func _divide_paid(parent,ledger,dormant: bool=false,follow: bool=false,progress: bool=false) -> bool:
	if parent.dead or parent.health<=0 or parent.lineage_id()!=ledger.root_id:return false
	if not dormant and cells.filter(func(cell):return not cell.dead).size()>=MAX_LIVE_CELLS:return false
	if dormant and ledger.dormant.size() >= Lineage.MAX_DORMANT: return false
	if not dormant and ledger.active_family(self).size() >= Lineage.MAX_ACTIVE: return false
	var quote := offspring_quote(parent)
	if parent.brood_mass+0.000001 < quote.material or parent.brood_energy < quote.energy: return false
	if parent.count("feeding")+parent.count("photosynthesis") == 0: return false
	var child = make_offspring(parent,quote)
	child.position = parent.position
	var found := dormant
	if not dormant:
		for i in 32:
			child.position = Medium.wrap_position(parent.position+Vector2.from_angle(parent.angle+TAU*i/32)*(parent.extent()+child.extent()+45))
			if safe_birth_position(child.position,child.extent()):
				found = true
				break
	if not found: return false
	child.chemistry.partition(parent.chemistry,0.25)
	parent.brood_mass -= quote.material
	parent.body -= quote.body_transfer
	parent.brood_energy -= quote.energy
	parent.oxygen -= child.oxygen
	parent.update_geometry()
	parent.render_revision+=1
	child.previous_position = child.position
	child.angle = parent.angle
	child.previous_angle = child.angle
	inherited_lineages[child.id] = child.lineage_id()
	next_id += 1
	ledger.births += 1
	ledger.register(child,parent.id,child.generation,"dormant" if dormant else "active" if follow else "living",time)
	if dormant:
		ledger.dormant.append(child)
	else:
		cells.append(child)
		if follow:
			var record: Dictionary = ledger.record_for(parent.id)
			if not record.is_empty(): record.state = "living"
			parent.role = "ancestor"
			child.role = "player"
			player = child
			evolution.observe_successor(child)
	if progress:evolution.offspring_id = child.id if not dormant else evolution.offspring_id
	_record_sound("division",parent.position,parent.id)
	ledger.notify("Dormant successor funded · family safety costs real tissue and ATP." if dormant else "Successor released · the family now has another living branch.")
	events.append({"type":"division","id":child.id,"parent":parent.id,"dormant":dormant,"time":time,"material":quote.total_material,"reserve_used":quote.material,"body_transferred":quote.body_transfer,"oxygen_transferred":child.oxygen,"atp_used":20})
	return true

func follow_family(identity: int) -> bool:
	if remote_client: return edit("follow",{"id":identity})
	if build_original != null or evolution.terminal(): return false
	for cell in lineage.active_family(self):
		if cell.id == identity and cell != player:
			lineage.adopted(cell,self,false)
			return true
	return false

func edit(action: String,args: Dictionary = {}):
	if remote_client:
		if command_sink.is_valid(): command_sink.call(action,args)
		if action in ["module_add","link_add"]: return 0
		if action in ["route_add","configuration"]: return ""
		return true
	return preload("res://scripts/network/editor_commands.gd").execute(self,action,args)

func _fund_reproduction(cell,dt: float) -> void:
	if not automatic_reproduction or remote_client or cell.dead or cell.health<=0 or dt<=0:return
	if cell==player and build_original!=null:return
	cell.reproduction_elapsed+=dt
	if cell.reproduction_elapsed<.5:return
	var elapsed: float=cell.reproduction_elapsed;cell.reproduction_elapsed=0
	if cell.count("feeding")+cell.count("photosynthesis")==0:return
	var quote:=offspring_quote(cell)
	var tissue: float=minf(REPRODUCTION_RATE*elapsed,minf(maxf(0,cell.biomass-REPRODUCTION_TISSUE_FLOOR),maxf(0,quote.material-cell.brood_mass)))
	var atp: float=minf(REPRODUCTION_RATE*elapsed,minf(maxf(0,cell.energy-REPRODUCTION_ATP_FLOOR),maxf(0,quote.energy-cell.brood_energy)))
	if tissue<=0 and atp<=0:return
	cell.biomass-=tissue;cell.brood_mass+=tissue
	if atp>0:cell.chemistry.reserve_atp(atp,true)
	cell.update_geometry();cell.render_revision+=1

func _family_ledger(cell):
	if lineage.root_id==cell.lineage_id():
		if not family_ledgers.has(lineage):family_ledgers.append(lineage)
		return lineage
	for ledger in family_ledgers:
		if ledger.root_id==cell.lineage_id():return ledger
	var ledger=Lineage.new();ledger.root_id=cell.lineage_id()
	ledger.register(cell,-1,cell.generation,"living",time);family_ledgers.append(ledger)
	return ledger

func _step_reproduction() -> void:
	if not automatic_reproduction or remote_client:return
	for cell in cells.duplicate():
		if cell.dead or cell.health<=0 or cell.brood_mass<=0 or cell.brood_energy<60 or time<cell.reproduction_retry_at:continue
		if cell==player and (build_original!=null or (not server_mode and evolution.terminal())):continue
		var quote:=offspring_quote(cell)
		if cell.brood_mass+.000001<quote.material:continue
		cell.reproduction_retry_at=time+.5
		_divide_paid(cell,_family_ledger(cell),false,false)
