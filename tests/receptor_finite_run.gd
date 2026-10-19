extends SceneTree
const Cell=preload("res://scripts/cell.gd")
const Sim=preload("res://scripts/simulation.gd")
const Host=preload("res://scripts/network/world_host.gd")
const Validity=preload("res://scripts/network/world_validity.gd")
var assertions:=0
var failures:=0
class BrokenTick:
 extends "res://scripts/simulation.gd"
 func step(_dt: float) -> void:player.energy=NAN
class LostGPU:
 extends "res://scripts/simulation.gd"
 func step(_dt: float) -> void:resident=null
class GuardedHost:
 extends "res://scripts/network/world_host.gd"
 var failure:=""
 var recoveries:=0
 func _fatal(reason: String) -> void:running=false;failure=reason
 func _recover_families(_dt: float) -> void:recoveries+=1
func check(ok: bool,message: String) -> void:
 assertions+=1
 if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 for kind in Cell.RECEPTORS:
  for damaged in [false,true]:
   for zero_atp in [false,true]:
    var cell=Cell.new(100);cell.organs.clear();cell.biomass=0;cell.energy=0 if zero_atp else 1
    check(cell.add_organ(kind,0,"graze",false),"Free receptor can be installed")
    if zero_atp:cell.add_organ("regenerative",PI,"graze",false)
    var organ: Dictionary=cell.organs[0]
    if damaged:organ.hp-=5
    var hp: float=organ.hp;var energy: float=cell.energy;var matter: float=cell.organic_mass()
    cell.heal(1.0/30)
    check(is_finite(cell.biomass) and is_finite(cell.energy) and is_finite(organ.hp),"Empty biomass with a free receptor never creates NaN")
    check(cell.biomass==0 and cell.energy>=0 and cell.energy<=energy,"Repair cannot create ATP or material")
    check(absf(cell.organic_mass()-matter)<.000001,"Free receptor repair preserves represented material")
    check(organ.hp>hp if damaged else organ.hp==hp,"Repair only restores actual damage, including zero-material receptors")
 var paid=Cell.new();paid.organs.clear();paid.add_organ("photosynthesis",0,"graze",false);paid.biomass=0;paid.energy=10
 paid.organs[0].hp-=5;var hp: float=paid.organs[0].hp;paid.heal(.1)
 check(paid.organs[0].hp==hp and paid.energy==10,"Ordinary material-bearing organs still require biomass for repair")
 var sim=Sim.new(4,0,false);sim.cells=[sim.player]
 check(Validity.error(sim)=="","Legitimate NaN oral-angle and infinite sensing deadlines remain valid")
 sim.player.energy=NAN
 check(Validity.error(sim).contains("energy"),"Nonfinite ATP is rejected")
 sim.player.energy=1;sim.fluid.velocity[0]=Vector2(INF,0)
 check(Validity.error(sim).contains("water"),"Invalid water is rejected")
 sim.fluid.velocity[0]=Vector2.ZERO
 var authority=Host.new();authority.cpu=true;authority.world=sim
 authority.store.directory=ProjectSettings.globalize_path("res://build/finite-checkpoint-"+str(OS.get_process_id()))
 check(authority.checkpoint(),"Healthy fixture checkpoint publishes")
 var filename: String=authority.store.directory.path_join("world-1.pworld")
 var before:=FileAccess.get_file_as_bytes(filename)
 sim.player.energy=NAN
 check(not authority.checkpoint() and authority.store.last_error.contains("energy"),"Invalid resources refuse checkpoint rotation")
 check(FileAccess.get_file_as_bytes(filename)==before and not FileAccess.file_exists(authority.store.directory.path_join("world-0.pworld")),"Last healthy generation remains byte-exact after refusal")
 authority.world=null;authority.free();DirAccess.remove_absolute(filename);DirAccess.remove_absolute(filename.get_base_dir())
 for gpu_lost in [false,true]:
  var host=GuardedHost.new();host.cpu=not gpu_lost;host.world=LostGPU.new(3,0,false) if gpu_lost else BrokenTick.new(3,0,false);host.running=true
  host.world.cells=[host.world.player]
  host._physics_process(1.0/30)
  check(not host.running and not host.failure.is_empty() and host.recoveries==0,"Bad tick/GPU fallback stops authority before lineage recovery can run")
  host.world=null;host.free()
 print("RECEPTOR FINITE: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
