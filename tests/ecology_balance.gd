extends SceneTree
## Paired seeded on/offscreen fixtures. Endowments are explicit test inputs.
const Sim = preload("res://scripts/simulation.gd")
const Test = preload("res://tests/offscreen_ecology.gd")
func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name+"="): return arg.substr(name.length()+1)
	return fallback
func _initialize() -> void: run.call_deferred()
func fixture(seed_value: int, mode: String, hidden: bool):
	var sim = Test.fixture(seed_value)
	var cell = sim.player
	sim.view_half = Sim.VIEW*0.5/0.8
	if not hidden:
		sim.camera_position = cell.position
		sim.camera_follows_player = true
	sim.offscreen_ecology.period = float(option("--period","1"))
	cell.organs.clear()
	if mode.begins_with("hunt"):
		cell.body = 110
		cell.biomass = 40
		cell.update_geometry()
		cell.membrane = Sim.Cell.Membrane.new(cell.radius,seed_value)
		cell.add_organ("hunting",0,"hunt",false)
		cell.add_organ("offensive",0.45,"graze",false)
		cell.add_organ("offensive",-0.45,"graze",false)
		cell.add_organ("feeding",1.4,"graze",false)
		cell.add_organ("propulsion",PI,"graze",false)
		var prey = sim._make_cell(cell.position+Vector2(145,0),"grazer")
		prey.role = "ancestor"
		prey.organs.clear()
		prey.angle = PI*0.35
		if mode == "hunt_armored":
			for angle in [0.0,1.4,2.8,4.2]: prey.add_organ("protection",angle,"graze",false)
			prey.add_organ("regenerative",5.4,"graze",false)
		if mode == "hunt_flee":
			prey.add_organ("sensing",0,"flee",false)
			prey.add_organ("propulsion",PI,"graze",false)
			prey.add_organ("propulsion",2.0,"graze",false)
		prey.update_geometry()
		cell.update_geometry()
	else:
		if mode in ["graze","scarce","hybrid"]: cell.add_organ("feeding",0,"graze",false)
		if mode in ["photo","hybrid"]: cell.add_organ("photosynthesis",1.3,"graze",false)
		cell.add_organ("propulsion",PI,"graze",false)
		var random := RandomNumberGenerator.new()
		random.seed = seed_value
		var count := 30 if mode == "scarce" else 250
		for i in count:
			var at: Vector2 = cell.position+Vector2.from_angle(random.randf()*TAU)*random.randf_range(65,300)
			sim.spawn_particle(sim.NUTRIENT,at,Vector2.ZERO,0.3,900)
		for i in 240:
			var at: Vector2 = cell.position+Vector2.from_angle(random.randf()*TAU)*random.randf_range(65,300)
			sim.spawn_particle(sim.OXYGEN if i%2 else sim.CARBON,at,Vector2.ZERO,0.4,900)
	cell.update_geometry()
	sim.rng.seed = seed_value
	sim.ecology_rng.seed = seed_value
	return sim
func run() -> void:
	var seeds := int(option("--seeds","4"))
	var seconds := float(option("--seconds","30"))
	for mode in option("--modes","graze,scarce,photo,hybrid,hunt,hunt_armored,hunt_flee").split(","):
		for hidden in ([true] if option("--views","both") == "hidden" else [false,true]):
			var rows: Array = []
			for seed_value in seeds:
				var sim = fixture(int(option("--seed-start","720"))+seed_value,mode,hidden)
				var actor = sim.player
				var baseline: float = actor.organic_mass()
				var initial: float = Test.organic(sim)
				var victim = sim.cells[1] if sim.cells.size() > 1 else null
				var started := Time.get_ticks_usec()
				for i in roundi(seconds*60):
					sim.step(1.0/60)
					if actor.dead: break
				if not actor.dead and actor.coarse_elapsed > 0:
					sim.offscreen_ecology.advance(sim,actor,actor.coarse_elapsed,true)
					actor.coarse_elapsed = 0
				var elapsed := (Time.get_ticks_usec()-started)/1000.0
				rows.append({"seed":int(option("--seed-start","720"))+seed_value,"gain":actor.organic_mass()-baseline,"biomass":actor.biomass,"eaten":actor.eaten,"processed":actor.processed,"fixed":actor.fixed_carbon,"atp":actor.energy,"health":actor.health,"alive":not actor.dead,"prey_dead":victim != null and victim.dead,"age":actor.age,"mass_error":Test.organic(sim)-initial,"cpu_ms_per_tick":elapsed/maxf(1,sim.time*60),"particles":sim.particles.size()})
			var means := {}
			for key in ["gain","biomass","eaten","processed","fixed","atp","health","age","cpu_ms_per_tick","particles"]:
				var total := 0.0
				for row in rows: total += row[key]
				means[key] = total/rows.size()
			means["survival"] = rows.filter(func(row): return row.alive).size()/float(rows.size())
			means["kills"] = rows.filter(func(row): return row.prey_dead).size()/float(rows.size())
			print("ECOLOGY_BALANCE ",JSON.stringify({"mode":mode,"hidden":hidden,"period":float(option("--period","1")),"seconds":seconds,"seeds":seeds,"mean":means,"rows":rows}))
	quit()
