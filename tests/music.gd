extends RefCounted
const Synth = preload("res://scripts/music_synth.gd")
const Score = preload("res://scripts/music_score.gd")
const Sim = preload("res://scripts/simulation.gd")
var host
func check(ok: bool, message: String) -> void: host.expect(ok,message)

func run(test_host) -> void:
	host = test_host
	_networks()
	_observation()
	var started := Time.get_ticks_usec()
	var bank := Synth.make_bank()
	print("MUSIC_BANK: ",(Time.get_ticks_usec()-started)/1000.0," ms")
	check(bank.size() == 17,"Music has seventeen authored percussion/tonal instruments including cilia")
	var distinct := {}
	for sample in bank:
		var peak := 0.0
		var square := 0.0
		var finite := true
		for value in sample:
			finite = finite and is_finite(value)
			peak = maxf(peak,absf(value))
			square += value*value
		check(finite and peak > 0.05 and peak < 1.4 and square/sample.size() > 0.0001,"Every synthesized instrument is finite, audible and bounded")
		check(absf(sample[0]) < 0.001 and absf(sample[-1]) < 0.001,"Instrument envelopes meet silence at both ends")
		distinct[hash(sample)] = true
	check(distinct.size() == 17,"Every instrument has a distinct synthesized waveform")
	Synth.cached_bank = bank
	_schedule()
	_mixer(bank)
	_preferences()
	preload("res://tests/music_ecology.gd").new().run(host,bank)

func _networks() -> void:
	var counts := {}
	var branched := false
	var tube_to_tube := false
	var spread := {}
	for seed in 64:
		var membrane = Sim.Cell.Membrane.new(47,seed)
		var net = membrane.skeleton
		counts[net.next_group] = true
		check(net.next_group >= 0 and net.next_group <= 4,"Seeded cells start with zero through four tension groups")
		var replay = Sim.Cell.Membrane.new(47,seed)
		check(net.links == replay.skeleton.links and net.junctions == replay.skeleton.junctions,"Anatomy seed replays its sequential network")
		for link in net.links:
			check(link.tension >= 0 and link.tension <= 1 and net.valid(link.a) and net.valid(link.b),"Initial link endpoints and tensions are valid")
			spread[roundi(link.tension*100)] = true
			branched = branched or link.a.kind == "junction" or link.b.kind == "junction"
			tube_to_tube = tube_to_tube or (link.a.kind == "junction" and link.b.kind == "junction")
		if seed < 10:
			for tick in 90: membrane.step(1.0/60,47,Vector2.ZERO,tick/60.0)
			check(Geometry2D.triangulate_polygon(membrane.outline()).size() > 0,"Random tension networks retain renderable membrane geometry")
			var area := 0.0
			var finite := true
			for i in membrane.COUNT:
				finite = finite and membrane.points[i].is_finite()
				area += membrane.points[i].cross(membrane.points[(i+1)%membrane.COUNT])*0.5
			var target: float = membrane.COUNT*47*47*sin(TAU/membrane.COUNT)*0.5
			check(finite and absf(area-target)/target < 0.03,"Random tension preserves hydrostatic area and finite motion")
	check(counts.size() == 5 and branched and tube_to_tube and spread.size() > 30,"Initial layouts cover all counts, varied tensions and tube-to-tube branching")
	var sim = Sim.new(823)
	var copy = Sim.new(823)
	check(sim.player.membrane.skeleton.links == copy.player.membrane.skeleton.links,"Simulation seed determines starting anatomy")
	var signatures := {}
	for cell in sim.cells: signatures[cell.membrane.skeleton.links.hash()] = true
	check(signatures.size() > 5,"Cells in one habitat receive different initial networks")

func _observation() -> void:
	var sim = Sim.new(73)
	var state: int = sim.rng.state
	var time: float = sim.time
	var particles: Array = sim.particles.duplicate(true)
	var cell = sim.player
	var anatomy: Array = cell.organs.duplicate(true)
	var score := Score.new()
	score.observe(sim,cell.position,Vector2(600,380),false)
	check(score.sources.size() > 0 and score.sources.size() <= 6 and score.channels.size() == 7,"Music bounds its ecosystem layers to six audible cells")
	check(sim.rng.state == state and sim.time == time and sim.particles == particles and cell.organs == anatomy,"Musical observation cannot mutate chemistry, anatomy, time or ecology RNG")
	var close := Score.proximity(Vector2.ZERO,Vector2(600,380),70)
	var edge := Score.proximity(Vector2(620,0),Vector2(600,380),70)
	var off := Score.proximity(Vector2(800,0),Vector2(600,380),70)
	check(close > edge and edge > 0 and off == 0,"A large entering body starts quiet and grows louder toward the viewer center")
	score.observe(sim,Sim.Medium.wrap_position(cell.position+Vector2(400,0)),Vector2(600,380),false)
	var player_source := {}
	for source in score.sources:
		if source.id == cell.id: player_source = source
	check(not player_source.is_empty() and player_source.pan < 0,"Stereo placement follows the viewer rather than player position")
	score.observe(sim,cell.position,Vector2(600,380),true)
	check(score.paused and score.channels[0].gain < 0.5,"Editing softens the music without advancing the run")
	score.mass = 100
	score.events(0,1)
	var high := score.transpose
	score.mass = 1600
	score.events(0,1)
	check(score.transpose < high,"Growing biomass lowers the tonal register")

