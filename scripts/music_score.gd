extends RefCounted
## Read-only musical observations. Rhythm is scheduled in audio sample frames.
const Synth = preload("res://scripts/music_synth.gd")
const KINDS := ["propulsion","protection","offensive","regenerative","feeding","sensing","photosynthesis","toxin","neutralizing","acidifying","hunting"]
const INSTRUMENTS := [4,5,6,7,8,9,10,11,12,13,9]
const PATTERNS := [
	[2,6,10,14], [0,7,12], [0,3,6,10,14], [3,11],
	[0,3,8,10,14], [1,4,9,12], [0,2,5,8,10,13], [3,6,11,14], [5,13], [0,3,7,10,15], [2,5,8,14]
]
const DEGREES := [0,7,0,12,3,10,7,0,12,3,5]
const ROOTS := [0,8,3,10]
var sources: Array = []
var channels: Array = []
var paused := false
var terminal := false
var mass := 100.0
var transpose := 0
var observed_usec := 0
var cells_considered := 0
var intensity := 0.3
var lead_id := -1
var journal_world := 0
var journal_sequence := 0
var pending: Array = []
var scheduled: Array = []
var cue_cooldown: Dictionary = {}
const CUE_PRIORITY := {"feeding":0,"neutralize":1,"division":2}
const MOTIF_BEATS := [0,3,6,10,12,15]

static func lineage_motif(seed_value: int, lineage: int) -> Array:
	# A private RNG cannot perturb the ecology's random stream.
	var identity := RandomNumberGenerator.new()
	identity.seed = seed_value*65537+lineage*104729
	var contour: Array = [0,7,12,3,10,7]
	# Preserve a tonal opening/resolution; vary the middle of the family phrase.
	for i in range(1,5): contour[i] = [0,3,5,7,10,12][identity.randi_range(0,5)]
	return contour

func clear_accents() -> void:
	pending.clear()
	scheduled.clear()
	cue_cooldown.clear()

func reset_accents(world) -> void:
	clear_accents()
	journal_world = world.get_instance_id()
	journal_sequence = world.sound_sequence

func _init() -> void:
	for i in 7: channels.append({"id":-1,"gain":0.0,"pan":0.0})
	channels[0] = {"id":-2,"gain":0.8,"pan":0.0}

static func proximity(offset: Vector2, half: Vector2, radius: float) -> float:
	# Let the edge of a large body announce its arrival before its center enters.
	var edge := (offset.abs()-Vector2.ONE*radius).max(Vector2.ZERO)/half
	if edge.x >= 1 or edge.y >= 1: return 0
	var distance := (offset/half).length()/maxf(1,1+radius/minf(half.x,half.y)*0.4)
	return pow(clampf(1-distance/1.3,0,1),1.65)

func observe(world, camera: Vector2, half: Vector2, editing: bool) -> void:
	var started := Time.get_ticks_usec()
	paused = editing
	terminal = world.player.dead or world.evolution.terminal()
	mass = world.player.organic_mass()
	var candidates: Array = []
	cells_considered = 0
	for cell in world.cells:
		if cell.dead: continue
		cells_considered += 1
		var offset: Vector2 = world.Medium.offset(camera,cell.position)
		var gain := proximity(offset,half,cell.extent())
		if gain < 0.005: continue
		var counts := PackedFloat32Array()
		counts.resize(KINDS.size())
		for organ in cell.organs:
			var kind := KINDS.find(organ.kind)
			if kind >= 0: counts[kind] += 0.35+0.65*clampf(organ.hp/maxf(organ.max_hp,0.01),0,1)
		var weight: float = cell.organic_mass()
		candidates.append({"id":cell.id,"gain":gain,"pan":clampf(offset.x/half.x,-0.85,0.85),"mass":weight,"counts":counts,"offset":offset,"radius":cell.extent(),"rank":gain*(1+minf(2,weight/180)*0.3),"motif":lineage_motif(world.seed_value,cell.lineage_id()),"light":world.light_at(cell.position),"acid":world.acidity.sample(cell.position)})
	candidates.sort_custom(func(a,b): return a.rank > b.rank if not is_equal_approx(a.rank,b.rank) else a.id < b.id)
	if candidates.size() > 6:
		var player_source := {}
		for source in candidates:
			if source.id == world.player.id: player_source = source
		candidates.resize(6)
		if not player_source.is_empty() and not candidates.has(player_source):
			candidates[5] = player_source
	# Stable channels prevent a distance-order swap from moving an existing voice.
	var occupied: Array[int] = []
	for source in candidates:
		for lane in range(1,7):
			if channels[lane].id == source.id:
				source["lane"] = lane
				occupied.append(lane)
				break
	for source in candidates:
		if source.has("lane"): continue
		for lane in range(1,7):
			if not occupied.has(lane):
				source["lane"] = lane
				occupied.append(lane)
				break
	for lane in range(1,7): channels[lane] = {"id":-1,"gain":0.0,"pan":0.0}
	var balance := 1.0/sqrt(maxf(1,candidates.size()*0.7))
	intensity = 0.2
	for source in candidates:
		channels[source.lane] = {"id":source.id,"gain":source.gain*balance*(0.50 if editing else 0.85),"pan":source.pan,"light":source.light,"acid":source.acid}
		intensity = maxf(intensity,minf(1,source.gain*(source.counts[2]+source.counts[7])*0.5))
	channels[0] = {"id":-2,"gain":0.28 if terminal else 0.42 if editing else 0.80,"pan":0.0,"light":world.light_at(camera),"acid":world.acidity.sample(camera)}
	sources = candidates
	lead_id = sources[0].id if not sources.is_empty() else -1
	for source in sources:
		if source.id == world.player.id: lead_id = source.id
	_observe_accents(world,camera,half)
	observed_usec = Time.get_ticks_usec()-started

