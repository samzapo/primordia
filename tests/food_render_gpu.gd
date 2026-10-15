extends SceneTree
var failures:=0
var assertions:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	root.size=Vector2i(1440,900)
	var scene=load("res://scenes/pond.tscn").instantiate();scene.use_particle_pool=false
	root.add_child(scene);scene.set_physics_process(false);scene.music.enabled=false;scene.music.player.stop()
	var cell=scene.world.player
	cell.angle=.7;cell.previous_angle=.7;cell.chemistry.receive(0,3,3,cell.position+Vector2(30,0).rotated(cell.angle))
	cell.chemistry.advance(cell,1)
	var other=scene.world.Cell.clone_state(cell);other.id=999;other.lineage=999
	scene.world.cells=[cell,other];scene.manual_zoom=4;scene.membrane_depth=true
	scene._toggle_perception();scene._update_world(1)
	for i in 5:await process_frame
	var view=scene.views[cell.id]
	check(view.z_index>scene.views[999].z_index and view.interior_backing.visible,"Focused cell is an opaque foreground above background organisms")
	check(view.cytoplasm.multimesh.visible_instance_count==1 and cell.chemistry.particles.size()==2,"Mixed food/waste stock has one rendered carrier rather than independently moving contents")
	var artwork=preload("res://scripts/visuals.gd")
	check(artwork.internal_content_radius(0)==scene.world.particle_radius(0)*.5 and artwork.internal_content_radius(2)==scene.world.particle_radius(2)*.5,"Interior nutrient and waste glyphs use half the matching external base radius")
	for quantity in [.03,.3,3.0]:
		check(artwork.internal_content_radius(0,quantity)==scene.world.particle_radius(0)*scene.world.particle_scale(quantity)*.5 and artwork.internal_content_radius(2,quantity)==scene.world.particle_radius(2)*scene.world.particle_scale(quantity)*.5,"Illustrated nutrient/waste sizes stay half the external glyph size across dose scaling")
	var mask: Image=scene.perception_mask.viewport.get_texture().get_image()
	var extent: float=cell.extent()*1.05
	check(mask.get_pixel(128,128).r>.9,"Actual cell center is inside the membrane mask")
	var outside:=0
	for x in [0,1,254,255]:
		for y in [0,1,64,128,192,254,255]:
			if mask.get_pixel(x,y).a<.1:outside+=1
	check(outside==28,"Mask texture has no filled halo or cropped rectangular edge")
	for j in 28:
		var edge: Vector2=cell.local_point(TAU*j/28)
		var inside:=Vector2i(Vector2.ONE*128+edge*.85*128/extent)
		check(mask.get_pixelv(inside).r>.9,"Deformed membrane contains its inner ring")
	var packet: Dictionary=cell.chemistry.particles[0]
	var at: Vector2=scene.world_layer.to_global(view.position+packet.p.rotated(view.rotation))
	var picked: Dictionary=scene.inspector.pick(at,1)
	check(picked.get("internal",false) and picked.kind==0,"Internal food glyph supports local hover inspection")
	scene.inspector.inspect_touch(at);scene.inspector.update_lens(.2,at,1,true)
	check(scene.inspector.label.text.contains("Food vacuole") and scene.inspector.glyph.visible,"Phone tap exposes the same named magnifier")
	var radius: float=picked.radius
	scene.manual_zoom=8;scene._update_world(1)
	var new_at: Vector2=scene.world_layer.to_global(view.position+packet.p.rotated(view.rotation))
	check(scene.inspector.pick(new_at,1).radius>radius*1.9,"Internal glyphs scale with camera zoom")
	# Render only the interior on a transparent surface to detect an invisible factory.
	var factory_viewport:=SubViewport.new();factory_viewport.size=Vector2i(512,512)
	factory_viewport.disable_3d=true;factory_viewport.transparent_bg=true;factory_viewport.world_2d=World2D.new()
	factory_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;scene.add_child(factory_viewport)
	var factory_art=preload("res://scripts/cell_interior.gd").new();factory_art.game=scene
	factory_viewport.add_child(factory_art);factory_art.sync();factory_art.position=Vector2(256,256);factory_art.rotation=0;factory_art.scale=Vector2.ONE*5
	for i in 4:await process_frame
	var factory_image: Image=factory_viewport.get_texture().get_image()
	for i in 3:
		var chamber: Vector2=factory_art.anchors.chemistry+Vector2((i-1)*.10,abs(i-1)*.07)*factory_art.anchors.radius
		var pixel: Color=factory_image.get_pixelv(Vector2i(Vector2(256,256)+chamber*5))
		check(pixel.a>.9 and pixel.g>.7 and pixel.b>.6 and pixel.r<.5,"All three teal chemical-factory chambers remain visibly rendered")
	factory_viewport.queue_free()
	var resident=preload("res://scripts/resident_particles.gd").new();resident.rd=RenderingServer.get_rendering_device()
	check(preload("res://scripts/resident_cytoplasm.gd").new().attach(resident,cell.chemistry,cell),"The same illustrated vacuole can transfer into the main resident device")
	view.seen_revision=-1;scene._update_world(1)
	var before_exports: int=cell.chemistry.accelerator.exports
	var receipt: Dictionary=cell.chemistry.vacuoles[0]
	var native_at: Vector2=scene.world_layer.to_global(view.position+receipt.p.rotated(view.rotation))
	var native_pick: Dictionary=scene.inspector.pick(native_at,1)
	check(native_pick.get("internal",false) and native_pick.food>0 and native_pick.waste>0,"Compact resident receipts support picking both finite stocks in one carrier")
	check(cell.chemistry.accelerator.exports==before_exports and cell.chemistry.particles.is_empty(),"Inspecting a resident vacuole never downloads its full stock/pose pool")
	for i in 4:await process_frame
	cell.chemistry.ensure_cpu()
	scene.queue_free();await process_frame
	print("FOOD RENDER GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
