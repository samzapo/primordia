extends RefCounted
## Authored synthesis recipes and a reference sampler. No simulation state.
const RATE := 22050
const MAX_VOICES := 40
const BPM := 128.0
const BASE_NOTE := [36,60,60,36,60,60,60,60,60,60,60,60,60,60,60,36]
const LENGTH := [0.42,0.09,0.20,0.42,0.48,0.82,0.38,1.25,0.55,0.50,0.92,0.64,1.10,0.46,2.30,2.20]
static var cached_bank: Array = []
var bank: Array = []
var voices: Array = []
var channels: Array = []
var cursor := 0
var delay_left := PackedFloat32Array()
var delay_right := PackedFloat32Array()
var delay_index := 0
var peak_voices := 0
var dropped := 0
var master := 0.0

static func make_bank() -> Array:
	var result: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1282026
	for instrument in LENGTH.size():
		var data := PackedFloat32Array()
		var count := ceili(LENGTH[instrument]*RATE)
		data.resize(count)
		var filtered := 0.0
		var noise_previous := 0.0
		for i in count:
			var t := float(i)/RATE
			var f := 440.0*pow(2,(BASE_NOTE[instrument]-69)/12.0)
			var p := TAU*f*t
			var noise := rng.randf_range(-1,1)
			var value := 0.0
			var attack := minf(1,t/0.006)
			var end := minf(1,(LENGTH[instrument]-t)/0.035)
			match instrument:
				0: # Rounded kick, swept body and a short click.
					var phase := TAU*(44*t+74*0.026*(1-exp(-t/0.026)))
					value = sin(phase)*exp(-t*10)+noise*exp(-t*160)*0.20
					attack = minf(1,t/0.0015)
				1: # High-passed noise hat, no external sample.
					value = (noise-noise_previous)*0.35*exp(-t*48)
					attack = minf(1,t/0.001)
				2: # Three short clap impulses over a soft snare body.
					var bursts := exp(-t*75)
					for offset in [0.011,0.023]:
						if t >= offset: bursts += exp(-(t-offset)*75)*0.6
					value = noise*bursts*0.55+sin(TAU*180*t)*exp(-t*32)*0.16
				3: value = (sin(p)+0.25*sin(p*2)+0.12*sin(p*3))*exp(-t*9)*0.72
				4: value = (sin(p)+0.35*sin(p*2)+0.18*sin(p*3))*exp(-t*7)*0.68 # Propulsion pluck.
				5: value = (sin(p)+0.22*sin(p*1.003)+0.25*sin(p*2))*exp(-t*4)*0.65 # Cortex brass.
				6: value = sin(p+2.4*exp(-t*12)*sin(p*2))*exp(-t*9)*0.75 # Spike acid bite.
				7: value = (sin(p)+0.35*sin(p*2.001)*exp(-t*5))*exp(-t*3.7)*0.64 # Repair bell.
				8: value = sin(p+1.2*exp(-t*18)*sin(p*3))*exp(-t*8)*0.80 # Feeding mallet.
				9: value = (sin(p)+0.25*sin(p*3)+0.10*sin(p*5))*exp(-t*8)*0.68 # Flight signal.
				10: value = (sin(p)+0.28*sin(p*2)+0.12*sin(p*4))*exp(-t*4.8)*0.65 # Light glass.
				11: value = sin(p+1.8*sin(p*0.5)*exp(-t*3))*exp(-t*5)*0.65 # Toxin growl.
				12: value = (sin(p)+0.18*sin(p*3))*exp(-t*3.4)*0.7 # Neutralizer chime.
				13: value = (sin(p)+sin(p*2)*exp(-t*15)*0.55+sin(p*3)*exp(-t*20)*0.3)*exp(-t*8)*0.6 # Acid chirp.
				14:
					value = (sin(p)+sin(p*1.004)*0.35+sin(p*0.998)*0.35+sin(p*2)*0.12)*0.39
					attack = minf(1,t/0.22)
					end = minf(end,(LENGTH[instrument]-t)/0.55)
				15:
					value = (sin(p)+0.26*sin(p*0.5)+0.23*sin(p*1.006))*0.63
					attack = minf(1,t/0.13)
					end = minf(end,(LENGTH[instrument]-t)/0.60)
			# A small smoothing filter keeps bright timbres rounded.
			filtered = lerpf(filtered,value,0.74 if instrument in [1,2] else 0.55)
			data[i] = filtered*attack*clampf(end,0,1)
			noise_previous = noise
		result.append(data)
	return result

