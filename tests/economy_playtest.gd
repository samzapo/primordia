extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for seed_text in option("--seeds","41,113,20261004").split(","):
		for diet in option("--diets","grazer,photo,hunter").split(","):
			var sim = Sim.new(int(seed_text))
			var policy := option("--policy","reserve")
			sim.view_half = Sim.VIEW # half zoom, actual simulation at 60 Hz
			var started := Time.get_ticks_msec()
			var adjustments := 0
			var last_phase := -1
			if diet == "photo":
				sim.install("photosynthesis",0.7,"graze",0.75)
				sim.install("regenerative",4.2,"graze",0.5)
			elif diet == "hunter":
				sim.install("offensive",0)
				sim.install("regenerative",4.2,"graze",0.5)
			else:
				sim.install("feeding",1.2,"graze",0.75)
				sim.install("regenerative",4.2,"graze",0.5)
			sim.install("sensing" if policy == "flight" else "protection",0.4,"flee" if policy == "flight" else "graze",0.5)
			while not sim.evolution.terminal() and sim.time < 811:
				if sim.revision%60 == 0:
					var cell = sim.player
					if cell.hurt_flash > 0.2:
						for organ in cell.organs.duplicate():
							if organ.kind == "protection": cell.move_organ(organ.id,cell.last_wound)
					if cell.health < 60 and cell.brood_mass > 0: cell.reserve(-10)
					var run_state = sim.evolution
					if run_state.tide != last_phase:
						last_phase = run_state.tide
						print("TIDE ",JSON.stringify({"seed":seed_text,"diet":diet,"policy":policy,"time":sim.time,"health":cell.health,"atp":cell.energy,"mass":cell.biomass,"brood":cell.brood_mass,"need":sim.offspring_quote().material,"food":cell.processed,"fixed":cell.fixed_carbon,"kills":sim.kills}))
					if not run_state.chosen:
						var available: Array[String] = []
						for gene in run_state.offers:
							if cell.count(Sim.Genes.DATA[gene].kind) > 0: available.append(gene)
						run_state.choose(available[0] if not available.is_empty() else run_state.offers[0])
					if run_state.challenge == "": run_state.accept_challenge("stability",cell)
					for organ in cell.lost_organs.duplicate(): cell.restore_organ(organ.id)
					if cell.health < 95 and cell.count("regenerative") == 0 and cell.biomass > 6:
						if sim.install("regenerative",4.2,"graze",0.5): adjustments += 1
					if run_state.tide >= 3 and cell.count("neutralizing") == 0 and cell.biomass > 15:
						if sim.install("neutralizing",2.8,"graze",0.5): adjustments += 1
					for gene in run_state.learned:
						for organ in cell.organs:
							if organ.kind == Sim.Genes.DATA[gene].kind and organ.mutation == "" and cell.biomass > Sim.Genes.price(organ)+(8 if policy == "invest" else 22) and cell.energy > 30 and cell.health > 85:
								if sim.mutate_organ(organ.id,gene): adjustments += 1
					if run_state.offspring_id < 0 and cell.health >= 70 and cell.biomass > (20 if policy == "invest" else 12) and (cell.brood_mass < sim.offspring_quote().material or cell.brood_energy < 60):
						cell.reserve(minf(1,cell.biomass-(20 if policy == "invest" else 12)),sim.offspring_quote().material)
				sim.step(1.0/60)
			print("PLAYTEST ",JSON.stringify({"seed":seed_text,"diet":diet,"policy":policy,"result":sim.evolution.status,"reason":sim.evolution.ending,"seconds":sim.time,"food":sim.player.processed,"fixed":sim.player.fixed_carbon,"health":sim.player.health,"atp":sim.player.energy,"oxygen":sim.player.oxygen,"substrate":sim.player.substrate,"reserve_used":sim.player.reserve_used,"fermented":sim.player.fermented,"mass":sim.player.biomass,"brood":sim.player.brood_mass,"need":sim.offspring_quote().material,"points":sim.evolution.points,"viable_seconds":sim.evolution.viable_seconds,"metabolism_age":sim.evolution.metabolism_age if is_finite(sim.evolution.metabolism_age) else -1.0,"offspring_id":sim.evolution.offspring_id,"spending":sim.evolution.spending,"adjustments":adjustments,"kills":sim.kills,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0}))
	quit()
