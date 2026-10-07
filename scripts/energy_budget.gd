extends RefCounted
## Read-only accounting: 12 quarter-second bins, never gameplay state or RNG.
const WINDOW := 3.0
var samples: Array[Dictionary] = []
var started_at := -1.0
var enabled := true

func record(clock: float, produced: float, stored: float, spent: float, organ_id: int, category: String, shares: Dictionary = {}) -> void:
	if not enabled: return
	if started_at < 0: started_at = clock
	var epoch := floori(clock*4)
	while not samples.is_empty() and samples[0].epoch < epoch-11: samples.pop_front()
	if samples.is_empty() or samples[-1].epoch != epoch:
		samples.append({"epoch":epoch,"produced":0.0,"stored":0.0,"spent":0.0,"organs":{},"categories":{}})
	var bucket: Dictionary = samples[-1]
	bucket.produced += produced
	bucket.stored += stored
	bucket.spent += spent
	if spent > 0:
		var total := 0.0
		for value in shares.values(): total += maxf(0,float(value))
		if total > 0:
			for key in shares: bucket.organs[key] = bucket.organs.get(key,0.0)+spent*maxf(0,float(shares[key]))/total
		else: bucket.organs[organ_id] = bucket.organs.get(organ_id,0.0)+spent
		bucket.categories[category] = bucket.categories.get(category,0.0)+spent

func rates(clock: float) -> Dictionary:
	var duration := clampf(clock-maxf(0,started_at),0.25,WINDOW)
	var result := {"production":0.0,"stored":0.0,"spent":0.0,"organs":{},"categories":{},"seconds":duration,"sampled":false}
	var epoch := floori(clock*4)
	for bucket in samples:
		if bucket.epoch < epoch-11: continue
		result.sampled = true
		result.production += bucket.produced/duration
		result.stored += bucket.stored/duration
		result.spent += bucket.spent/duration
		for key in bucket.organs: result.organs[key] = result.organs.get(key,0.0)+bucket.organs[key]/duration
		for key in bucket.categories: result.categories[key] = result.categories.get(key,0.0)+bucket.categories[key]/duration
	result.net = result.production-result.spent
	result.reserve_net = result.stored-result.spent
	result.overflow = maxf(0,result.production-result.stored)
	return result