func configure(samples: Array) -> void:
	bank = samples
	voices.clear()
	channels.clear()
	cursor = 0
	master = 0
	delay_index = 0
	peak_voices = 0
	dropped = 0
	delay_left.resize(roundi(RATE*60/BPM*0.75))
	delay_right.resize(delay_left.size())
	delay_left.fill(0)
	delay_right.fill(0)
	for i in 7: channels.append({"id":-99,"left":0.0,"right":0.0,"target_left":0.0,"target_right":0.0,"low":0.0,"filter":0.5,"target_filter":0.5,"acid":0.0,"target_acid":0.0})

func render(frames: int, events: Array, sources: Array, volume: float) -> PackedVector2Array:
	for lane in 7:
		var source: Dictionary = sources[lane] if lane < sources.size() else {"id":-1,"gain":0.0,"pan":0.0}
		var channel: Dictionary = channels[lane]
		if channel.id != source.id:
			for voice in voices:
				if voice.lane == lane: voice.release = mini(voice.release,roundi(RATE*0.035))
		channel.id = source.id
		var light := clampf(source.get("light",0.75),0,1)
		channel.target_filter = 1-exp(-TAU*(400+6100*pow(light,1.4))/RATE)
		channel.target_acid = clampf(source.get("acid",0.0),0,1)
		channel.target_left = source.gain*sqrt(0.5*(1-clampf(source.pan,-1,1)))
		channel.target_right = source.gain*sqrt(0.5*(1+clampf(source.pan,-1,1)))
	var output := PackedVector2Array()
	output.resize(frames)
	var tones := PackedFloat64Array()
	tones.resize(7)
	var event_index := 0
	for i in frames:
		while event_index < events.size() and events[event_index].offset <= i:
			var event: Dictionary = events[event_index]
			event_index += 1
			if voices.size() >= MAX_VOICES:
				dropped += 1
				continue
			var instrument: int = event.instrument
			voices.append({"instrument":instrument,"lane":event.lane,"position":0.0,"rate":pow(2,(event.note-BASE_NOTE[instrument])/12.0),"gain":event.gain,"release":2147483647})
		var dry := Vector2.ZERO
		var send := Vector2.ZERO
		tones.fill(0)
		var beat := fposmod(float(cursor+i)/RATE,60/BPM)
		var duck := 0.42+0.58*clampf(beat/0.18,0,1)
		for channel in channels:
			channel.left = lerpf(channel.left,channel.target_left,0.002)
			channel.right = lerpf(channel.right,channel.target_right,0.002)
			channel.filter = lerpf(channel.filter,channel.target_filter,0.0015)
			channel.acid = lerpf(channel.acid,channel.target_acid,0.0015)
		for n in range(voices.size()-1,-1,-1):
			var voice: Dictionary = voices[n]
			var samples: PackedFloat32Array = bank[voice.instrument]
			var index := int(voice.position)
			if index+1 >= samples.size() or voice.release <= 0:
				voices.remove_at(n)
				continue
			var value: float = lerpf(samples[index],samples[index+1],voice.position-index)*voice.gain
			value *= minf(1,voice.release/(RATE*0.035))
			voice.position += voice.rate
			voice.release -= 1
			var channel: Dictionary = channels[voice.lane]
			if voice.instrument >= 4:
				tones[voice.lane] += value*duck
			else:
				dry += Vector2(channel.left,channel.right)*value*(duck if voice.instrument == 3 else 1.0)
		# One filter per organism, rather than per voice; percussion stays crisp.
		var ripple := sin(TAU*6.4*(cursor+i)/RATE)
		for lane in 7:
			var channel: Dictionary = channels[lane]
			channel.low = lerpf(channel.low,tones[lane],channel.filter)
			var tone: float = channel.low
			var acid: float = channel.acid
			if acid > 0.001:
				tone = tanh(tone*(1+acid*2.5))/(1+acid*1.7)*(1+acid*0.045*ripple)
			var pair := Vector2(channel.left,channel.right)*tone
			dry += pair
			send += pair*0.18
		peak_voices = maxi(peak_voices,voices.size())
		var echo := Vector2(delay_left[delay_index],delay_right[delay_index])
		delay_left[delay_index] = send.x+echo.y*0.26
		delay_right[delay_index] = send.y+echo.x*0.26
		delay_index = (delay_index+1)%delay_left.size()
		master = lerpf(master,clampf(volume,0,1),0.0015)
		output[i] = Vector2(tanh((dry.x+echo.x)*0.9),tanh((dry.y+echo.y)*0.9))*0.88*master
	cursor += frames
	return output

func metrics() -> Dictionary:
	return {"cursor":cursor,"peak_voices":peak_voices,"voices":voices.size(),"dropped":dropped}
