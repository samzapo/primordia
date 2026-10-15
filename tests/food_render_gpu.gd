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
	var other=scene.world.Cell.clone_state(cell);other.id=999;other.lineage=999
	scene.world.cells=[cell,other];scene.manual_zoom=4;scene.membrane_depth=true
	scene._toggle_perception();scene._update_world(1)
	for i in 5:await process_frame
	var view=scene.views[cell.id]
	check(view.z_index>scene.views[999].z_index and view.interior_backing.visible,"Focused cell is an opaque foreground above background organisms")
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
	scene.queue_free();await process_frame
	print("FOOD RENDER GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
