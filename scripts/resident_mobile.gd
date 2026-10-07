extends Control
## Touch launcher for the isolated benchmark export, never the gameplay HUD.
const Runner = preload("res://scripts/resident_benchmark.gd")
var runner
var menu := VBoxContainer.new()
var status := Label.new()
var counts := OptionButton.new()
var modes := OptionButton.new()
var lanes := OptionButton.new()
var durations := OptionButton.new()
var pacing := OptionButton.new()
var distributions := OptionButton.new()
var stop := Button.new()
var last_report := ""
func _ready() -> void:
	preload("res://scripts/resident_fixture.gd").load_native()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := MarginContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: panel.add_theme_constant_override("margin_"+side,24)
	add_child(panel);panel.add_child(menu)
	menu.add_theme_constant_override("separation",12)
	menu.add_theme_font_size_override("font_size",26)
	var title := Label.new()
	title.text="Primordia · GPU particle experiment"
	title.add_theme_font_size_override("font_size",32);menu.add_child(title)
	var note := Label.new()
	note.text="Transport + artwork only. No collisions, chemistry or cells.\nThis measures a prototype, not game FPS."
	note.add_theme_font_size_override("font_size",22);menu.add_child(note)
	for n in [5000,20000,50000,100000]: counts.add_item(str(n))
	counts.select(2);add_choice("Particle count",counts)
	modes.add_item("GPU resident")
	modes.add_item("Native CPU + texture")
	modes.add_item("Native CPU + MultiMesh")
	if not ClassDB.class_exists("PrimordiaResidentReference"):
		modes.set_item_disabled(1,true);modes.set_item_disabled(2,true)
	add_choice("Backend",modes)
	for n in [1,2,4,8]: lanes.add_item(str(n))
	add_choice("CPU lanes",lanes)
	for n in [30,60,600]: durations.add_item(str(n)+" seconds")
	durations.select(1);add_choice("Duration",durations)
	for name in ["30 FPS cap","60 FPS cap"]: pacing.add_item(name)
	pacing.select(1);add_choice("Frame pacing",pacing)
	distributions.add_item("uniform");distributions.add_item("clustered");distributions.add_item("seam")
	add_choice("Distribution",distributions)
	var start := Button.new()
	start.text="Run benchmark";start.pressed.connect(_start);start.add_theme_font_size_override("font_size",26);menu.add_child(start)
	var copy := Button.new()
	copy.text="Copy last report JSON"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(last_report))
	copy.add_theme_font_size_override("font_size",26);menu.add_child(copy)
	status.add_theme_font_size_override("font_size",22)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.text="Reports save under user://. Record device heat, battery and brightness separately."
	menu.add_child(status)
	stop.text="Stop benchmark"
	stop.add_theme_font_size_override("font_size",26)
	stop.position=Vector2(20,20);stop.visible=false
	stop.pressed.connect(func(): if runner!=null: runner.cancel())
	add_child(stop)
func add_choice(label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var text := Label.new();text.text=label;text.custom_minimum_size.x=220
	text.add_theme_font_size_override("font_size",26)
	row.add_child(text);row.add_child(control);control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	control.add_theme_font_size_override("font_size",26)
	menu.add_child(row)
func _start() -> void:
	menu.visible=false;stop.visible=true
	runner=Runner.new()
	runner.count=[5000,20000,50000,100000][counts.selected]
	runner.backend=["gpu","cpu-texture","cpu-multimesh"][modes.selected]
	runner.threads=[1,2,4,8][lanes.selected]
	runner.seconds=[30.0,60.0,600.0][durations.selected]
	runner.fps_limit=[30,60][pacing.selected]
	runner.distribution=distributions.get_item_text(distributions.selected)
	runner.output="user://resident-%d.json"%Time.get_unix_time_from_system()
	add_child(runner)
	move_child(runner,0)
	runner.finished.connect(_finished,CONNECT_ONE_SHOT)
	runner.begin()
func _finished(report: Dictionary) -> void:
	last_report=JSON.stringify(report)
	status.text=str(report.get("error","Finished. Report: "+runner.output+"\nCopy JSON or retrieve the file. Compare equal durations after cooldown."))
	runner.queue_free();runner=null
	menu.visible=true;stop.visible=false
func _notification(what: int) -> void:
	# Suspension invalidates a sustained foreground run; do not pretend catch-up
	# after switching apps is a measured thermal interval.
	if what==NOTIFICATION_APPLICATION_PAUSED and runner!=null: runner.cancel()
