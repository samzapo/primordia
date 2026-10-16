extends "res://tests/network_live.gd"
func run() -> void:
	check_performance(false,"Fixture timing target missed")
	if "--functional-failure" in OS.get_cmdline_user_args():check(false,"Fixture functional guard must remain hard")
	print("POLICY_RESULT ",JSON.stringify({"failures":failures,"performance_warnings":performance_warnings}))
	quit(0 if failures==0 else 1)
