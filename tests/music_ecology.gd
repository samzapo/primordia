extends RefCounted
const Sim = preload("res://scripts/simulation.gd")
const Score = preload("res://scripts/music_score.gd")
const Synth = preload("res://scripts/music_synth.gd")
var host
func check(ok: bool, message: String) -> void: host.expect(ok,message)

func run(test_host, bank: Array) -> void:
	host = test_host
	_lineage_and_events()
	_cue_bounds()
	_timbre(bank)

func _isolated():
	var world = Sim.new(73)
	world.cells = [world.player]
	world.particles.clear()
	world.pheromones.clear()
	world.habitat_geometry.enabled = false
	world.grid.rebuild(world.particles)
	return world

func _lineage_and_events() -> void:
	var world = _isolated()
	var parent = world.player
	var score := Score.new()
	score.observe(world,parent.position,Vector2(600,380),false)
	var original: Array = score.sources[0].motif.duplicate()
	var variants := {}
	for family in 32: variants[Score.lineage_motif(73,family).hash()] = true
	check(variants.size() > 24,"Seeded families have distinct, repeatable musical contours")
	for i in 8:
		var neighbor = world._make_cell(parent.position+Vector2(i,0),"grazer")
		neighbor.biomass = 700
		neighbor.update_geometry()
		world.cells.append(neighbor)
	score.observe(world,parent.position,Vector2(600,380),false)
	check(score.sources.size() == 6 and score.lead_id == parent.id,"Crowded giant neighbors cannot displace the visible player's family theme")
	world.cells = [parent]
	parent.substrate=1 # A real food vacuole supplies its anatomical instrument.
	score.observe(world,parent.position,Vector2(600,380),false)
	check(original == Score.lineage_motif(73,parent.lineage_id()),"Observed melody uses the inherited lineage signature")
	var melody_before: Array = []
	for event in score.events(0,42000):
		if event.has("theme"): melody_before.append(event.note)
	parent.add_organ("neutralizing",2.8,"graze",false)
	score.observe(world,parent.position,Vector2(600,380),false)
	var melody_after: Array = []
	var instruments := {}
	for event in score.events(0,360000):
		if event.has("theme"):
			instruments[event.instrument] = true
			if event.offset < 42000: melody_after.append(event.note)
	check(melody_before == melody_after and instruments.size() > 1,"Anatomy changes orchestration while retaining the family melody")
	var player_lane: int = score.sources[0].lane
	check(is_equal_approx(score.channels[player_lane].light,world.light_at(parent.position)),"Local habitat light drives the organism's filter")
	world.acidity.values.fill(0.8)
	score.observe(world,parent.position,Vector2(600,380),false)
	var acidic: float = score.channels[player_lane].acid
	world.spawn_particle(Sim.BUFFER,parent.position,Vector2.ZERO,2,parent.id)
	world._chemistry(1.0)
	score.observe(world,parent.position,Vector2(600,380),false)
	check(score.channels[player_lane].acid < acidic,"A real buffer reaction reduces the acidity heard at the cell")
	world.particles.clear()
	world.grid.rebuild(world.particles)
	parent.organs.clear()
	parent.add_organ("feeding",0,"graze",false)
	parent.substrate = 0
	world.spawn_particle(Sim.NUTRIENT,parent.pore_center(parent.organs[0]))
	world._feed(parent)
	check(world.sound_events[-1].kind == "feeding" and parent.eaten > 0,"Actual nutrient intake emits a feeding accent")
	world.time += 0.2
	world.particles.clear()
	world.grid.rebuild(world.particles)
	world.spawn_particle(Sim.ANTITOXIN,parent.position,Vector2.ZERO,0.5,parent.id)
	world.spawn_particle(Sim.TOXIN,parent.position+Vector2.RIGHT*2,Vector2.ZERO,0.5,17)
	world.particles[0].direction = Vector2.RIGHT
	world.particles[1].direction = Vector2.LEFT
	world._chemistry(0.00001)
	check(world.chemistry_events.neutralize == 1 and world.sound_events[-1].kind == "neutralize","Actual oriented toxin neutralization emits an answering accent")
	parent.biomass = 300
	parent.energy = 90
	parent.biomass=300;parent.energy=100;parent.reproduction_retry_at=0
	parent.brood_energy = 0
	parent.oxygen = 20
	check(world.divide_lineage(),"Music inheritance fixture completes a real funded division")
	var snapshot: Array = world.sound_events.duplicate(true)
	var rng_state: int = world.rng.state
	score.observe(world,world.player.position,Vector2(600,380),false)
	var child_source := {}
	for source in score.sources:
		if source.id == world.player.id: child_source = source
	check(child_source.motif == original and score.lead_id == world.player.id,"Offspring inherits its parent's melody and takes over the foreground voice")
	var accents := {}
	for event in score.events(400001,50000):
		if event.has("accent"): accents[event.accent] = true
	check(accents.is_empty(),"Habitat events cannot produce an anonymous backing phrase")
	check(world.sound_events == snapshot and world.rng.state == rng_state,"Reading the bounded audio journal never consumes events or ecology randomness")
	score.observe(world,world.player.position,Vector2(600,380),false)
	check(score.pending.is_empty(),"Repeated observation does not replay prior reactions")
	var late := Score.new()
	late.observe(world,world.player.position,Vector2(600,380),false)
	check(late.pending.is_empty(),"Attaching audio to an existing run skips historical actions")

