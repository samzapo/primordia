extends RefCounted
## Shared, read-only synergy artwork for live cells and current-state portraits.
## Hairs/follicles are illustration, never extra organs or collision bodies.
static func capture(cell) -> Dictionary:
	var role: String=cell.synergy()
	var model: Dictionary={"role":role,"spine":PackedVector2Array(),"roots":PackedVector2Array(),"normals":PackedVector2Array()}
	if role=="hunter" and is_finite(cell.membrane.hunter_angle):
		var axis: float=cell.membrane.hunter_angle
		model.spine=PackedVector2Array([-Vector2.from_angle(axis)*cell.radius*.45,Vector2.ZERO,cell.local_point(cell.surface_parameter(axis))*.96])
	elif role=="grazer":
		# Leave the oral vestibule clear. The ten roots follow the real outline,
		# with modest local offsets away from equipped membrane organs.
		var mouth:=0.0
		for organ in cell.organs:
			if organ.kind=="feeding":mouth=float(organ.a);break
		for i in 10:
			var a: float=mouth+.62+(TAU-1.24)*(i+.5)/10
			var best:=a;var clearance:=-INF
			for offset in [0.0,-.10,.10,-.20,.20]:
				var candidate: float=a+offset;var score:=INF
				for organ in cell.organs:
					if cell.internal_organ(organ.kind):continue
					score=minf(score,cell.local_point(candidate).distance_to(cell.organ_local_position(organ)))
				if score>clearance:clearance=score;best=candidate
			var outline: PackedVector2Array=cell.membrane.outline()
			var phase: float=fposmod(best,TAU)/TAU*outline.size()
			var root: Vector2=outline[int(phase)].lerp(outline[(int(phase)+1)%outline.size()],fposmod(phase,1))
			model.roots.append(root);model.normals.append(cell.local_normal(best))
	return model

static func hair(model: Dictionary,index: int,radius: float,age: float) -> PackedVector2Array:
	var root: Vector2=model.roots[index];var normal: Vector2=model.normals[index]
	var length:=radius*(.25+.045*sin(index*2.4))
	var bend:=radius*(.035*sin(age*2+index*1.7)+.035*sin(index*2.1))
	var curve:=PackedVector2Array()
	for j in 9:
		var t:=j/8.0
		curve.append(root+normal*(radius*.025+length*t)+Vector2(-normal.y,normal.x)*bend*t*t)
	return curve

static func draw(canvas: Node2D,model: Dictionary,outline: PackedVector2Array,radius: float,hue: Color,age: float) -> void:
	var role: String=model.get("role","")
	if role=="hunter" and model.spine.size()>1:
		canvas.draw_polyline(model.spine,hue.lightened(.7)*Color(1,1,1,.28),maxf(.8,radius*.018),true)
		canvas.draw_polyline(model.spine,hue.lightened(.85)*Color(1,1,1,.45),maxf(.4,radius*.006),true)
	elif role=="producer":
		# Keep the existing Producer wall exactly as it appears in the pond.
		var wall:=PackedVector2Array()
		for point in outline:wall.append(point*.975)
		wall.append(wall[0])
		canvas.draw_polyline(wall,hue.lightened(.55)*Color(1,1,1,.8),maxf(1,radius*.045),true)
		var inner:=PackedVector2Array()
		for point in outline:inner.append(point*.92)
		inner.append(inner[0])
		canvas.draw_polyline(inner,hue.darkened(.45)*Color(1,1,1,.65),maxf(.7,radius*.018),true)
	elif role=="grazer":
		for i in model.roots.size():
			var at: Vector2=model.roots[i]
			var normal: Vector2=model.normals[i]
			canvas.draw_polyline(hair(model,i,radius,age),hue.lightened(.8)*Color(1,1,1,.85),maxf(.6,radius*.014),true)
			# Round follicle bumps sit below usable organ artwork.
			canvas.draw_circle(at,radius*.046,hue.darkened(.35))
			canvas.draw_circle(at+normal*radius*.012,radius*.034,hue.lightened(.35))
			canvas.draw_circle(at+normal*radius*.025,radius*.012,hue.lightened(.75))
