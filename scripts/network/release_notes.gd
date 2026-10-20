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
{
	"id":"2026-10-17-growing-families-and-toxin-sacs",
	"audience":"experimental",
	"title":"What’s new in the pond",
	"items":[
		"Families can grow beyond four cells. The ring around Divide shows progress and turns green when ready. The bud also opens Investment and Family.",
		"Toxin sacs store a little surplus biomass as toxin, then spill it into nearby water when the cell dies.",
		"Pore-forming attacks stay closer to their source. Pieces already on a membrane can still finish assembling.",
		"Each cell now keeps its own AP. Division gives 1 AP to the parent and 1 AP to the daughter.",
		"Investment starts on Manual for everyone. Chosen strategies can build or reabsorb organs at most once a minute per cell.",
		"Reabsorb returns AP to that cell. Installed organs stay where you built them.",

	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
	"id":"2026-10-17-stable-growing-families",
	"audience":"stable",
	"title":"What’s new in the pond",
	"items":[
		"Families can grow beyond four cells. The ring around Divide fills as your cell prepares and turns green when ready.",
		"Open the division bud or nucleus to choose Investment. The bud also opens Family.",
		"Toxin sacs store a little surplus biomass as toxin, then spill it into nearby water when the cell dies.",
		"Pore-forming attacks stay closer to their source. Pieces already on a membrane can still finish assembling.",
		"Each cell now keeps its own AP. Division gives 1 AP to the parent and 1 AP to the daughter.",
		"Investment starts on Manual for everyone. Chosen strategies can build or reabsorb organs at most once a minute per cell.",
		"Reabsorb returns AP to that cell. Installed organs stay where you built them.",

	],
	"footer":"Your cell and its progress carry on between updates.",
	"button":"Back to the pond",
},
{
 "id":"2026-10-17-stable-renewable-carbon",
 "audience":"stable",
 "title":"What’s new in the pond",
 "items":[
  "Air slowly replenishes dissolved carbon throughout the pond, so the food chain can keep going.",
  "One healthy leaf can sustain a basic cell even in dim water. Larger builds need more leaves and efficient respiration.",
  "Starving cells pause reproductive investment while they recover. Select a leaf to see what it is waiting for.",
 ],
 "footer":"Your cells and their progress carry on between updates.",
 "button":"Back to the pond",
},
 {
  "id":"2026-10-18-family-fusion",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
  "Stronger currents carry life through the pond, while plants still soften the water around them.",
   "New cells start with a leaf. Leaves provide more ATP, and swirling water exchanges gases with the air.",
   "Choose when to divide, or turn on automatic division. Relatives can merge after reabsorbing the donor’s organs, combining AP and resources.",
   "Family investment is clearer, with individual exceptions preserved and easier family scrolling.",
   "Glands keep their attack cues while the cell seeks food or light. Specialization, mouth layering and particle information are clearer."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond",
 },
 {
  "id":"2026-10-18-clearer-gases-and-currents",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "CO2 and oxygen particles are larger and easier to see.",
   "Soft, bright ripples now trace the water's movement. Gold still marks only the water immediately around an induced-current source."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-cross-current-crests",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Water ripples now stretch across the current as they travel, with clearer crests at every zoom."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-current-display-choice",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Wave crests are now broad, continuous arcs drifting with the water.",
   "In Pause, choose Wave crests or the familiar continuous Streamlines. Your choice is remembered.",
   "Current markers no longer crisscross around moving eddies."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-induced-input-overlay",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Passing currents now fade gently in and out over a wider area.",
   "Pale marks show the water’s overall motion. Gold marks show where a passing current is pushing.",
   "Gold uses the other current style, so you can see both the push and the resulting flow."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-division-and-instinct-controls",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Intent view starts on. Use Instinct to show or hide your cell’s intention and direction arrow.",
   "Divide opens a choice: keep Auto divide on, or request just one division. If resources are short, your request stays lit until the cell can divide.",
   "Wave crests are the starting view for this update. You can still choose Streamlines in Pause."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-mitochondrial-efficiency",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Mitochondria now recover more ATP from food and oxygen without taking away biomass growth.",
   "Each healthy mitochondrion adds 50% to ordinary oxygen-supported digestion. Two give double the ATP; damaged mitochondria help less."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-local-merge-selection",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Merge now zooms smoothly to nearby water. Choose a bright relative directly; only relatives your cell detects through pheromones can be selected.",
   "Other cells dim while you choose. Cancel returns to your previous view.",
   "The view controls now say Internal and External.",
   "The Family window fits your screen, and you can swipe through larger families or use the arrow buttons.",
   "Stray offensive particles can now affect relatives. Hunters still choose targets outside the family.",
   "The new Receptor factory offers free Flight, Hunting, Toward family and Away from family receptors.",
   "Hunters can pursue any detected non-family cell. Flight avoids nearby toxins and armed non-family cells."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-critical-resource-signals",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Low ATP now makes the ATP sac blink amber. Critical membrane damage makes the membrane blink coral, replacing the warning message."
  ],
  "footer":"Your cells and their progress carry on between updates.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-steady-family-merge",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Nearby relatives stay available to merge for five seconds after you receive their family signal.",
   "Cancel merge takes you back, and overlapping relatives are easier to choose.",
   "A merging relative now slides into your cell and fades away.",
   "Air now enters faster-moving water more quickly."
  ],
  "footer":"Experimental updates start with a fresh copy of the main pond.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-immediate-family-merge",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Choose a bright relative to merge it straight into your cell, without waiting for an approach.",
   "The relative slides into your cell as its resources are absorbed.",
   "Crowded water never blocks a merge. Your biomass and AP have no storage limit."
  ],
  "footer":"Experimental updates start with a fresh copy of the main pond.",
  "button":"Back to the pond"
 },
 {
  "id":"2026-10-18-smoother-current-drawing",
  "audience":"experimental",
  "title":"What’s new in the pond",
  "items":[
   "Reduced stutters while updating the water-current animation.",
   "Phones can show fewer full-length current curves to keep the view responsive."
  ],
  "footer":"Experimental updates start with a fresh copy of the main pond.",
  "button":"Back to the pond"
 },
{
 "id": "2026-10-18-stable-life-and-currents",
 "audience": "stable",
 "title": "What’s new in the pond",
 "items": [
  "Leaves produce more ATP, and new cells start with one leaf. Each healthy mitochondrion adds 50% to ATP recovered from food and oxygen.",
  "Open Divide to request one division or enable Auto divide. A single request stays lit until your cell is ready. Instinct shows or hides your cell’s intention.",
  "Merge a bright relative your cell has sensed recently. It slides straight into your cell as its resources are absorbed. Biomass and AP have no storage limit.",
  "The Receptor factory offers free Hunting, Flight, Toward family and Away from family receptors. Hunters pursue other lineages; Flight avoids toxins and armed outsiders. Stray attacks can also hurt relatives.",
  "Family menus fit your screen and support swiping over portraits. View controls now say Internal and External. Low ATP and serious membrane damage make the affected part blink.",
  "Stronger currents move through the pond. Choose broad Wave crests or continuous Streamlines in Pause; gold shows passing current sources. Larger gas particles are easier to see, and moving water takes in more air.",
  "Reduced stutters in the current animation, with fewer water markings on phones when needed."
 ],
 "footer": "Your cells and their progress carry on between updates.",
 "button": "Back to the pond"
},
{
 "id":"2026-10-18-stable-receptor-repair",
 "audience":"stable",
 "title":"What’s new in the pond",
 "items":["Fixed a rare repair problem that could corrupt cell resources and interrupt the pond."],
 "footer":"The pond has been recovered from its last healthy save.",
 "button":"Back to the pond"
},
{
 "id":"2026-10-19-stable-family-limit",
 "audience":"stable",
 "title":"What’s new in the pond",
 "items":[
  "Families now keep up to 12 living cells. If a division goes over the limit, the daughter merges straight back into its parent.",
  "Larger families bring younger unattended relatives back into older cells. AP and resources combine through the usual merge.",
  "Auto divide starts on for new cells. You can switch it off in Divide; saved choices stay as you left them."
 ],
 "footer":"Your pond, family progress and remaining cells carry on.",
 "button":"Back to the pond"
},
{
 "id": "2026-10-19-experimental-cell-lifecycle",
 "supersedes_experimental": true,
 "audience": "experimental",
 "title": "What’s new in the pond",
 "items": [
  "Build with biomass instead of AP. Your first two organelles are free, and the oral groove can now be replaced.",
  "Choose Mitosis or Budding directly. Instincts can choose either automatically, with one birth per cell each minute. Families still keep up to 12 cells.",
  "Your favorite cell is protected while you are away, paused or in a hidden tab. Give it a first name in Pause.",
  "Hunter, Producer and Grazer builds gain distinct benefits. Investment can also remember a relative’s build.",
  "Cells swim more responsively. Crowding and oversized cells have visible, gradual consequences; stored biomass can provide emergency ATP.",
  "Fixed lingering merge images and reconnecting from Pause. Removed the old three-crisis objectives."
 ],
 "footer": "Experimental starts from a fresh copy of the main pond. Main is unchanged.",
 "button": "Back to the pond"
},
{
 "id":"2026-10-19-experimental-steady-cells",
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "Cells settle into the local current instead of bouncing wildly. Swimming still moves them through the water.",
  "The oral groove’s internal strand now joins the center of the cell and disappears when the mouth is reabsorbed.",
  "Producers grow a firm, boxy wall. They need two working leaves, a mitochondrion, no weapons and no mouth."
 ],
 "footer":"Experimental starts from a fresh copy of the main pond. Main is unchanged.",
 "button":"Back to the pond"
},
{
 "id":"2026-10-19-experimental-growing-build-prices",
 "audience":"experimental",
 "title":"What’s new in the pond",
 "items":[
  "Your first two organelles are free. Later build prices grow: 10, 10, 20, 30, 50, 80… biomass.",
  "Reabsorbing an organelle moves the next build back one price step. Receptors remain free and do not raise prices."
 ],
 "footer":"Experimental starts from a fresh copy of the main pond. Main is unchanged.",
 "button":"Back to the pond"
}
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
	var first:=seen_index(account)+1
	var consolidated:=-1
	if instance=="experimental":
		for i in range(first,RELEASES.size()):
			if RELEASES[i].get("audience","")=="experimental" and RELEASES[i].get("supersedes_experimental",false):consolidated=i
	for release_index in range(first,RELEASES.size()):
		var update: Dictionary=RELEASES[release_index]
		# Consolidation replaces earlier experimental notices only. Later updates
		# must still appear in publication order and be acknowledged normally.
		if release_index<consolidated and update.get("audience","")=="experimental":continue
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
