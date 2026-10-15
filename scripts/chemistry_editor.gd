extends PanelContainer
## Read-only, cell-local explanation of the current food lifecycle.
var game
var inspected:=Label.new()
func initialize(owner_game) -> void:
	game=owner_game;z_index=30
	var column:=VBoxContainer.new();add_child(column)
	var title:=Label.new();title.text="Food vacuoles";column.add_child(title)
	inspected.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(inspected)
	var close_button:=Button.new();close_button.text="Close";close_button.pressed.connect(hide);column.add_child(close_button)
	hide()
func open_cell() -> void:
	if not game.build_open or game.world.player.dead:return
	size=Vector2(minf(420,game.get_viewport_rect().size.x-32),210)
	position=(game.get_viewport_rect().size-size)*.5;show();_process(0)
func _process(_dt: float) -> void:
	if not visible:return
	if not game.build_open:hide();return
	var cell=game.world.player
	inspected.text="Nutrients enter through the oral groove and circulate in food vacuoles. Digestion makes ATP and biomass directly. Remaining waste travels to the cytoproct and is expelled.\n\nFood %.2f · waste %.2f\nATP %.1f · biomass %.1f\nReproduction: %.1f ATP · %.1f tissue reserved" % [cell.substrate,cell.waste,cell.energy,cell.biomass,cell.brood_energy,cell.brood_mass]
