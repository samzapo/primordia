extends SceneTree
func _initialize() -> void:
	var inspector=preload("res://tools/world_status.gd")
	var fixture={"world_id":"fixture","tick":1,"graph":{"root":{"world":{"$ref":0},"accounts":{"fixture-private-key":{"selected":1,"root":1,"lineage":{"$ref":3},"current":{"$ref":2}}}},"objects":[{"fields":{"cells":{"$array":[{"$ref":1}]}}},{"fields":{"id":2,"lineage":-1,"dead":false,"position":Vector2(20,30),"radius":10}},{"fields":{"id":1,"lineage":-1,"dead":true,"position":Vector2(40,50),"radius":5}},{"fields":{"dormant":{"$array":[]}}}]}}
	var result: Dictionary=inspector.selection(fixture)
	assert(result.accounts[0].selected_dead and result.accounts[0].selected_location=="retained","A living pond does not imply a living selected account cell")
	assert(not JSON.stringify(result).contains("fixture-private-key"),"Selection telemetry cannot reveal account keys or tokens")
	fixture.graph.root.accounts["fixture-private-key"].selected=2;fixture.graph.root.accounts["fixture-private-key"].root=2
	result=inspector.selection(fixture)
	assert(not result.accounts[0].selected_dead and result.accounts[0].selected_location=="world" and result.accounts[0].living_family_count==1,"Current living selection and founder lineage resolve from graph references")
	print("WORLD SELECTION: 3 assertions, 0 failures")
	quit(0)
