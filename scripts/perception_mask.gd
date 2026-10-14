extends RefCounted
## Small render-only mask reuses the actual membrane mesh; no physics/readbacks.
var game
var viewport:=SubViewport.new()
var body:=MeshInstance2D.new()
var enabled:=false
var cached_revision:=-1
var cached_cell:=-1
func initialize(owner_game) -> void:
	game=owner_game
	viewport.size=Vector2i(256,256);viewport.disable_3d=true;viewport.transparent_bg=true
	viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	game.add_child(viewport);viewport.add_child(body)
	body.material=ShaderMaterial.new();body.material.shader=preload("res://shaders/perception_mask.gdshader")
	game.microscope_layer.material.set_shader_parameter("focus_mask",viewport.get_texture())
func sync() -> void:
	var focus=game._follow_cell()
	enabled=game.perception=="interoception" and game.views.has(focus.id)
	var material: ShaderMaterial=game.microscope_layer.material
	material.set_shader_parameter("interoception",game.perception=="interoception")
	material.set_shader_parameter("focus_valid",enabled)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	if not enabled:return
	var view=game.views[focus.id]
	if view.surface.mesh!=null:body.mesh=view.surface.mesh
	elif cached_revision!=focus.render_revision or cached_cell!=focus.id:
		body.mesh=preload("res://scripts/membrane_art.gd").mesh(focus.membrane.outline(),game.native_geometry)
	cached_revision=focus.render_revision;cached_cell=focus.id
	var extent: float=maxf(1,focus.extent()*1.05)
	body.position=Vector2.ONE*128;body.scale=Vector2.ONE*128/extent
	material.set_shader_parameter("focus_center",game.Simulation.Medium.wrap_position(game.render_camera+view.position))
	material.set_shader_parameter("focus_heading",view.rotation)
	material.set_shader_parameter("focus_extent",extent)
