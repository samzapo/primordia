extends Node
## Buffered audio sample clock; observes ecology without advancing or mutating it.
const Synth = preload("res://scripts/music_synth.gd")
const Score = preload("res://scripts/music_score.gd")
var game
var web_audio
var web_generation:=-1
var resume_volume:=.65
var score := Score.new()
var mixer
var player := AudioStreamPlayer.new()
var playback: AudioStreamGeneratorPlayback
var bank_job: Thread
var ready_bank := false
var enabled := true
var refill_between_ticks := true # profiler ablation; ordinary playback services every tick
var observe_clock := 0.0
var frame_cursor := 0
var render_usec := 0
var peak_render_usec := 0
var skips := 0
var bank_ms := 0.0
var bank_started := 0
var startup_skips := 0
var buffer_capacity := 0
var silence_clock := 0.0
var visual_notes: Array = []
var waves: Array = []
var audible_frame := 0

func _queue_visual_notes(events: Array, start: int) -> void:
	for event in events:
		if visual_notes.size() >= 128: break
		var cue: Dictionary = event.duplicate()
		cue["at"] = start+event.offset
		visual_notes.append(cue)

func _update_waves(dt: float) -> void:
	if (playback == null and web_audio==null) or game.preferences.music_volume <= 0:
		visual_notes.clear()
		waves.clear()
		return
	for wave in waves: wave.age += minf(dt,0.1)
	waves = waves.filter(func(wave): return wave.age < 0.65)
	if web_audio!=null:audible_frame=int(web_audio.cached.get("frame",0))
	else:
		var queued := buffer_capacity-playback.get_frames_available()
		audible_frame = maxi(audible_frame,frame_cursor-queued-roundi(AudioServer.get_output_latency()*Synth.RATE))
	while not visual_notes.is_empty() and visual_notes[0].at <= audible_frame:
		var cue: Dictionary = visual_notes.pop_front()
		var age := float(audible_frame-cue.at)/Synth.RATE
		if age > 0.65 or waves.size() >= 64: continue
		var lane: int = cue.lane
		if score.channels[lane].id != cue.source or score.channels[lane].gain <= 0: continue
		cue["age"] = maxf(0,age)
		cue["strength"] = minf(1,score.channels[lane].gain*cue.gain*4)
		waves.append(cue)

func initialize(owner_game) -> void:
	game = owner_game
	var args := OS.get_cmdline_user_args()
	enabled = ("--music-benchmark" in args) or (DisplayServer.get_name() != "headless" and not "--benchmark" in args and game.screenshot_path == "")
	if OS.has_feature("web") and enabled:
		web_audio=preload("res://scripts/web_music.gd").new();web_audio.initialize(game.preferences.music_volume)
	add_child(player)
	if enabled and game.preferences.music_volume > 0: _prepare()

func _prepare() -> void:
	if web_audio!=null:return
	if ready_bank or bank_job != null: return
	bank_started = Time.get_ticks_usec()
	if not Synth.cached_bank.is_empty():
		_finish_bank(Synth.cached_bank)
	else:
		bank_job = Thread.new()
		var result := bank_job.start(Synth.make_bank)
		if result != OK:
			bank_job = null
			push_warning("Music sample preparation could not start; audio remains off.")

func _finish_bank(bank: Array) -> void:
	Synth.cached_bank = bank
	bank_ms = (Time.get_ticks_usec()-bank_started)/1000.0
	mixer = ClassDB.instantiate("PrimordiaMusicMixer") if OS.get_environment("PRIMORDIA_BACKEND") != "script" and ClassDB.class_exists("PrimordiaMusicMixer") else Synth.new()
	mixer.configure(bank)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = Synth.RATE
	stream.buffer_length = 0.4
	player.stream = stream
	ready_bank = true

func reset() -> void:
	if web_audio!=null:web_audio.reset()
	player.stop()
	playback = null
	frame_cursor = 0
	audible_frame = 0
	visual_notes.clear()
	waves.clear()
	observe_clock = 0
	score = Score.new()
	if ready_bank: mixer.configure(Synth.cached_bank)

func update_music(dt: float) -> void:
	if web_audio!=null:
		_update_web_music(dt);_update_waves(dt);return
	_update_waves(dt)
	if not enabled: return
	if bank_job != null and not bank_job.is_alive():
		var bank: Array = bank_job.wait_to_finish()
		bank_job = null
		_finish_bank(bank)
	if not ready_bank:
		if game.preferences.music_volume > 0: _prepare()
		return
	observe_clock -= dt
	if observe_clock <= 0:
		score.observe(game.world,game.render_camera,game.get_viewport_rect().size*0.5/game.zoom,game.is_paused(),game._follow_cell() if game.world.remote_client else game.world.player)
		observe_clock = 0.10
	if game.preferences.music_volume <= 0:
		score.reset_accents(game.world)
		silence_clock += dt
		if not player.playing or silence_clock > 0.35:
			player.stop()
			playback = null
			return
	else: silence_clock = 0
	refill()

