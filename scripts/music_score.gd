extends RefCounted
## Read-only musical observations. Rhythm is scheduled in audio sample frames.
const Synth = preload("res://scripts/music_synth.gd")
const KINDS := ["propulsion","protection","offensive","regenerative","feeding","sensing","photosynthesis","toxin","neutralizing","acidifying"]
const PATTERNS := [
	[2,6,10,14], [0,7,12], [0,3,6,10,14], [3,11],
	[0,3,8,10,14], [1,4,9,12], [0,2,5,8,10,13], [3,6,11,14], [5,13], [0,3,7,10,15]
]
const DEGREES := [0,7,0,12,3,10,7,0,12,3]
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
		counts.resize(10)
		for organ in cell.organs:
			var kind := KINDS.find(organ.kind)
			if kind >= 0: counts[kind] += 0.35+0.65*clampf(organ.hp/maxf(organ.max_hp,0.01),0,1)
		var weight: float = cell.organic_mass()
		candidates.append({"id":cell.id,"gain":gain,"pan":clampf(offset.x/half.x,-0.85,0.85),"mass":weight,"counts":counts,"offset":offset,"radius":cell.extent(),"rank":gain*(1+minf(2,weight/180)*0.3)})
	candidates.sort_custom(func(a,b): return a.rank > b.rank if not is_equal_approx(a.rank,b.rank) else a.id < b.id)
	if candidates.size() > 6: candidates.resize(6)
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
		channels[source.lane] = {"id":source.id,"gain":source.gain*balance*(0.50 if editing else 0.85),"pan":source.pan}
		intensity = maxf(intensity,minf(1,source.gain*(source.counts[2]+source.counts[7])*0.5))
	channels[0] = {"id":-2,"gain":0.28 if terminal else 0.42 if editing else 0.80,"pan":0.0}
	sources = candidates
	observed_usec = Time.get_ticks_usec()-started

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
	# Integer sample onsets; a little authored sixteenth swing cannot drift.
	var first := maxi(0,floori(start/interval)-1)
	var last := ceili((start+frames)/interval)
	for step in range(first,last+1):
		var sample := roundi((step+(0.055 if step%2 else 0.0))*interval)
		if sample < start or sample >= start+frames: continue
		_step(out,step,sample-start)
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
	# A returning hook supplies musical identity; the organism layers answer it.
	if not broken and part in ["lift","return"] and beat in [0,3,6,10,12,15]:
		var motif := [0,7,12,third,10,7]
		_note(out,offset,10,0,root+12+motif[[0,3,6,10,12,15].find(beat)],0.23)
	var allowance := 6
	for source in sources:
		if source.mass > 120 and beat == 0:
			var low := maxi(26,root-12-mini(12,floori(log(source.mass/120)/log(2))*4))
			_note(out,offset,15,source.lane,low,minf(0.36,0.16+log(source.mass/100)*0.08))
		var hits := 0
		for shift in 10:
			var kind := (shift+step/4)%10
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
			_note(out,offset,kind+4,source.lane,note,gain)
			allowance -= 1
			hits += 1
