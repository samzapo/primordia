extends RefCounted
## Paused graph behavior and paid capacity; no survival or yield acceptance.
func run(suite) -> void:
	var scene=load("res://scenes/pond.tscn").instantiate()
	scene.use_particle_pool=false
	suite.root.add_child(scene)
	scene.set_physics_process(false)
	scene._toggle_build()
	var editor=scene.cell_ui.pathways
	editor.open_cell()
	var cell=scene.world.player
	var chemistry=cell.chemistry
	suite.expect(editor.visible and editor._valid(),"Pathway editor is attached to the paused living cell")
	var count:=0
	for child in editor.graph.get_children():
		if child is GraphNode: count+=1
	suite.expect(count==chemistry.nodes.size(),"Graph exposes installed local catalyst domains")
	var packets: Array=chemistry.particles.duplicate(true)
	var time: float=scene.world.time
	var revision: int=scene.world.revision
	var source: int=chemistry.find_module("digestion")
	var target: int=chemistry.find_module("glycolysis")
	editor._disconnect("reaction_"+str(source),0,"reaction_"+str(target),0)
	editor._connect("reaction_"+str(source),0,"reaction_"+str(target),0)
	editor._process(1)
	scene._physics_process(1)
	suite.expect(chemistry.particles==packets and scene.world.time==time and scene.world.revision==revision,"Graph wiring and pause never transport molecules or advance chemistry")
	var atp: float=cell.energy
	var matter: float=cell.organic_mass()
	var tissue: float=cell.biomass
	var points: int=scene.world.evolution.points
	editor._add(editor.templates.find("autocatalysis"))
	suite.expect(chemistry.find_module("autocatalysis")>=0 and cell.biomass==tissue-10 and scene.world.evolution.points==points-1,"New catalyst capacity spends ten tissue and one AP")
	suite.expect(absf(cell.organic_mass()-matter)<.0001 and cell.energy==atp,"Paid capacity conserves matter without granting ATP")
	var valid: Dictionary=chemistry.configuration()
	var invalid:=valid.duplicate(true)
	invalid.edges.append({"from":source,"to":target,"species":"unrecognized"})
	suite.expect(chemistry.load_configuration(invalid)!="" and chemistry.configuration()==valid,"Rejected graph configuration preserves the previous valid network")
	scene._toggle_build()
	editor._process(0)
	suite.expect(not editor.visible,"Leaving cell editing hides the pathway graph")
	scene.music.enabled=false
	scene.music.player.stop()
	scene.queue_free()
	await suite.process_frame
