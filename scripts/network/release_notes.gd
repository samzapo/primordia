extends RefCounted
## Append releases in publication order with an explicit shared/stable/experimental audience.
## Preserve historical IDs so filtering cannot invalidate saved acknowledgements.
const RELEASES=[
{
	"id":"2026-10-16-clearer-pond",
	"audience":"shared",
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
	"audience":"shared",
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
	"audience":"shared",
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
	"audience":"shared",
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
	"audience":"shared",
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
	"audience":"experimental",
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
	"audience":"shared",
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
	"audience":"shared",
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
	"audience":"shared",
	"title":"What’s new in the pond",
	"items":[
		"Nearby particles arrive ahead of your camera, reducing empty patches while you explore.",
		"Your view keeps updating while other parts of the pond prepare.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-17-pond-exploration",
	"audience":"stable",
	"title":"What’s new in the pond",
	"items":[
		"Explore more smoothly: nearby particles arrive ahead of your camera, and Follow glides into place.",
		"Moving eddies stir the pond, with gold marking their sources and plants softening their flow.",
		"Pores build visibly in stages, and toxin glands and pores are less deadly.",
		"Pause lets you start a new lineage while your former family carries on in the pond.",
	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
 "id":"2026-10-17-cell-investments",
 "hidden_items":[2], # Historical withdrawn-feature copy is retained, never offered again.
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "Photosynthetic cells keep most of their food inside and share a little with the pond. Build mitochondria to get more ATP from food and oxygen.",
  "Choose Hunter, Producer or Grazer investments in the nucleus for unattended relatives. Other cells now follow these strategies too.",
  "Try a Counterattack gland that spares unarmed cells, or Sanctuary to keep a cell alive without producing offspring.",
  "See your AP while building and check organelle recharge and energy needs more easily.",
  "Choose your lineage’s color in Pause, switch relatives without a camera jump, and browse your current family. Improved long-running pond reliability.",
 ],
 "footer":"Your cell and its progress carry on between updates.",
 "button":"Back to the pond",
},
{
 "id":"2026-10-17-clear-building",
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "Look for the teal chamber factory with its new rim and build symbol. Choose an internal organ from either view to go inside and place it.",
  "Pick Hunter, Producer or Grazer directly from three pictured cells in the Investment menu.",
  "Choose overlapping structures by their matching pictures, including both factories, the nucleus and resource stores.",
 ],
 "footer":"Your cell and its progress carry on between updates.",
 "button":"Back to the pond",
},
{
 "id":"2026-10-17-cell-instincts",
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "Cells now choose when to feed, hunt, rest or explore from their reserves and the signals their organs receive.",
  "Attacked cells retreat and use nearby family traces to spread out. Flight receptors also seek a way out of harmful acid.",
  "Shade leaves seek softer light, returning toward light when the water is too dark.",
  "Hunter, Producer and Grazer investments develop more varied, complementary organs.",
  "Removed Exploration, Steering and Output percentages. Your cell’s organs now guide these choices automatically.",
  "The Family menu shows living relatives, highest generation and total cells. Sanctuary is no longer available.",
 ],
 "footer":"This update starts a fresh pond. Your existing access key still works.",
 "button":"Back to the pond",
},
{
 "id":"2026-10-17-growing-new-builds",
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "Daughter cells begin with a basic oral groove and build their own organs, instead of receiving a copy of the parent’s build.",
  "Daughters inherit the parent’s Hunter, Producer or Grazer investment strategy. A Manual parent gives one of those three at random.",
  "Reproduction now funds the daughter’s basic body, without charging for the parent’s extra organs.",
  "Your first added organelle is free, the second costs 1 AP, the third 2 AP, and so on. Selling lowers the next price and returns the AP you paid minus 1 (at least 0).",
  "Selected investment choices now show a clear tick on phones.",
 ],
 "footer":"Your existing cells and their organs carry on between updates.",
 "button":"Back to the pond",
},
{
 "id":"2026-10-17-quarter-power",
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "Low ATP now slows movement, feeding currents, glands and active repair to a quarter of normal activity instead of stopping them.",
  "Weapons recharge more slowly while underpowered. Normal activity returns automatically as ATP recovers.",
  "Organs still need their usual materials and signals. Photosynthesis and digestion keep working to help the cell recover.",
 ],
 "footer":"Your cells and their progress carry on between updates.",
 "button":"Back to the pond",
},
{
 "id":"2026-10-17-family-pictures",
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "The family menu now shows each relative’s current cell, including its shape and organelles.",
  "A tiny corner number shows its generation. Choose a living relative’s picture to manage it.",
 ],
 "footer":"Your cells and their progress carry on between updates.",
 "button":"Back to the pond",
},
{
 "id":"2026-10-17-family-grid",
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "The family menu shows all living relatives in a larger grid. Scroll when your family needs more room.",
  "Choose a living relative directly, even if it’s outside your current view.",
  "Cells now divide into living daughters instead of storing offspring for later.",
 ],
 "footer":"Your cells and their progress carry on between updates.",
 "button":"Back to the pond",
},
{
 "id":"2026-10-17-stable-cell-families",
 "audience":"stable",
 "title":"What’s new in the pond",
 "items":[
  "Build mitochondria to make ATP from food and oxygen. Photosynthesis now keeps most of its food and shares a little with the pond.",
  "Choose Hunter, Producer or Grazer investments for unattended cells. Their senses and organelles guide how they feed, seek light, hunt and escape.",
  "Your first added organelle costs no AP, the next costs 1, then 2, and so on. Selling returns what you paid minus 1 AP, with a minimum of zero.",
  "Low on ATP? Powered organelles keep working at quarter strength while your cell recovers.",
  "Cells divide straight into living daughters with basic anatomy and an inherited investment strategy. Find every living relative in the larger family picture menu.",
  "Factories are easier to spot and use, organelle readiness is clearer, and you can choose your lineage’s color in Pause.",
 ],
 "footer":"Your living cells and their progress carry on between updates.",
 "button":"Back to the pond",
},
{
 "id":"2026-10-17-recycling",
 "audience":"stable",
 "title":"What’s new in the pond",
 "items":[
  "Recycling any added organelle returns the current build tier: four added organelles return 3 AP, three return 2, and one returns 0. The oral groove does not count.",
  "Recycling works while your cell is moving and updating. Its confirmation tells you how much AP came back.",
 ],
 "footer":"Your living cells and their progress carry on between updates.",
 "button":"Back to the pond",
},
]
const CURRENT=RELEASES[-1]
static func seen_index(account: Dictionary) -> int:
	for i in RELEASES.size():
		if RELEASES[i].id==account.get("seen_release",""):return i
	return -1
static func applies(update: Dictionary,instance: String) -> bool:
	var audience: String=update.get("audience","")
	return audience=="shared" or audience==instance
static func pending_all(account: Dictionary,instance: String="stable") -> Array:
	var updates: Array=[]
	for update in RELEASES.slice(seen_index(account)+1):
		if applies(update,instance):
			var visible: Dictionary=update.duplicate(true)
			var items: Array=[]
			for i in update.items.size():
				if i not in update.get("hidden_items",[]):items.append(update.items[i])
			visible.items=items;updates.append(visible)
	return updates
static func pending(account: Dictionary,instance: String="stable") -> Dictionary:
	var updates:=pending_all(account,instance)
	return {} if updates.is_empty() else updates[0]
static func acknowledge(account: Dictionary,id,instance: String="stable") -> bool:
	if not id is String:return false
	for i in RELEASES.size():
		if RELEASES[i].id!=id:continue
		if not applies(RELEASES[i],instance):return false
		var seen:=seen_index(account)
		if i<=seen:return true # Duplicate acknowledgements cannot move backwards.
		var updates:=pending_all(account,instance)
		if updates.is_empty() or updates[0].id!=id:return false
		account.seen_release=id;return true
	return false
