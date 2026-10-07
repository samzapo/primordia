extends RefCounted
const Fixture = preload("res://scripts/resident_fixture.gd")
static func run(check: Callable) -> void:
	var data := Fixture.make(513,"seam")
	var field := Fixture.flow()
	var material := 0.0
	for k in range(0,data.size(),12): material+=data[k+9]
	check.call(absf(material-300)<0.0001,"Resident fixture has fixed finite material")
	var one := Fixture.advance(data,field,1.0/60,0)
	check.call(Fixture.compare(one,one).passed,"Portable resident reference stays finite")
	check.call(one!=Fixture.advance(data,field,1.0/60,1),"Resident diffusion changes with tick")
	if not ClassDB.class_exists("PrimordiaResidentReference"): return
	var serial=ClassDB.instantiate("PrimordiaResidentReference")
	check.call(not serial.configure(data,field,9),"Resident CPU rejects invalid worker count")
	check.call(not serial.configure(PackedFloat32Array([0]),field,1),"Resident CPU rejects malformed state")
	check.call(serial.configure(data,field,1),"Resident CPU initializes")
	check.call(not serial.advance(0,0) and not serial.advance(3,0),"Resident CPU rejects unsupported dt")
	serial.advance(1.0/60,0)
	check.call(Fixture.compare(one,serial.snapshot()).passed,"Resident CPU agrees with portable independent oracle")
	for lanes in [2,4,8]:
		var parallel=ClassDB.instantiate("PrimordiaResidentReference")
		parallel.configure(data,field,lanes)
		parallel.advance(1.0/60,0)
		check.call(parallel.snapshot()==serial.snapshot(),"Resident CPU lane counts have identical outcomes")
	var coarse := Fixture.advance(one,field,0.7,1)
	serial.advance(0.7,1)
	check.call(Fixture.compare(coarse,serial.snapshot()).passed,"Resident coarse transport preserves reference")
	var before: PackedFloat32Array=serial.snapshot()
	var saved := before.duplicate()
	serial.advance(1.0/60,2)
	check.call(before!=serial.snapshot() and before==saved,"Resident snapshots detached")
	var instances: PackedFloat32Array=serial.instances(Vector2(2048,1280))
	check.call(instances.size()==data.size(),"Resident CPU drawing has one transform per particle")
