extends SceneTree
const Acid=preload("res://scripts/acidity.gd")
const Medium=preload("res://scripts/medium.gd")
const Surface=preload("res://scripts/membrane_art.gd")
class Body:
	var position:=Vector2.ZERO
	var previous_position:=Vector2.ZERO
	var dead:=false
	var radius:=40.0
	func extent() -> float:return radius
var failures:=0
var assertions:=0
func check(ok: bool,text: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:
	check(is_equal_approx(Acid.ph_from_equivalents(0),7),"Neutral water is pH 7")
	check(absf(Acid.ph_from_equivalents(1)-3)<.001 and absf(Acid.ph_from_equivalents(.1)-4)<.001,"Tenfold excess acid changes pH by one unit")
	check(absf(Acid.ph_from_equivalents(-.1)-10)<.001,"The indicator conversion also supports alkaline equivalents")
	check(Acid.indicator_color(7).a==0 and Acid.indicator_color(6.8).a==0,"Near-neutral tint is invisible")
	check(Acid.indicator_color(2).r>.9 and Acid.indicator_color(2).b>.4,"Low pH is visibly pink")
	check(Acid.indicator_color(9).g>Acid.indicator_color(9).r and Acid.indicator_color(12).b>Acid.indicator_color(12).r,"Basic palette passes through green and cyan")
	var acid=Acid.new();var fluid=Medium.new();fluid.activity.fill(1);fluid.active_indices.clear()
	for i in acid.values.size():fluid.active_indices.append(i)
	fluid.velocity.fill(Vector2.ZERO);acid.values.fill(.5)
	for i in 10:acid.step(.1,fluid)
	check(absf(acid.values[0]-.5*exp(-.08))<.00001,"Uniform acid neutralizes at the explicit rate without gaining material")
	var script_values=acid.values.duplicate()
	var kernels=preload("res://scripts/backend.gd").create()
	if kernels!=null:
		var native_values=PackedFloat32Array();native_values.resize(script_values.size());native_values.fill(.5)
		for i in 10:native_values=kernels.acid_step(native_values,fluid.velocity,fluid.activity,.1)
		check(absf(native_values[0]-script_values[0])<.00001,"Native and script acid decay agree")
	acid.values.fill(0);acid.values[100]=1
	acid.step(.1,fluid)
	check(acid.values[102]==0 and acid.values[100]>.94,"An isolated acid source does not tint or numerically diffuse across distant cells")
	for count in [28,112]:
		var outline:=PackedVector2Array()
		for i in count:outline.append(Vector2.from_angle(TAU*i/count)*(40+5*sin(i*3)))
		var arrays: Array=Surface.arrays(outline,false)
		check(arrays[Mesh.ARRAY_VERTEX].size()==1+4*count and arrays[Mesh.ARRAY_INDEX].size()==count*21,"Cached topology retains all radial vertices and triangle indices")
		for ring in 4:
			for i in count:
				if arrays[Mesh.ARRAY_VERTEX][1+ring*count+i]!=outline[i]*Surface.RINGS[ring]:failures+=1
		var again: Array=Surface.arrays(Transform2D(0,Vector2.ONE*1.1,0,Vector2.ZERO)*outline,false)
		check(again[Mesh.ARRAY_INDEX]==arrays[Mesh.ARRAY_INDEX] and again[Mesh.ARRAY_VERTEX]!=arrays[Mesh.ARRAY_VERTEX],"Topology reuse cannot freeze changing membrane vertices")
	var sheet=preload("res://scripts/organ_atlas.gd").texture()
	check(sheet!=null and sheet.get_width()==384 and sheet.get_image().has_mipmaps(),"Tiny-organ atlas derives usable antialiased mipmapped art from source vectors")
	var Grid=preload("res://scripts/network/body_grid.gd")
	var bodies: Array=[]
	for i in 64:
		var body:=Body.new();body.previous_position=Vector2(i*67,15+i*39).posmodv(Grid.WORLD)
		body.position=(body.previous_position+Vector2(180,-210)).posmodv(Grid.WORLD)
		body.radius=40+i*3;bodies.append(body)
	bodies[31].radius=5000 # Full-world bounds and high bit in each texture word.
	var masks=Grid.masks(bodies);var pixels=Grid.pixels(bodies)
	var covered:=true;var packed:=true
	for b in 64:
		var body=bodies[b]
		var delta: Vector2=(body.position-body.previous_position+Grid.WORLD*.5).posmodv(Grid.WORLD)-Grid.WORLD*.5
		for step in 11:
			var center: Vector2=body.previous_position+delta*step/10.0
			for ray in 24:
				var at: Vector2=(center+Vector2.from_angle(ray*TAU/24)*(body.radius+7.999)).posmodv(Grid.WORLD)
				var index: int=posmod(floori(at.y/Grid.TILE),Grid.HEIGHT)*Grid.WIDTH+posmod(floori(at.x/Grid.TILE),Grid.WIDTH)
				covered=covered and (masks[index] & (1<<b))!=0
	for i in masks.size():
		for channel in 4:packed=packed and int(pixels[i*4+channel])==((masks[i]>>(channel*16))&65535)
	check(covered,"Swept periodic body grid keeps every candidate across interpolation, seams, large bodies and all 64 bits")
	check(packed,"Float texture words retain all 64 membership bits exactly")
	print("CLIENT PRESENTATION: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
