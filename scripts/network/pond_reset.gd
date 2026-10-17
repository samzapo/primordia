extends RefCounted
## Explicit reset only: reuse credentials/profiles, discard the old ecology/history.
const Codec=preload("res://scripts/network/state_codec.gd")
const Population=preload("res://scripts/network/pond_population.gd")
static func prepare(saved: Dictionary) -> Dictionary:
	var graph=Codec.new().restore(saved.get("graph",{}))
	if not graph is Dictionary or not graph.get("accounts") is Dictionary:return {"error":"Reset requires a valid account graph"}
	var accounts: Dictionary=graph.accounts
	var before: int=accounts.size()
	var replacement: Dictionary=Population.fresh(accounts)
	if replacement.has("error"):return replacement
	return {"world":replacement.world,"accounts":accounts,"accounts_before":before}
