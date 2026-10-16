extends RefCounted
## One calendar-derived weather sample per UTC hour, shared by every camera.
static func update(sim, unix_seconds: float) -> bool:
	var hour_key:=floori(unix_seconds/3600.0)
	if int(sim.environment.get("hour",-1))==hour_key and int(sim.environment.get("flow_version",0))>=1:return false
	var date:=Time.get_datetime_dict_from_unix_time(hour_key*3600)
	var random:=RandomNumberGenerator.new();random.seed=sim.seed_value^(hour_key*1000003)
	var clouds: Array=[["Clear",1.05],["Hazy",.85],["Cloudy",.65],["Overcast",.45]]
	var weather: Array=clouds[random.randi_range(0,clouds.size()-1)]
	var day: float=maxf(0,sin((float(date.hour)-6)/24.0*TAU))
	var season:=.85+.15*cos((float(date.month)-6)/12.0*TAU)
	var light: float=clampf((.22+.78*day)*season*float(weather[1]),.12,1.1)
	sim.environment={"hour":hour_key,"utc":"%04d-%02d-%02d %02d:00 UTC" % [date.year,date.month,date.day,date.hour],"weather":weather[0],"light":light,"flow_version":1}
	# Change the existing driven-current target only on the hourly boundary.
	# Velocity responds through the existing finite-mass medium, without resets.
	var angle:=random.randf_range(-.7,.7);var strength:=random.randf_range(.65,1.3)
	for i in sim.fluid.tide.size():
		var at: Vector2=Vector2(i%sim.Medium.COLS+.5,int(i/sim.Medium.COLS)+.5)*sim.Medium.SIZE
		sim.fluid.tide[i]=sim.fluid.current(at).rotated(angle)*strength
	return true
