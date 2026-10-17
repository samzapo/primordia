extends RefCounted
const Sim=preload("res://scripts/simulation.gd")
class GradientFixture extends Sim:
 var light:=.8
 var gradient_reads:=0
 func light_at(_at: Vector2) -> float:return light
 func light_direction(_at: Vector2) -> Vector2:
  gradient_reads+=1;return Vector2.RIGHT
static func fixture(gene: String="shade_leaf"):
 var sim=GradientFixture.new(891,0,false)
 sim.cells=[sim.player];sim.player.organs.clear()
 sim.player.add_organ("photosynthesis",0,"graze",false);sim.player.organs[0].mutation=gene
 sim.player.add_organ("propulsion",PI,"graze",false)
 sim.player.sense_clock=0
 return sim
static func listen(sim,h: float,received: bool=false) -> void:
 for i in ceili(.6/h):
  var prepared: Dictionary={sim.player.organs[0].id:{"food":{},"reports":{},"patch":{},"output":1.0}} if received else {}
  sim._sense(sim.player,h,prepared)
static func run(check: Callable) -> void:
 for mode in [{"step":1.0/60,"resident":false},{"step":.5,"resident":false},{"step":1.0/60,"resident":true}]:
  var step: float=mode.step
  var shade=fixture();var cell=shade.player;var leaf: Dictionary=cell.organs[0]
  var rng: int=shade.rng.state;var energy: float=cell.energy
  listen(shade,step,mode.resident)
  check.call(cell.target_mode=="light" and cell.drive_active and cell.target.x<-.99,"Shade steering seeks dimmer water in fine and coarse sensing")
  check.call(cell.state=="SEEKING SOFT LIGHT","The displayed state identifies the Shade drive")
  shade.light=.1;cell.sense_clock=0;listen(shade,step,mode.resident)
  check.call(cell.target.x>.99,"A Shade specialist seeks more light when too dark")
  shade.light=.4;cell.sense_clock=0
  shade._sense(cell,step)
  check.call(cell.target_memory==0 and cell.signals.is_empty(),"Reaching soft light clears stale light memory and queued signals")
  shade.light=.8;cell.sense_clock=0;listen(shade,step,mode.resident)
  cell.specialize(leaf.id,"sun_leaf");cell.sense_clock=10;shade._sense(cell,step)
  check.call(cell.target_memory==0 and cell.signals.is_empty(),"Changing to Sun discards previously queued shade-directed intentions")
  cell.sense_clock=0;listen(shade,step,mode.resident)
  check.call(cell.target.x>.99,"Sun specialization still seeks brighter water")
  leaf["steering"]=0;shade._sense(cell,step)
  check.call(cell.target_memory>0 and cell.target.x>.99,"Legacy Steering Off no longer disables automatic light preference")
  check.call(shade.rng.state==rng and cell.energy==energy,"Light preference consumes no ecological RNG or hidden ATP")
 var quiet=fixture();quiet.light=.4
 var stranger=quiet._make_cell(quiet.player.position+Vector2(80,0),"hunter")
 var report: Dictionary=quiet._emit_pheromone(stranger)
 report.p=quiet.player.organ_position(quiet.player.organs[0]);report.expires_at=quiet.time+10
 quiet.grid.rebuild(quiet.particles)
 if quiet.kernels!=null:
  quiet.habitat_geometry=preload("res://scripts/habitat.gd").new(891)
  quiet.habitat_geometry.enabled=false
  check.call(quiet.enable_particle_pool(),"Quiet-band light fixture uses authoritative native packets")
 listen(quiet,1.0/60)
 check.call(quiet.player.target_memory==0 and quiet.player.signals.is_empty(),"A satisfied Shade leaf never mistakes nearby pheromones for a light cue")
 var cadence=fixture();listen(cadence,1.0/60)
 check.call(cadence.gradient_reads<=6,"Light gradients retain the ordinary 0.15-second sensory cadence")
 var mixed=fixture()
 listen(mixed,1.0/60)
 mixed.player.add_organ("photosynthesis",PI,"graze",false)
 var sun: Dictionary=mixed.player.organs[-1];sun.mutation="sun_leaf"
 sun["steering"]=4;mixed.player.sense_clock=0;listen(mixed,1.0/60)
 check.call(mixed.player.target.x<-.99,"Retired percentages cannot override a coherent remembered light preference")
 mixed.player.add_organ("sensing",1,"flee",false);var flight: Dictionary=mixed.player.organs[-1]
 mixed.player.signals.append({"p":Vector2.ZERO,"mode":"flee","score":100.0,"sample_at":mixed.time,"id":999,"at":mixed.player.position+Vector2(100,0),"organ_id":flight.id,"expires_at":mixed.time+10,"lineage":999})
 mixed._sense(mixed.player,1.0/60)
 check.call(mixed.player.target_mode=="flee" and mixed.player.target.x<0,"Flight still overrides photosynthetic light preferences")
 var sim=Sim.new(81,0,false);var cell=sim.player
 cell.organs.clear();cell.add_organ("photosynthesis",0,"graze",false)
 var leaf: Dictionary=cell.organs[0];var sites:=0
 for y in range(0,2560,256):
  for x in range(0,4096,256):
   cell.position=Vector2(x,y);leaf.mutation="shade_leaf"
   var at: Vector2=cell.organ_position(leaf);var light: float=sim.light_at(at)
   var direction: Vector2=sim._photosynthetic_direction(cell,leaf);var gradient: Vector2=sim.light_direction(at)
   var expected: float=-1 if light>.45 else 1 if light<.35 else 0
   check.call(direction.is_equal_approx(gradient*expected),"Shade preference follows the actual periodic, weather-scaled field")
   sites+=1
 sim.environment["light"]=.05
 check.call(sim._photosynthetic_direction(cell,leaf).dot(sim.light_direction(cell.organ_position(leaf)))>.99,"Shade leaves seek available light during a dark environmental cycle")
 check.call(sites==160,"Actual pond checks cover both light and shade regions")
