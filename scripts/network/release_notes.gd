extends RefCounted
## Append player-facing releases in publication order. Never replace old entries.
const RELEASES=[
{
	"id":"2026-10-16-clearer-pond",
	"title":"What’s new in the pond",
	"items":[
		"Pause now includes Gameplay for your controls and Mechanics for the science behind the pond.",
		"Excess particles now gradually disperse, helping keep crowded ponds manageable.",
		"The information overlay now shows particle counts for the whole pond and your current view.",
		"Fixed a chemistry issue that could slow the world down.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-16-readable-panels",
	"title":"What’s new in the pond",
	"items":[
		"Fixed the blank update message. You can close it straight away and return to your cell.",
		"Gameplay and Mechanics now use readable, scrollable pages on phones and computers.",
		"Missed several updates? Their messages now appear in order until you have cleared them all.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-16-smoother-motion",
	"title":"What’s new in the pond",
	"items":[
		"Cells, particles and the Follow view move more smoothly when your connection is uneven.",
		"Pause holds the view where you left it. Resume returns you to the live pond.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-16-diffuse-light",
	"title":"What’s new in the pond",
	"items":[
		"Sunlit and shady water now form broad, soft-edged patches with irregular shapes.",
		"Light varies more naturally across the pond, giving photosynthetic cells different places to explore.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-16-rippling-sunlight",
	"title":"What’s new in the pond",
	"items":[
		"Sunlit water is much brighter, with deeper shade and soft, irregular edges.",
		"Rippling ribbons of light now shimmer through sunny patches.",
		"Removed the repeated glow spots that made the light look like a grid.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-16-experimental-pond",
	"title":"What’s new in the pond",
	"items":[
		"The experimental pond is a separate place to try new features.",
		"Your cells and progress here stay separate from the main pond.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-16-pond-feedback",
	"title":"What’s new in the pond",
	"items":[
		"Start a new lineage from Pause. Your former family stays in the pond under computer control.",
		"Toxin glands and assembled pores are less deadly.",
		"Returning from a cell’s interior keeps your zoom within the pond view limits.",
		"Following, recentering and switching cells now glide smoothly into place.",
		"Gentle eddies stir the water. Gold marks only the water right around their sources.",
		"Pore-forming particles now build visibly from a membrane tag into a complete pore.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-16-more-pond-currents",
	"title":"What’s new in the pond",
	"items":[
		"Spiral eddies and directional currents now travel through the pond in short bursts, with at least one always active.",
		"Plants still soften passing currents, with half their previous damping.",
		"Gold still marks only the water near a current source.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-17-camera-particles",
	"title":"What’s new in the pond",
	"items":[
		"Nearby particles arrive ahead of your camera, reducing empty patches while you explore.",
		"Your view keeps updating while other parts of the pond prepare.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
]
const CURRENT=RELEASES[-1]
static func seen_index(account: Dictionary) -> int:
	for i in RELEASES.size():
		if RELEASES[i].id==account.get("seen_release",""):return i
	return -1
static func pending_all(account: Dictionary) -> Array:
	return RELEASES.slice(seen_index(account)+1).duplicate(true)
static func pending(account: Dictionary) -> Dictionary:
	var updates:=pending_all(account)
	return {} if updates.is_empty() else updates[0]
static func acknowledge(account: Dictionary,id) -> bool:
	if not id is String:return false
	for i in RELEASES.size():
		if RELEASES[i].id!=id:continue
		var seen:=seen_index(account)
		if i<=seen:return true # Duplicate acknowledgements cannot move backwards.
		if i!=seen+1:return false
		account.seen_release=id;return true
	return false
