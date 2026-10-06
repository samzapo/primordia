extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var gpu = load("res://scripts/gpu_transport.gd").new()
	if not gpu.initialize():
		push_error("A RenderingDevice renderer and GPU are required")
		quit(1)
		return
	var cpu = Sim.new(713)
	var accelerated = Sim.new(713)
	for sim in [cpu,accelerated]:
		for i in 120: sim.spawn_particle(Sim.PHEROMONE,sim.player.position+Vector2(i*3-180,i%7*11))
	cpu.view_half=Vector2(4000,3000)
	accelerated.view_half=cpu.view_half
	accelerated.gpu_transport=gpu
	cpu._move_particles(1.0/60)
	accelerated._move_particles(1.0/60)
	var error := 0.0
	var angle_error := 0.0
	for i in cpu.particles.size():
		error=maxf(error,Sim.Medium.offset(cpu.particles[i].p,accelerated.particles[i].p).length())
		angle_error=maxf(angle_error,absf(wrapf(cpu.particles[i].angle-accelerated.particles[i].angle,-PI,PI)))
	print("GPU_PARITY ",JSON.stringify({"max_position_error":error,"max_angle_error":angle_error,"particles":cpu.particles.size(),"device":rd_name(gpu)}))
	if error>0.005 or angle_error>0.00001:
		push_error("GPU transport diverges beyond floating-point tolerance")
		gpu.close()
		quit(1)
		return
	if not edge_parity(gpu):
		gpu.close()
		quit(1)
		return
	# Promotion after a dormant interval uses the same coarse integrator.
	for sim in [cpu,accelerated]:
		sim.transport_clock += 0.5
	cpu._move_particles(1.0/60)
	accelerated._move_particles(1.0/60)
	error = 0.0
	for i in cpu.particles.size():
		error = maxf(error,Sim.Medium.offset(cpu.particles[i].p,accelerated.particles[i].p).length())
	print("GPU_COARSE_PARITY ",JSON.stringify({"max_position_error":error}))
	if error > 0.008:
		push_error("GPU coarse promotion diverged")
		gpu.close()
		quit(1)
		return
	# Resident work is a transport-only throughput ceiling, not whole-game FPS.
	for count in [4096,16384,65536]:
		var data := PackedFloat32Array()
		data.resize(count*12)
		for i in count:
			data[i*12]=fposmod(i*53.7,4096)
			data[i*12+1]=fposmod(i*73.9,2560)
			data[i*12+3]=0.3
			data[i*12+11]=1
		gpu.upload(data,cpu.fluid.velocity)
		gpu.dispatch(count,1.0/60,20)
		var samples: Array[int]=[]
		for i in 20:
			var begin:=Time.get_ticks_usec()
			gpu.dispatch(count,1.0/60,60)
			samples.append(Time.get_ticks_usec()-begin)
		samples.sort()
		print("GPU_RESIDENT ",JSON.stringify({"particles":count,"batch_ticks":60,"batch_median_ms":samples[10]/1000.0,"amortized_transport_ms":samples[10]/60000.0,"note":"Persistent state; no chemistry/cells/rendering or per-tick CPU readback. Noise is zero in this throughput fixture."}))
	gpu.close()
	quit()
func rd_name(gpu) -> String: return gpu.rd.get_device_name()

func edge_parity(gpu) -> bool:
	var cpu = Sim.new(815)
	var accelerated = Sim.new(815)
	for sim in [cpu,accelerated]:
		sim.camera_follows_player = false
		sim.camera_position = Vector2(4070,2510)
		sim.view_half = Vector2(500,300)
		sim.particles.clear()
		sim.pheromones.clear()
		sim.grid.clear()
		for offset in [Vector2(490,290),Vector2(-490,-290),Vector2(560,0),Vector2(596,0),Vector2(700,0)]:
			sim.spawn_particle(Sim.NUTRIENT,sim.camera_position+offset,Vector2(20,8),0.3)
		sim.rng.seed = 83
	accelerated.gpu_transport = gpu
	cpu._move_particles(0.02)
	accelerated._move_particles(0.02)
	var error := 0.0
	var age_error := 0.0
	for i in cpu.particles.size():
		error = maxf(error,Sim.Medium.offset(cpu.particles[i].p,accelerated.particles[i].p).length())
		age_error = maxf(age_error,absf(accelerated.particles[i].age-[0.02,0.02,0.02,0.02,0.0][i]))
	var passed: bool = error < 0.005 and age_error < 0.000001 and accelerated.active_particles == 4
	print("GPU_EDGE_PARITY ",JSON.stringify({"max_position_error":error,"max_age_error":age_error,"active":accelerated.active_particles,"passed":passed}))
	if not passed: push_error("GPU viewport corners, offscreen fade or wrapped halo diverged")
	return passed
