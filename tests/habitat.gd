extends RefCounted
const Habitat = preload("res://scripts/habitat.gd")
const Sim = preload("res://scripts/simulation.gd")
const Art = preload("res://scripts/habitat_view.gd")
static func run(check: Callable) -> void:
	var first = Sim.new(412)
	var second = Sim.new(412)
	var other = Sim.new(413)
	check.call(first.habitat_geometry.plants == second.habitat_geometry.plants,"Habitat placement repeats from its independent seed")
	check.call(first.habitat_geometry.plants != other.habitat_geometry.plants,"Different seeds produce different colonies")
	check.call(first.habitat_geometry.plants.size() >= 6,"Habitat has several large obstacle colonies")
	for cell in first.cells:
		check.call(first.habitat_geometry.clear_at(cell.position,cell.extent()+20),"Initial cells have open water around them")
	var families := {}
	check.call(first.habitat_geometry.forms == second.habitat_geometry.forms,"Seeded plant artwork repeats independently of the simulation")
	for form in first.habitat_geometry.forms:
		families[form.kind] = true
		var per_arm: int = form.branches.size()/form.arms
		check.call(form.branches.size() <= 192,"Fractal grammar has a bounded finite depth")
		for branch in form.branches:
			check.call(branch.a.is_finite() and branch.b.is_finite() and maxf(branch.a.length(),branch.b.length())+maxf(branch.r,5.5) < 100,"Every fractal fits its drawing and obstacle placement envelope")
		for arm in range(1,form.arms):
			var expected: Vector2 = form.branches[0].b.rotated(TAU*arm/form.arms)
			check.call(expected.distance_to(form.branches[per_arm*arm].b) < 0.001,"Repeated arms have rotational symmetry")
		var image := Image.new()
		check.call(image.load_svg_from_string(Art.svg(form)) == OK,"Procedural plant artwork rasterizes")
		check.call(image.get_size() == Vector2i(512,512),"Texture size stays bounded independently of visible geometry")
	check.call(families.size() == 4 and families.has("fern") and families.has("fan") and families.has("spiral") and families.has("radial"),"Habitat contains fern, radial, branching fan and spiral families")
	# One capsule fixture exercises the authoritative branch collision and periodic bins.
	var h = Habitat.new(1)
	h.forms = [{"branches":[{"a":Vector2(-50,0),"b":Vector2(50,0),"r":5.0,"depth":2}]}]
	h.plants = [{"p":Vector2(2048,1280),"radius":100.0,"form":0,"angle":0.0}]
	h.rebuild()
	var result: Array = h.move(Vector2(2048,1180),Vector2(2048,1380),Vector2(0,12000),10)
	check.call(result[2] and result[0].y < 1265.1,"Fast cells cannot tunnel through a narrow stem")
	check.call(absf(result[1].y) < 0.01,"Branch collision removes only inward velocity")
	result = h.move(Vector2(2048,1180),Vector2(2100,1380),Vector2(100,400),10)
	check.call(result[0].x > 2055 and result[1].x > 90,"Oblique contact preserves sliding along a stem")
	result = h.move(Vector2(2048,1280),Vector2(2048,1280),Vector2.ZERO,30)
	check.call(h.clear_at(result[0],30),"Growing or initially overlapping cells are projected out of stems")
	check.call(h.clear_at(Vector2(2048,1320),5),"Water outside a stem is traversable")
	h.plants[0].p = Vector2(4,1280)
	h.rebuild()
	check.call(not h.clear_at(Vector2(4090,1280),3),"Solid branches continue across the habitat seam")
	result = h.move(Vector2(4090,1180),Vector2(4090,1380),Vector2(0,100),4)
	check.call(result[2] and result[0].y < 1271.1,"Swept contacts use the same periodic image as drawing")
	h.particles_permeable = false # Historical contact-kernel parity, not current gameplay.
	var grid = Sim.Grid.new()
	var packets := [{"p":Vector2(4090,1380),"previous":Vector2(4090,1180),"v":Vector2(0,100),"alive":true,"updated":1,"amount":3.0,"kind":0,"owner":1}]
	grid.rebuild(packets)
	var reference: Array = packets.duplicate(true)
	h.move_particles(reference,[0],1,grid,false)
	h.move_particles(packets,[0],1,grid)
	check.call(packets[0].p.distance_to(reference[0].p) < 0.001 and packets[0].v.distance_to(reference[0].v) < 0.001,"Native and reference obstacle contacts agree across the seam")
	check.call(packets[0].p.y < 1271.1 and packets[0].amount == 3.0,"Plant contact preserves packet material and prevents crossing")
	check.call(0 in grid.query(packets[0].p,10),"Moved packets retain correct spatial-grid membership")
	check.call(packets[0].previous == packets[0].p,"Particle interpolation cannot cross the contacted stem")
	# Differential fixture includes empty bins, penetration, grazing and long seam-crossing sweeps.
	if h.accelerator != null:
		var random := RandomNumberGenerator.new()
		random.seed = 9081
		var native_packets: Array = []
		for i in 160:
			var start := Vector2(random.randf_range(-80,100),random.randf_range(1200,1350))
			if i == 0: start = Vector2(4,1280)
			var travel := Vector2(random.randf_range(-120,120),random.randf_range(-200,200))
			native_packets.append({"p":Sim.Medium.wrap_position(start+travel),"previous":Sim.Medium.wrap_position(start),"v":travel*60,"alive":true,"updated":1,"amount":1.0})
		var script_packets: Array = native_packets.duplicate(true)
		grid.rebuild(script_packets)
		h.move_particles(script_packets,range(160),1,grid,false)
		grid.rebuild(native_packets)
		h.move_particles(native_packets,range(160),1,grid,true)
		for i in 160:
			check.call(Sim.Medium.offset(script_packets[i].p,native_packets[i].p).length() < 0.01,"Native/reference colony sweep positions agree %d: %s vs %s" % [i,script_packets[i].p,native_packets[i].p])
			check.call(script_packets[i].v.distance_to(native_packets[i].v) < maxf(0.01,script_packets[i].v.length()*0.0001),"Native/reference colony sliding velocities agree %d: %s vs %s" % [i,script_packets[i].v,native_packets[i].v])
	h.enabled = false
	result = h.move(Vector2(4090,1180),Vector2(4090,1380),Vector2(0,100),4)
	check.call(not result[2] and result[0] == Vector2(4090,1380),"Disabled plant ablation leaves motion unchanged")
