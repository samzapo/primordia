extends "res://tests/resident_gameplay_gpu.gd"
## Focused real-device boundary regression; no timing/performance acceptance.
func run() -> void:
	Fixture.load_native()
	await exhausted_admission()
	print("RESIDENT ADMISSION: %d assertions, 0 failures" % checks)
	quit()
