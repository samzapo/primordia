extends RefCounted
const Sim=preload("res://scripts/simulation.gd")
func run(suite) -> void:
	var sim=Sim.new(713)
	var progression=sim.evolution
	for i in 100:progression.advance(30,sim)
	suite.expect(not progression.terminal() and progression.status=="growing","The pond has no scripted expedition ending")
	suite.expect(not progression.forecast().contains("crisis") and not progression.objective(sim).contains("crisis"),"Persistent progression exposes no crisis objective")
	var before=sim.player.ap
	for i in 200:progression.divided(sim.player)
	suite.expect(sim.player.ap==before,"Mutation opportunities do not mint AP")
	suite.expect(not progression.division_offers.is_empty(),"Actual births can offer free mutations")
	var gene: String=progression.division_offers[0]
	suite.expect(progression.accept_division_offer(gene) and gene in progression.learned,"A free birth mutation becomes a persistent discovery")
	suite.expect(not progression.accept_division_offer(gene),"The same offer cannot be accepted twice")
	suite.expect(not progression.accept_challenge("growth",sim.player),"Retired crisis challenges cannot be activated")
	sim.begin_build()
	suite.expect(sim.build_original!=null and sim.player!=sim.build_original,"Anatomy editing still clones a local paused build")
	sim.cancel_build()
	suite.expect(sim.build_original==null,"A cancelled local build leaves no staged lifecycle")
