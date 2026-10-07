extends Node
## Buffered audio sample clock; observes ecology without advancing or mutating it.
const Synth = preload("res://scripts/music_synth.gd")
const Score = preload("res://scripts/music_score.gd")
var game
var score := Score.new()
var mixer
var player := AudioStreamPlayer.new()
var playback: AudioStreamGeneratorPlayback
var bank_job: Thread
var ready_bank := false
var enabled := true
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

func initialize(owner_game) -> void:
	game = owner_game
	var args := OS.get_cmdline_user_args()
	enabled = ("--music-benchmark" in args) or (DisplayServer.get_name() != "headless" and not "--benchmark" in args and game.screenshot_path == "")
	add_child(player)
	if enabled and game.preferences.music_volume > 0: _prepare()

func _prepare() -> void:
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
	player.stop()
	playback = null
	frame_cursor = 0
	observe_clock = 0
	score = Score.new()
	if ready_bank: mixer.configure(Synth.cached_bank)

func update_music(dt: float) -> void:
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
		score.observe(game.world,game.render_camera,game.get_viewport_rect().size*0.5/game.zoom,game.is_paused())
		observe_clock = 0.10
	if game.preferences.music_volume <= 0:
		score.reset_accents(game.world)
		silence_clock += dt
		if not player.playing or silence_clock > 0.35:
			player.stop()
			playback = null
			return
	else: silence_clock = 0
	var started := Time.get_ticks_usec()
	if not player.playing:
		# Unmute starts a fresh musical phrase; biology is never restarted.
		score.reset_accents(game.world)
		mixer.configure(Synth.cached_bank)
		frame_cursor = 0
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
		frame_cursor += count
		needed -= count
	render_usec = Time.get_ticks_usec()-started
	peak_render_usec = maxi(peak_render_usec,render_usec)
	skips = maxi(0,playback.get_skips()-startup_skips)

func _exit_tree() -> void:
	player.stop()
	playback = null
	player.stream = null
	mixer = null
	if bank_job != null:
		bank_job.wait_to_finish()
		bank_job = null
