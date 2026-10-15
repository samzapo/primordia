extends SceneTree
## Pixel regression: a reversed pair must not draw a second lip inside the body.
var failures:=0
var assertions:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(720,320);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var materials: Array=[]
	for j in 3:
		var membrane=preload("res://scripts/membrane.gd").new(65)
		membrane.native_outline=membrane.kernels!=null and j==2
		if j>0:
			var at:=3 if j==1 else 14
			var swap: Vector2=membrane.points[at];membrane.points[at]=membrane.points[at+1];membrane.points[at+1]=swap
		membrane.invalidate()
		var node:=MeshInstance2D.new();node.mesh=preload("res://scripts/membrane_art.gd").mesh(membrane.outline(),false)
		node.position=Vector2(120+j*240,160);node.rotation=j*.53;node.material=ShaderMaterial.new();node.material.shader=preload("res://shaders/membrane.gdshader")
		var palette: Array=preload("res://scripts/cell_art.gd").PALETTES[1]
		for pair in [["edge",0],["body",1],["gel",2],["rim",3],["shine",4]]:node.material.set_shader_parameter(pair[0],Color(palette[pair[1]]))
		node.material.set_shader_parameter("wakes",false);viewport.add_child(node);materials.append(node)
	for frame in 5:await process_frame
	var image:=viewport.get_texture().get_image()
	for j in 3:
		var internal_lip:=0;var missing:=0
		for radius in [.45,.55,.65,.72]:
			for i in 72:
				var at: Vector2=materials[j].position+Vector2.from_angle(TAU*i/72)*65*radius
				var c:=image.get_pixel(roundi(at.x),roundi(at.y))
				if c.g>c.b*.65:internal_lip+=1
				if c.a<.98:missing+=1
		check(internal_lip==0,"No square or second membrane lip appears inside contour case %d (%d pixels)" % [j,internal_lip])
		check(missing==0,"The membrane body stays fully filled in contour case %d" % j)
		var c:=image.get_pixel(roundi(materials[j].position.x+100),160)
		check(c.a<.01,"The outer mesh halo cannot fill outside the membrane")
	if OS.has_environment("PRIMORDIA_MEMBRANE_CAPTURE"):image.save_png(OS.get_environment("PRIMORDIA_MEMBRANE_CAPTURE"))
	viewport.queue_free();await process_frame
	print("MEMBRANE RENDER GPU: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
