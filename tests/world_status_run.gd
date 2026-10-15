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
	fixture.graph.objects[1].fields.chemistry={"$ref":4}
	fixture.graph.objects.append({"fields":{"particles":{"$array":[{"species":"water","source":-1,"compartment":-1,"amount":1.0},{"species":"water","source":-1,"compartment":-1,"amount":2.0,"sparse_fact":true}]}}})
	result=inspector.selection(fixture)
	assert(result.living_chemistry[0].species.water==2 and result.living_chemistry[0].compatible_groups==1 and result.living_chemistry[0].extra_facts.sparse_fact==1,"Bounded chemistry telemetry counts species and constraints without restoring or mutating the saved world")
	var points:=PackedVector2Array()
	for i in 28:points.append(Vector2.from_angle(TAU*i/28)*47)
	fixture.graph.objects[1].fields.membrane={"$ref":5}
	fixture.graph.objects.append({"fields":{"points":points}})
	result=inspector.selection(fixture)
	assert(not result.membranes[0].folded and absf(result.membranes[0].turn-TAU)<.001 and not result.membranes[0].has("points"),"Healthy membrane telemetry stays bounded and omits raw geometry")
	var swap: Vector2=points[3];points[3]=points[4];points[4]=swap
	fixture.graph.objects[5].fields.points=points
	result=inspector.selection(fixture)
	assert(result.membranes[0].folded and result.membranes[0].points.size()==28,"A folded saved membrane retains decisive bounded reproduction geometry")
	print("WORLD SELECTION: 6 assertions, 0 failures")
	quit(0)
