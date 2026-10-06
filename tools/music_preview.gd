extends SceneTree
## Offline authored listening fixture, using the same score/sampler as gameplay.
const Synth = preload("res://scripts/music_synth.gd")
const Score = preload("res://scripts/music_score.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "user://primordia-music-preview.wav"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): path = arg.trim_prefix("--output=")
	preload("res://scripts/backend.gd").create()
	var bank := Synth.make_bank()
	var mixer = ClassDB.instantiate("PrimordiaMusicMixer") if OS.get_environment("PRIMORDIA_BACKEND") != "script" and ClassDB.class_exists("PrimordiaMusicMixer") else Synth.new()
	mixer.configure(bank)
	var score := Score.new()
	var count := Synth.RATE*30
	var bytes := PackedByteArray()
	bytes.resize(count*4)
	var small := PackedFloat32Array([1,0,0,1,1,0,1,0,1,0])
	var large := PackedFloat32Array([1,2,1,0,1,0,0,1,0,1])
	var cursor := 0
	var beginning := roundi(20*16*Synth.RATE*60/Synth.BPM/4)
	var peak := 0.0
	var square := 0.0
	while cursor < count:
		var time := float(cursor)/Synth.RATE
		var entering := smoothstep(5,18,time)
		var exiting := 1-smoothstep(24,29,time)
		var gain := entering*exiting
		score.mass = lerpf(105,260,smoothstep(16,25,time))
		score.sources = [
			{"id":0,"lane":1,"gain":1.0,"mass":score.mass,"counts":small},
			{"id":1,"lane":2,"gain":gain,"mass":820.0,"counts":large}
		]
		score.channels[1] = {"id":0,"gain":0.72,"pan":-0.15}
		score.channels[2] = {"id":1,"gain":gain*0.78,"pan":lerpf(0.85,0.05,entering)}
		var length := mini(1024,count-cursor)
		var events := score.events(beginning+cursor,length)
		var buffer: PackedVector2Array = mixer.render(length,events,score.channels,0.75*(1-smoothstep(28.5,30,time)))
		for i in length:
			var sample := buffer[i]
			peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
			square += sample.length_squared()
			bytes.encode_s16((cursor+i)*4,roundi(clampf(sample.x,-1,1)*32767))
			bytes.encode_s16((cursor+i)*4+2,roundi(clampf(sample.y,-1,1)*32767))
		cursor += length
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = Synth.RATE
	wav.stereo = true
	wav.data = bytes
	var result := wav.save_to_wav(path)
	print("MUSIC_PREVIEW ",JSON.stringify({"path":path,"seconds":30,"peak":peak,"rms_db":linear_to_db(sqrt(square/(count*2))),"mixer":mixer.metrics(),"result":result}))
	quit(0 if result == OK else 1)