func _observe_accents(world, camera: Vector2, half: Vector2) -> void:
	if journal_world != world.get_instance_id():
		journal_world = world.get_instance_id()
		journal_sequence = world.sound_sequence
		clear_accents()
		return
	var fresh: Array = []
	for event in world.sound_events:
		if event.sequence > journal_sequence: fresh.append(event)
	journal_sequence = world.sound_sequence
	if paused or terminal:
		clear_accents()
		return
	fresh.sort_custom(func(a,b): return a.sequence < b.sequence)
	for event in fresh:
		if world.time-event.time > 1.0: continue
		var distance: Vector2 = world.Medium.offset(camera,event.at)
		var gain := proximity(distance,half,0)
		if gain < 0.04: continue
		var lane := 0
		for source in sources:
			if source.id == event.source:
				lane = source.lane
				break
		queue_accent(event.kind,lane,gain*minf(1.3,sqrt(maxf(0.2,event.amount))))

func queue_accent(kind: String, lane: int, gain: float) -> void:
	if not CUE_PRIORITY.has(kind) or lane < 0 or lane >= channels.size(): return
	for cue in pending:
		if cue.kind == kind and cue.lane == lane and cue.id == channels[lane].id:
			cue.gain = maxf(cue.gain,clampf(gain,0,1.3))
			return
	pending.append({"kind":kind,"lane":lane,"id":channels[lane].id,"gain":clampf(gain,0,1.3)})
	pending.sort_custom(func(a,b): return CUE_PRIORITY[a.kind] > CUE_PRIORITY[b.kind])
	if pending.size() > 12: pending.resize(12)

func _schedule_accents(start: int, interval: float) -> void:
	var accepted := 0
	for cue in pending:
		if accepted >= 3 or scheduled.size() > 20: break
		if channels[cue.lane].id != cue.id: continue
		var key: String = cue.kind+":"+str(cue.lane)
		if start < cue_cooldown.get(key,0): continue
		var unit := 4 if cue.kind == "division" else 2 if cue.kind == "neutralize" else 1
		var step := ceili(start/(interval*unit))*unit
		# Rounding must never place the cue behind the render cursor.
		if roundi(step*interval) < start: step += unit
		var chord := (step/16/2)%4
		var root: int = 50+ROOTS[chord]-mini(12,maxi(0,floori(log(maxf(100,mass)/100)/log(2)))*3)
		var third := 3 if chord == 0 else 4
		var notes: Array = [0,7] if cue.kind == "feeding" else [7,12] if cue.kind == "neutralize" else [7,third,0,12]
		var instrument := 8 if cue.kind == "feeding" else 12 if cue.kind == "neutralize" else 7
		for n in notes.size():
			scheduled.append({"at":roundi((step+n*unit)*interval),"instrument":instrument,"lane":cue.lane,"id":cue.id,"note":root+12+notes[n],"gain":cue.gain*(0.27 if cue.kind == "feeding" else 0.32),"accent":cue.kind})
		cue_cooldown[key] = start+roundi(Synth.RATE*(0.55 if cue.kind == "feeding" else 1.0))
		accepted += 1
	pending.clear()

static func section(bar: int) -> String:
	var at := posmod(bar,64)
	if at < 8: return "emerge"
	if at < 24: return "groove"
	if at < 32: return "lift"
	if at < 40: return "break"
	if at < 48: return "build"
	return "return"

func _note(out: Array, offset: int, instrument: int, lane: int, note: int, gain: float) -> void:
	out.append({"offset":offset,"instrument":instrument,"lane":lane,"note":note,"gain":gain})