func _cue_bounds() -> void:
	var world = _isolated()
	var score := Score.new()
	score.observe(world,world.player.position,Vector2(600,380),false)
	world._record_sound("feeding",world.player.position+Vector2(1400,0),43)
	score.observe(world,world.player.position,Vector2(600,380),false)
	check(score.pending.is_empty(),"Offscreen reactions cannot produce event accents")
	world._record_sound("feeding",world.player.position,44)
	world.time += 2
	score.observe(world,world.player.position,Vector2(600,380),false)
	check(score.pending.is_empty(),"Stale reaction history cannot produce delayed bursts")
	for i in 300:
		world.time += 0.11
		world._record_sound("feeding",world.player.position,i)
	check(world.sound_events.size() == 64 and world.sound_recent.size() <= 64,"Long runs retain at most 64 presentation events and coalescing keys")
	score.observe(world,world.player.position,Vector2(600,380),true)
	check(score.pending.is_empty() and score.scheduled.is_empty(),"Editing discards habitat accents while retaining anatomical voices")
	score.paused = false
	world.time += 0.2
	world._record_sound("neutralize",world.player.position,world.player.id)
	score.reset_accents(world)
	score.observe(world,world.player.position,Vector2(600,380),false)
	check(score.pending.is_empty(),"Unmute discards even actions since the last audio observation")
	var a := Score.new()
	var b := Score.new()
	for target in [a,b]:
		for kind in ["feeding","neutralize","division"]: target.queue_accent(kind,0,1)
	var whole := a.events(173,22050)
	var chunks: Array = []
	var cursor := 173
	for amount in [173,921,2048,777,5000,13131]:
		for event in b.events(cursor,amount):
			var absolute: Dictionary = event.duplicate()
			absolute.offset += cursor-173
			chunks.append(absolute)
		cursor += amount
	check(whole == chunks,"Quantized event phrases are identical across arbitrary audio block boundaries")
	for i in 1000:
		for kind in ["feeding","neutralize","division"]: score.queue_accent(kind,i%7,1)
	check(score.pending.size() <= 12,"Dense reaction bursts have a bounded, coalesced pending queue")
	score.events(1,20)
	check(score.scheduled.size() <= 24,"Burst scheduling never creates an unbounded note backlog")
	score.clear_accents()
	check(score.pending.is_empty() and score.scheduled.is_empty() and score.cue_cooldown.is_empty(),"Mute and restart can clear pending notes and old sample deadlines")
	score.channels[1].id = 42
	score.queue_accent("division",1,1)
	score.events(1,20)
	score.channels[1].id = 99
	var accents := 0
	for event in score.events(21,22050):
		if event.has("accent"): accents += 1
	check(accents == 0,"An event phrase cannot follow a lane reassigned to a different organism")

func _timbre(bank: Array) -> void:
	var script := Synth.new()
	script.configure(bank)
	var native
	if OS.get_environment("PRIMORDIA_BACKEND") != "script" and ClassDB.class_exists("PrimordiaMusicMixer"):
		native = ClassDB.instantiate("PrimordiaMusicMixer")
		native.configure(bank)
	var channels: Array = Score.new().channels
	channels[1] = {"id":1,"gain":0.7,"pan":0.35,"light":0.0,"acid":0.0}
	var max_error := 0.0
	var maximum := 0.0
	for state in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0.2,0.1)]:
		channels[1].light = state.x
		channels[1].acid = state.y
		for block in 4:
			var events := [{"offset":13,"instrument":6,"lane":1,"note":72,"gain":0.6}]
			var expected: PackedVector2Array = script.render(1024,events,channels,0.7)
			var actual: PackedVector2Array = native.render(1024,events,channels,0.7) if native else expected
			for i in expected.size():
				max_error = maxf(max_error,expected[i].distance_to(actual[i]))
				maximum = maxf(maximum,maxf(absf(actual[i].x),absf(actual[i].y)))
	check(max_error < 0.00002,"Native and reference habitat filters agree through changing light, acidity and buffering")
	check(is_finite(maximum) and maximum < 0.88,"Environmental saturation remains finite and within the output headroom")
	# A fixed test signal lets us measure filtering rather than judge a melody.
	var fixture: Array = bank.duplicate()
	var tone := PackedFloat32Array()
	tone.resize(10000)
	for i in tone.size(): tone[i] = 0.20*sin(TAU*250*i/Synth.RATE)+0.15*sin(TAU*4000*i/Synth.RATE)
	fixture[6] = tone
	var energies: Array[float] = []
	var renders: Array = []
	for state in [Vector2(0,0),Vector2(1,0),Vector2(1,1)]:
		var test := Synth.new()
		test.configure(fixture)
		channels[1].light = state.x
		channels[1].acid = state.y
		var pcm := test.render(8192,[{"offset":0,"instrument":6,"lane":1,"note":60,"gain":0.6}],channels,0.7)
		var edge := 0.0
		for i in range(2049,8192): edge += (pcm[i]-pcm[i-1]).length_squared()
		energies.append(edge)
		renders.append(pcm)
	check(energies[1] > energies[0]*3,"Light audibly opens the filter by preserving more high-frequency energy")
	check(renders[1] != renders[2],"Acidity changes the waveform independently of light")
