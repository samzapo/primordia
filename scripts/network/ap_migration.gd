extends RefCounted
## One-time legacy shared-pool allocation. No anatomy, physiology or RNG changes.
static func apply(world,accounts: Dictionary={}) -> void:
	if world.ap_model_version>=1:return
	var bodies: Dictionary={}
	for body in world.cells:bodies[body.id]=body
	bodies[world.player.id]=world.player
	for account in accounts.values():
		if account.has("current") and not bodies.has(account.current.id):bodies[account.current.id]=account.current
	for body in bodies.values():body.ap=0
	var credited: Dictionary={}
	# Authenticated ownership takes precedence over world.player, which may be
	# another account or an administrative simulation selection.
	for account in accounts.values():
		var target=bodies.get(account.selected,account.get("current"))
		_credit(target,account.evolution,credited)
	for ledger in [world.lineage]+world.family_ledgers:
		var target=null
		if world.player.lineage_id()==ledger.root_id:target=world.player
		if target==null:
			for body in world.cells:
				if body.lineage_id()==ledger.root_id and not body.dead:target=body;break
		if ledger.progression!=null:_credit(target,ledger.progression,credited)
	# A minimal/local fixture can have an unregistered initial ledger.
	_credit(world.player,world.evolution,credited)
	world.investment={"npc":{},"lineages":{},"cells":{}} # Explicit new default: everyone Manual.
	world.ap_model_version=1

static func _credit(body,progression,credited: Dictionary) -> void:
	var identity: int=progression.get_instance_id()
	if credited.has(identity):return
	credited[identity]=true
	if body==null:return # No living/retained owner; never assign an extinct pool elsewhere.
	body.ap+=maxi(0,progression.points)
	progression.points=0
