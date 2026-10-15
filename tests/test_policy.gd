extends RefCounted
## Owner instruction, October 15, 2026: gameplay and balance suites restored.
const GAMEPLAY_BALANCE_ENABLED := true
const GAMEPLAY_OBJECTIVES_ENABLED := true
static func skip(group: String) -> void:
	print("SKIPPED gameplay balance: %s (disabled by owner until further notice)" % group)
