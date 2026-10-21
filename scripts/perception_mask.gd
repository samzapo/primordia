extends RefCounted
## Small render-only mask reuses the actual membrane mesh; no physics/readbacks.
var game
var viewport:=SubViewport.new()
var body:=MeshInstance2D.new()
var enabled:=false
var cached_revision:=-1
var cached_cell:=-1
var selection_bodies: Dictionary={}
func initialize(owner_game) -> void:
	game=owner_game
	viewport.size=Vector2i(256,256);viewport.disable_3d=true;viewport.transparent_bg=true
	viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	game.add_child(viewport);viewport.add_child(body)
	body.material=ShaderMaterial.new();body.material.shader=preload("res://shaders/perception_mask.gdshader")
	game.microscope_layer.material.set_shader_parameter("focus_mask",viewport.get_texture())
func sync() -> void:
	var focus=game._follow_cell()
	var internal: bool=game.perception=="interoception" and game.death_focus_age>=game.death_view.LIFETIME
	game.microscope_layer.material.set_shader_parameter("merge_selecting",game.merge_selecting())
	if game.merge_selecting():
		_sync_selection();return
	body.visible=true
	for node in selection_bodies.values():node.queue_free()
	selection_bodies.clear()
	viewport.size=Vector2i(256,256)
	enabled=internal and game.views.has(focus.id)
	var material: ShaderMaterial=game.microscope_layer.material
	material.set_shader_parameter("interoception",internal)
	material.set_shader_parameter("focus_valid",enabled)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	if not enabled:return
	var view=game.views[focus.id]
	if view.surface.mesh!=null:body.mesh=view.surface.mesh
	elif cached_revision!=focus.render_revision or cached_cell!=focus.id:
		body.mesh=preload("res://scripts/membrane_art.gd").mesh(focus.membrane.outline(),game.native_geometry)
	cached_revision=focus.render_revision;cached_cell=focus.id
	var extent: float=maxf(1,focus.extent()*1.05)
	body.transform=Transform2D(0,Vector2.ONE*128/extent,0,Vector2.ONE*128)*view.motion.deformation
	material.set_shader_parameter("focus_center",game.Simulation.Medium.wrap_position(game.render_camera+view.position))
	material.set_shader_parameter("focus_heading",view.rotation)
	material.set_shader_parameter("focus_extent",extent)

func _sync_selection() -> void:
	enabled=true;body.hide()
	var material: ShaderMaterial=game.microscope_layer.material
	material.set_shader_parameter("interoception",false);material.set_shader_parameter("focus_valid",false)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var size: Vector2=game.get_viewport_rect().size
	var scale_value: float=512.0/maxf(1,maxf(size.x,size.y))
	viewport.size=Vector2i(maxi(1,roundi(size.x*scale_value)),maxi(1,roundi(size.y*scale_value)))
	var conversion:=Transform2D(Vector2(viewport.size.x/size.x,0),Vector2(0,viewport.size.y/size.y),Vector2.ZERO)
	var retained: Dictionary={}
	for cell in game.world.cells:
		if cell.dead or not game._merge_bright(cell) or not game.views.has(cell.id):continue
		retained[cell.id]=true
		if not selection_bodies.has(cell.id):
			var node:=MeshInstance2D.new();node.material=body.material;viewport.add_child(node);selection_bodies[cell.id]=node
		var mask: MeshInstance2D=selection_bodies[cell.id]
		var view=game.views[cell.id]
		if view.surface.mesh!=null:mask.mesh=view.surface.mesh
		elif mask.get_meta("revision",-1)!=cell.render_revision:
			mask.mesh=preload("res://scripts/membrane_art.gd").mesh(cell.membrane.outline(),game.native_geometry)
		mask.set_meta("revision",cell.render_revision)
		mask.transform=conversion*view.get_global_transform_with_canvas()*view.motion.deformation;mask.show()
	for id in selection_bodies.keys():
		if not retained.has(id):selection_bodies[id].queue_free();selection_bodies.erase(id)