func refill() -> void:
	if web_audio!=null:return # Browser audio is scheduled independently below.
	# Catch-up ticks can starve _process for longer than the audio queue. Refill
	# from the same sample clock between ticks; do not observe or mutate ecology.
	if not enabled or not ready_bank or (game.preferences.music_volume <= 0 and not player.playing): return
	var started := Time.get_ticks_usec()
	if not player.playing:
		# Unmute starts a fresh musical phrase; biology is never restarted.
		score.reset_accents(game.world)
		mixer.configure(Synth.cached_bank)
		frame_cursor = 0
		audible_frame = 0
		visual_notes.clear()
		waves.clear()
		# The reference mixer can take tens of milliseconds. Prepare silence-free
		# startup while the stream is stopped, then begin with a complete buffer.
		var priming_frames := roundi(0.16*Synth.RATE)
		var priming_events := score.events(0,priming_frames)
		var priming: PackedVector2Array = mixer.render(priming_frames,priming_events,score.channels,game.preferences.music_volume)
		player.play()
		playback = player.get_stream_playback()
		startup_skips = playback.get_skips()
		buffer_capacity = playback.get_frames_available()
		if not playback.push_buffer(priming):
			player.stop()
			playback = null
			push_warning("Music could not prime its playback buffer.")
			return
		_queue_visual_notes(priming_events,0)
		frame_cursor = priming_frames
	var capacity := buffer_capacity
	var target := mini(capacity,roundi(0.16*Synth.RATE))
	var queued := capacity-playback.get_frames_available()
	var needed := maxi(0,target-queued)
	while needed > 0:
		var count := mini(1024,needed)
		var events := score.events(frame_cursor,count)
		var buffer: PackedVector2Array = mixer.render(count,events,score.channels,game.preferences.music_volume)
		if not playback.push_buffer(buffer): break
		_queue_visual_notes(events,frame_cursor)
		frame_cursor += count
		needed -= count
	render_usec = Time.get_ticks_usec()-started
	peak_render_usec = maxi(peak_render_usec,render_usec)
	skips = maxi(0,playback.get_skips()-startup_skips)

func _exit_tree() -> void:
	if web_audio!=null:web_audio.reset()
	player.stop()
	playback = null
	player.stream = null
	mixer = null
	if bank_job != null:
		bank_job.wait_to_finish()
		bank_job = null

func _update_web_music(dt: float) -> void:
	observe_clock-=dt
	if observe_clock>0:return
	observe_clock=.05
	var state: Dictionary=web_audio.status();ready_bank=state.get("ready",false)
	web_audio.volume(game.preferences.music_volume)
	if not ready_bank or state.get("state","")!="running":return
	score.observe(game.world,game.render_camera,game.get_viewport_rect().size*.5/game.zoom,game.is_paused(),game._follow_cell() if game.world.remote_client else game.world.player)
	var now: int=state.get("frame",0)
	if web_generation!=int(state.get("generation",0)):
		web_generation=state.get("generation",0);frame_cursor=now;visual_notes.clear();waves.clear();score.reset_accents(game.world)
	if game.preferences.music_volume<=0:
		score.reset_accents(game.world);frame_cursor=now;visual_notes.clear();waves.clear();return
	if frame_cursor<now:
		if frame_cursor>0:skips+=1
		frame_cursor=now;score.reset_accents(game.world)
	var target:=now+roundi(.35*Synth.RATE)
	if frame_cursor>=target:return
	var events: Array=score.events(frame_cursor,target-frame_cursor)
	web_audio.schedule(frame_cursor,events,score.channels,game.preferences.music_volume)
	_queue_visual_notes(events,frame_cursor);frame_cursor=target

func toggle() -> void:
	if game.preferences.music_volume>0:
		resume_volume=game.preferences.music_volume;game.preferences.music_volume=0
	else:game.preferences.music_volume=resume_volume
	game.preferences.save_settings()
	if web_audio!=null:web_audio.volume(game.preferences.music_volume)

func enable_music() -> void:
	if game.preferences.music_volume<=0:game.preferences.music_volume=resume_volume
	game.preferences.save_settings()
	if web_audio!=null:
		JavaScriptBridge.eval("window.primordiaMusic.unlock()")
		web_audio.volume(game.preferences.music_volume)
