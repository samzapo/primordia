extends Node2D
## Frozen donor artwork moves into the receiver; no simulated body or resources.
const Portrait=preload("res://scripts/cell_portrait.gd")
const Art=preload("res://scripts/cell_art.gd")
const Medium=preload("res://scripts/medium.gd")
const LIFETIME:=1.2
var game
var source
var seen:=0
var pulls: Array=[]
func reset(sim,serial: int=0) -> void:
	for pull in pulls:pull.node.queue_free()
	pulls.clear();source=sim;seen=serial
func sync(sim,camera: Vector2,dt: float,alpha: float=1.0) -> void:
	if source!=sim:reset(sim)
	for pull in pulls:pull.age+=dt
	for pull in pulls.duplicate():
		if pull.age>=LIFETIME:pull.node.queue_free();pulls.erase(pull)
	for event in sim.merge_bursts:
		if event.serial<=seen:continue
		seen=event.serial
		if sim.time-float(event.time)>LIFETIME:continue
		var node:=Node2D.new()
		var model: Dictionary=event.portrait.duplicate(true)
		var art: Dictionary=Art.make(sim.seed_value,model.lineage,game.lineage_color(model.lineage))
		art["core"]=Art.nucleus_outline(art.nucleus,art.phase)
		var mesh: ArrayMesh=Portrait.body(model,art)
		node.draw.connect(func():Portrait.draw(node,model,art,mesh,model.extent))
		add_child(node)
		pulls.append({"node":node,"event":event,"age":0.0})
		if pulls.size()>32:pulls[0].node.queue_free();pulls.pop_front()
	for pull in pulls:
		var phase: float=clampf(pull.age/LIFETIME,0,1)
		var event: Dictionary=pull.event
		var destination: Vector2=event.to
		for cell in sim.cells:
			if cell.id==event.receiver:
				destination=cell.previous_position+Medium.offset(cell.previous_position,cell.position)*alpha if sim.remote_client or cell.activity>0 else cell.position
				break
		var progress: float=smoothstep(0,.85,phase)
		pull.node.position=Medium.offset(camera,Medium.wrap_position(event.at+Medium.offset(event.at,destination)*progress))
		pull.node.modulate.a=1-smoothstep(.65,1,phase)
		pull.node.queue_redraw()
