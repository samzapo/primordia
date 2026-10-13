extends RefCounted
## Owner instruction, October 13, 2026: gameplay balance tests stay disabled
## until the owner explicitly asks to restore them. No environment override.
const GAMEPLAY_BALANCE_ENABLED := false
static func skip(group: String) -> void:
	print("SKIPPED gameplay balance: %s (disabled by owner until further notice)" % group)
