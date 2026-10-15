extends RefCounted
func run(suite) -> void:
	var scene=load("res://scenes/pond.tscn").instantiate();scene.use_particle_pool=false
	suite.root.add_child(scene);scene.set_physics_process(false);scene._toggle_build()
	var editor=scene.cell_ui.pathways;editor.open_cell()
	suite.expect(editor.visible and editor.inspected.text.contains("Digestion makes ATP and biomass directly"),"Cell-local inspection explains direct digestion")
	suite.expect(scene.world.player.chemistry.nodes.is_empty(),"Retired pathway controls cannot create a molecular network")
	scene._toggle_build();editor._process(0)
	suite.expect(not editor.visible,"Leaving editing hides the food explanation")
	scene.music.enabled=false;scene.music.player.stop();scene.queue_free();await suite.process_frame