func events(start: int, frames: int) -> Array:
	var out: Array = []
	var interval := Synth.RATE*60.0/Synth.BPM/4
	_schedule_accents(start,interval)
	# Integer sample onsets; a little authored sixteenth swing cannot drift.
	var first := maxi(0,floori(start/interval)-1)
	var last := ceili((start+frames)/interval)
	for step in range(first,last+1):
		var sample := roundi((step+(0.055 if step%2 else 0.0))*interval)
		if sample < start or sample >= start+frames: continue
		_step(out,step,sample-start)
	for n in range(scheduled.size()-1,-1,-1):
		var cue: Dictionary = scheduled[n]
		if cue.at < start or channels[cue.lane].id != cue.id:
			scheduled.remove_at(n)
		elif cue.at < start+frames:
			var note: Dictionary = cue.duplicate()
			note["offset"] = cue.at-start
			out.append(note)
			scheduled.remove_at(n)
	out.sort_custom(func(a,b): return a.offset < b.offset)
	return out

func _step(out: Array, step: int, offset: int) -> void:
	var bar := step/16
	var beat := step%16
	var part := section(bar)
	if beat == 0: transpose = -mini(12,maxi(0,floori(log(maxf(100,mass)/100)/log(2)))*3)
	var chord := (bar/2)%4
	var root: int = 50+ROOTS[chord]+transpose # D minor / B-flat / F / C.
	var third := 3 if chord == 0 else 4
	var broken := part == "break" or paused or terminal
	var opening := part == "emerge" and bar%8 < 4
	if not terminal and beat%4 == 0 and (not broken or beat in [0,8]):
		_note(out,offset,0,0,36,0.82 if not broken else 0.40)
	if not broken and not opening:
		if beat in [4,12]: _note(out,offset,2,0,60,0.50)
		if beat%2 == 0 or (part in ["lift","return"] and beat in [7,15]):
			_note(out,offset,1,0,60,0.22 if beat%4 == 2 else 0.12)
		if bar%8 == 7 and beat in [13,14,15]: _note(out,offset,2,0,60,0.13+beat*0.009)
	if not terminal and beat in ([2,10] if broken or opening else [2,6,10,14]):
		_note(out,offset,3,0,maxi(26,root-12),0.49)
	if beat == 0 and bar%2 == 0:
		for degree in [0,third,7]:
			_note(out,offset,14,0,root+12+degree,0.14 if broken else 0.095)
	# The family melody persists through division; anatomy chooses its voice.
	if not terminal and beat in MOTIF_BEATS and (not broken or beat in [0,10]):
		for source in sources:
			if source.id != lead_id: continue
			var instruments: Array[int] = []
			for kind in KINDS.size():
				if source.counts[kind] > 0: instruments.append(INSTRUMENTS[kind])
			if instruments.is_empty(): break
			var motif: Array = source.motif if source.has("motif") else lineage_motif(0,source.id)
			var degree: int = motif[MOTIF_BEATS.find(beat)]
			if degree == 3: degree = third
			var instrument: int = instruments[(bar/2)%instruments.size()]
			_note(out,offset,instrument,source.lane,root+12+degree,0.30 if part in ["lift","return"] else 0.23)
			out[-1]["theme"] = true
			break
	var allowance := 6
	for source in sources:
		if source.mass > 120 and beat == 0:
			var low := maxi(26,root-12-mini(12,floori(log(source.mass/120)/log(2))*4))
			_note(out,offset,15,source.lane,low,minf(0.36,0.16+log(source.mass/100)*0.08))
		var hits := 0
		for shift in KINDS.size():
			var kind := (shift+step/4)%KINDS.size()
			var count: float = source.counts[kind]
			if count <= 0 or not beat in PATTERNS[kind]: continue
			if source.gain < 0.25 and beat%4 != 0: continue
			if broken and beat not in [0,8,11,13]: continue
			if allowance <= 0 or hits >= (2 if source.gain > 0.5 else 1): break
			var register := -12*clampi(floori(log(maxf(1,source.mass/100))/log(4)),0,2)
			var degree: int = DEGREES[kind]
			if kind == 4: degree = [0,third,7,12][(step/2+source.id)%4]
			if kind == 6: degree = [0,7,12,third+12][(step/2+bar)%4]
			if kind == 9: degree = [0,7,third,12][(step+bar)%4]
			var note := clampi(root+12+register+degree,29,88)
			var gain := 0.25*minf(1.6,sqrt(count))*(0.72 if opening else 1.0)
			_note(out,offset,INSTRUMENTS[kind],source.lane,note,gain)
			allowance -= 1
			hits += 1
