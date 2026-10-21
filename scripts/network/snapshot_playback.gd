extends RefCounted
## Presentation only. Play captured poses on one monotonic host-time timeline.
## No prediction, chemistry steps or simulation random draws.
const MAX_FRAMES:=8
const MAX_DELAY:=2.0
var frames: Array=[]
var gaps: Array[float]=[]
var period:=0.1
var delay:=0.2
var cursor:=0.0
var last_sample:=-1.0
var last_arrival:=-1.0
var started:=false
var underruns:=0
var resyncs:=0

func reset() -> void:
	frames.clear();gaps.clear();period=0.1;delay=0.2
	cursor=0;last_sample=-1;last_arrival=-1;started=false

func push(frame: Dictionary,arrival: float) -> bool:
	var stamp:=float(frame.get("presentation_usec",float(frame.time)*1000000.0))/1000000.0
	if not is_finite(stamp):return false
	if not frames.is_empty():
		var previous: float=frames[-1].stamp
		if stamp<=previous:return false
		# A slow authority is not a suspended browser. Preserve its consecutive
		# captured endpoints instead of teleporting to every sparse arrival.
		var span:=clampf(stamp-previous,1.0/60,MAX_DELAY)
		period=span if gaps.is_empty() else lerpf(period,span,.125)
		gaps.append(clampf(arrival-last_arrival,0,MAX_DELAY))
		if gaps.size()>16:gaps.pop_front()
		var ordered:=gaps.duplicate();ordered.sort()
		delay=clampf(maxf(period*1.15+.05,ordered[int((ordered.size()-1)*.9)]*1.1),.12,MAX_DELAY)
	if frames.is_empty():cursor=stamp;last_sample=arrival
	frames.append({"stamp":stamp,"frame":frame})
	last_arrival=arrival
	while frames.size()>MAX_FRAMES:frames.pop_front()
	if cursor<float(frames[0].stamp):
		cursor=frames[0].stamp;resyncs+=1
	return true

func sample(now: float) -> Dictionary:
	if frames.is_empty():return {}
	var dt:=maxf(0,now-last_sample);last_sample=now
	if dt>1:
		cursor=frames[-1].stamp;started=false;resyncs+=1
	if not started and frames.size()>1 and float(frames[-1].stamp)-cursor>=delay*0.8:
		started=true;dt=0
	if started:
		var ahead: float=frames[-1].stamp-cursor
		# Small speed corrections refill/drain the buffer without snapping the camera.
		var rate:=clampf(1+(ahead-delay)*0.6,0.88,1.12)
		var next:=cursor+dt*rate
		if next>float(frames[-1].stamp) and cursor<float(frames[-1].stamp):underruns+=1
		cursor=minf(next,frames[-1].stamp)
	while frames.size()>2 and float(frames[1].stamp)<=cursor:frames.pop_front()
	var before: Dictionary=frames[0]
	var after: Dictionary=frames[1] if frames.size()>1 else before
	var span: float=after.stamp-before.stamp
	var alpha:=clampf((cursor-float(before.stamp))/span,0,1) if span>0 else 1.0
	return {"before":before.frame,"after":after.frame,"alpha":alpha}

func diagnostics() -> Dictionary:
	return {"buffered":frames.size(),"delay_ms":roundi(delay*1000),"period_ms":roundi(period*1000),"underruns":underruns,"resyncs":resyncs,"started":started}
