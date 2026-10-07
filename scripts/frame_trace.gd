extends RefCounted
## Opt-in bounded diagnostic; no disk I/O or print in the measured frame.
## GPU/renderer values are delayed engine measurements, not additive wall phases.
const LIMIT := 6000
var game
var rows: Array[Dictionary] = []
var work_us: Dictionary = {}
var counts: Dictionary = {}
var prior_post := 0
var pre_draw := 0
var ticks := 0
var elapsed_sim := 0.0

func start(owner) -> void:
	game = owner
	game.world.profiling = true
	RenderingServer.viewport_set_measure_render_time(game.get_viewport().get_viewport_rid(),true)
	RenderingServer.frame_pre_draw.connect(_pre)
	RenderingServer.frame_post_draw.connect(_post)
	prior_post = Time.get_ticks_usec()

func stop() -> void:
	game.world.profiling = false
	if RenderingServer.frame_pre_draw.is_connected(_pre): RenderingServer.frame_pre_draw.disconnect(_pre)
	if RenderingServer.frame_post_draw.is_connected(_post): RenderingServer.frame_post_draw.disconnect(_post)
	RenderingServer.viewport_set_measure_render_time(game.get_viewport().get_viewport_rid(),false)

func work(key: String, usec: int) -> void:
	work_us[key] = work_us.get(key,0)+usec

func count(key: String, amount: int = 1) -> void:
	counts[key] = counts.get(key,0)+amount

func tick(usec: int, dt: float) -> void:
	ticks += 1
	elapsed_sim += dt
	work("ticks",usec)
	for key in game.world.profile_usec: work("sim."+key,game.world.profile_usec[key])
	for key in game.world.profile_counts: count(key,game.world.profile_counts[key])

func _pre() -> void:
	pre_draw = Time.get_ticks_usec()

func _post() -> void:
	var now := Time.get_ticks_usec()
	if rows.size() < LIMIT:
		var viewport: RID = game.get_viewport().get_viewport_rid()
		var sim = game.world
		var times := {}
		for key in ["cell_pair_checks","cell_contacts","spike_contacts","membrane_updates","mesh_updates","receptor_queries","receptor_candidates","pheromone_queries"]:
			if not counts.has(key): counts[key] = 0
		for key in work_us: times[key] = work_us[key]/1000.0
		rows.append({"frame":Engine.get_frames_drawn(),"wall_ms":(now-prior_post)/1000.0,
			"ticks":ticks,"sim_dt":elapsed_sim,"sim_time":sim.time,"phases_ms":times,
			"render_boundary_ms":(now-pre_draw)/1000.0,
			"engine_fps":Engine.get_frames_per_second(),
			"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),
			"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),
			"render_setup_ms":RenderingServer.get_frame_setup_time_cpu(),
			"draw_calls":RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"counts":counts.duplicate(),"cells":sim.cells.size(),"active_cells":sim.active_cells,
			"views":game.views.size(),"particles":sim.particle_count(),"active_particles":sim.active_particles,
			"background_particles":sim.background_particles,"pheromones":sim.pheromone_count(),
			"audio_skips":game.music.skips,"audio_ready":game.music.ready_bank})
	prior_post = now
	ticks = 0
	elapsed_sim = 0
	work_us.clear()
	counts.clear()
