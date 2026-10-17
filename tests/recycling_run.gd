extends SceneTree
var assertions:=0
var failures:=0
func check(ok: bool,why: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(why)
func _initialize() -> void:run.call_deferred()
func fill(sim) -> void:
 var cell=sim.player
 sim.remote_client=false;sim.server_mode=true;sim.evolution.sandbox=true;sim.evolution.enabled=true;sim.evolution.points=20
 cell.organs.clear();cell.body=500;cell.biomass=100;cell.update_geometry()
 cell.add_organ("feeding",0,"graze",false)
 for kind in ["cilia","photosynthesis","mitochondrion","regenerative"]:
  check(sim.install(kind,1),"Four-organ fixture installs through ordinary progressive AP construction")
func run() -> void:
 preload("res://tests/division_investment.gd").pricing(check)
 var game=load("res://scenes/pond.tscn").instantiate()
 game.use_particle_pool=false;root.add_child(game)
 game.set_process(false);game.set_physics_process(false)
 game.music.enabled=false;game.music.player.stop()
 var sim=game.world
 for mobile in [false,true]:
  fill(sim);game.touch_zoom.enabled=mobile;game.build_open=true
  var cell=sim.player
  var cheap: Dictionary=cell.organs[1]
  check(cheap.construction_ap==0 and cell.construction_refund(cheap)==3,"Any of four added organs returns three AP, even the originally free organ")
  cheap.erase("construction_ap")
  var recovered=preload("res://scripts/network/state_codec.gd").new().restore(preload("res://scripts/network/state_codec.gd").new().capture(sim))
  check(recovered.player.construction_refund(recovered.player.organ_by_id(cheap.id))==3,"Refund works after recovery without purchase-history metadata")
  game.cell_ui.open_context({"kind":"organ","id":cheap.id})
  var recycle=game.cell_ui.choices.filter(func(button):return button.caption=="Recycle")[0]
  check(recycle.description.contains("3 AP"),"Recycle preview reports the current tier")
  # Network snapshots replace the dictionaries while the menu remains open.
  cell.organs=cell.organs.duplicate(true)
  cell.organ_by_id(cheap.id).charge_flash=.7
  check(cell.organs.find(cheap)==-1,"Fixture reproduces a stale menu dictionary after a snapshot")
  var before: int=sim.evolution.points
  recycle.pressed.emit()
  check(cell.organ_by_id(cheap.id).is_empty() and sim.evolution.points==before+3 and cell.construction_price()==3,"Desktop and mobile recycle the stable organ ID after a live snapshot")
  var refunded: int=sim.evolution.points
  recycle.pressed.emit()
  check(sim.evolution.points==refunded and cell.construction_price()==3,"A stale second click cannot refund again or remove a different organ")
  var next: Dictionary=cell.organs[1]
  check(cell.construction_refund(next)==2,"The next recycling tier falls to two AP")
  check(cell.construction_refund(cell.organs[0])==0 and cell.construction_refund({})==0,"Inherent or missing structures have no recycling reward")
 fill(sim);sim.remote_client=true
 var commands: Array=[]
 sim.command_sink=func(action,args):commands.append({"action":action,"args":args})
 var paid: Dictionary=sim.player.organs[3]
 game.cell_ui.open_context({"kind":"organ","id":paid.id})
 var recycle=game.cell_ui.choices.filter(func(button):return button.caption=="Recycle")[0]
 sim.player.organs=sim.player.organs.duplicate(true);sim.player.organ_by_id(paid.id).charge_flash=.9
 var before: int=sim.evolution.points
 recycle.pressed.emit()
 check(commands==[{"action":"remove","args":{"id":paid.id}}],"Multiplayer sends the stable ID after dictionary replacement")
 check(sim.evolution.points==before and not sim.player.organ_by_id(paid.id).is_empty(),"The browser never grants a guessed local refund or removes authority anatomy")
 sim.remote_client=false
 game.queue_free();await process_frame
 print("RECYCLING: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