func _schedule() -> void:
	var score := Score.new()
	var counts := PackedFloat32Array()
	counts.resize(Score.KINDS.size())
	counts.fill(1)
	var mounts := {}
	for i in Score.KINDS.size(): mounts[Score.KINDS[i]] = i
	score.sources = [{"id":0,"lane":1,"gain":1.0,"mass":160.0,"counts":counts,"mounts":mounts}]
	score.lead_id = 0
	var heard := {}
	var regions := {}
	var bounded := true
	for step in 16*64:
		var at := roundi(step*Synth.RATE*60.0/Synth.BPM/4)
		for event in score.events(at,roundi(Synth.RATE*60.0/Synth.BPM/4)):
			heard[event.instrument] = true
			bounded = bounded and event.lane >= 0 and event.lane < 7 and event.gain <= 1
		regions[Score.section(step/16)] = true
	check(bounded,"Musical events respect channel and gain limits")
	var complete := true
	for kind in range(4,14): complete = complete and heard.has(kind)
	check(complete and heard.has(16) and regions.size() == 6,"All organ timbres can sing across a six-section progressive arrangement")
	var a := Score.new()
	var b := Score.new()
	var whole: Array = a.events(0,22050)
	var chunks: Array = []
	var start := 0
	for amount in [173,921,2048,777,5000,13131]:
		for event in b.events(start,amount):
			var absolute: Dictionary = event.duplicate()
			absolute.offset += start
			chunks.append(absolute)
		start += amount
	check(whole == chunks,"Note onsets are sample-accurate across arbitrary frame-sized chunks")

func _mixer(bank: Array) -> void:
	var script := Synth.new()
	script.configure(bank)
	var score := Score.new()
	var channels: Array = score.channels.duplicate(true)
	channels[1] = {"id":10,"gain":0.65,"pan":0.6}
	var events: Array = []
	for i in Synth.LENGTH.size(): events.append({"offset":i*43,"instrument":i,"lane":1,"note":Synth.BASE_NOTE[i],"gain":0.15})
	var expected: PackedVector2Array = script.render(2048,events,channels,0.65)
	var peak := 0.0
	var rms := 0.0
	var stereo := false
	var finite := true
	for sample in expected:
		finite = finite and sample.is_finite()
		peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		rms += sample.length_squared()
		stereo = stereo or not is_equal_approx(sample.x,sample.y)
	check(finite,"Reference music mixer produces finite stereo samples")
	check(peak < 0.88 and rms/expected.size() > 0.0001 and stereo,"Mixed music is audible, stereo and headroom-limited")
	var over: Array = []
	for i in 100: over.append({"offset":0,"instrument":15,"lane":1,"note":36,"gain":1.0})
	script.render(512,over,channels,1)
	check(script.peak_voices <= Synth.MAX_VOICES and script.dropped > 0,"Dense anatomy cannot exceed the music voice budget")
	if OS.get_environment("PRIMORDIA_BACKEND") != "script" and ClassDB.class_exists("PrimordiaMusicMixer"):
		var native = ClassDB.instantiate("PrimordiaMusicMixer")
		native.configure(bank)
		var actual: PackedVector2Array = native.render(2048,events,channels,0.65)
		var error := 0.0
		for i in actual.size(): error = maxf(error,actual[i].distance_to(expected[i]))
		check(error < 0.00002,"Native music mixer agrees with the reference sampler")
		native.render(512,over,channels,1)
		check(native.metrics().peak_voices <= Synth.MAX_VOICES and native.metrics().dropped > 0,"Native music budget also bounds dense anatomy")
		check(native.render(0,[],[],0).is_empty(),"Native mixer rejects an empty render request safely")

func _preferences() -> void:
	var pref = preload("res://scripts/preferences.gd").new()
	pref.path = "user://music-test-preferences.cfg"
	pref.music_volume = 0.31
	pref.save_settings()
	var read = preload("res://scripts/preferences.gd").new()
	read.path = pref.path
	read.load_settings()
	check(is_equal_approx(read.music_volume,0.31),"Music volume persists without a particle beat setting")
	var config := ConfigFile.new()
	config.load(pref.path)
	check(not config.has_section_key("display","beat_pulse"),"Saved settings remove the obsolete particle beat control")
	DirAccess.remove_absolute(pref.path)
