extends RefCounted
## Authored player-facing copy: update this ID and text with every public release.
const CURRENT={
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
}
static func pending(account: Dictionary) -> Dictionary:
	return {} if account.get("seen_release","")==CURRENT.id else CURRENT.duplicate(true)
static func acknowledge(account: Dictionary,id) -> bool:
	if not id is String or id!=CURRENT.id:return false
	account.seen_release=id
	return true
