extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Codec=preload("res://scripts/network/state_codec.gd")
const Weather=preload("res://scripts/environment_cycle.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var sim=Sim.new(51,0,false);sim.cells=[sim.player]
	var first:=1792065600.0 # Fixed calendar input, never the test machine clock.
	check(Weather.update(sim,first),"Hourly conditions initialize")
	var environment: Dictionary=sim.environment.duplicate(true)
	var tide: PackedVector2Array=sim.fluid.tide.duplicate()
	check(not Weather.update(sim,first+300) and sim.environment==environment and sim.fluid.tide==tide,"Conditions are fixed within the hour")
	# Upgrade the reduced-current revision without replacing any actual velocity.
	sim.environment.flow_version = 1
	for i in sim.fluid.tide.size(): sim.fluid.tide[i] *= .35
	var water_before: PackedVector2Array = sim.fluid.velocity.duplicate()
	check(Weather.update(sim,first+300) and sim.fluid.tide==tide and sim.environment==environment,"The reduced-current save refreshes to the original ambient strength within the same hour")
	check(sim.fluid.velocity==water_before,"Restoring the ambient target preserves every saved water velocity")

	var recovered=Codec.new().restore(Codec.new().capture(sim))
	check(not Weather.update(recovered,first+600) and recovered.environment==environment,"Saved conditions do not reroll on restart")
	check(Weather.update(sim,first+3600) and int(sim.environment.hour)==int(environment.hour)+1,"A new hour resamples calendar-derived conditions")
	Weather.update(recovered,first+3600)
	check(recovered.environment==sim.environment and recovered.fluid.tide==sim.fluid.tide,"Same pond and calendar hour produce identical conditions")
	print("ENVIRONMENT CYCLE: %d assertions, %d failures" % [assertions,failures]);quit(0 if failures==0 else 1)
