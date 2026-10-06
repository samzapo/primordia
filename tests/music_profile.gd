extends SceneTree
const Synth = preload("res://scripts/music_synth.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	preload("res://scripts/backend.gd").create()
	var bank := Synth.make_bank()
	var mixer = ClassDB.instantiate("PrimordiaMusicMixer") if OS.get_environment("PRIMORDIA_BACKEND") != "script" and ClassDB.class_exists("PrimordiaMusicMixer") else Synth.new()
	mixer.configure(bank)
	var channels: Array = []
	for i in 7: channels.append({"id":i,"gain":0.4,"pan":(i-3)/4.0})
	var times: Array[float] = []
	for block in 60:
		var events: Array = []
		if block%10 == 0:
			for voice in 40: events.append({"offset":0,"instrument":15,"lane":voice%6+1,"note":36,"gain":0.12})
		var began := Time.get_ticks_usec()
		mixer.render(1024,events,channels,0.65)
		times.append((Time.get_ticks_usec()-began)/1000.0)
	times.sort()
	print("MUSIC_PROFILE ",JSON.stringify({"native":mixer.get_class()=="PrimordiaMusicMixer","frames_per_block":1024,"blocks":60,"median_ms":times[30],"p95_ms":times[57],"max_ms":times[-1],"metrics":mixer.metrics()}))
	quit()
