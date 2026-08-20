extends CanvasLayer
## TouchControls (Chunk 3) - minimal functional HUD.
##
## Gives the crank flashlight system real on-screen buttons instead of the
## old two-finger-tap debug toggle, plus an energy bar so you can actually
## see the dynamo charge while testing on-phone. Movement/look themselves
## stay in Player.gd as screen-drag zones (left half = move, right half =
## look) - this layer only needs to hold buttons that must NOT eat those
## drags, which is why every button below sets mouse_filter = STOP while
## the root Control stays MOUSE_FILTER_IGNORE.
##
## This is a functional but intentionally plain HUD. The real main menu,
## pause menu, clue tracker and death screen (Chunk 5) replace/extend this
## - it is NOT a placeholder to be deleted like DebugFlyCam was; the crank
## and light buttons stay, they'll just get restyled.
##
## Built entirely in code (no hand-authored HUD .tscn) for the same reason
## Chunk 2 generated level geometry from JSON instead of hand-placing
## nodes: there's no live editor available here to visually catch a
## misplaced anchor or offset, so keeping the layout in one script keeps
## it easy to re-check by reading numbers instead of hunting a scene tree.

var _player: Node = null
var _energy_bar: ProgressBar
var _crank_button: Button
var _flashlight_button: Button

func _ready() -> void:
	layer = 10
	_player = get_tree().get_first_node_in_group("player")
	_build_ui()
	if _player:
		_player.energy_changed.connect(_on_energy_changed)

func _build_ui() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Flashlight energy bar (top of screen) ---
	_energy_bar = ProgressBar.new()
	_energy_bar.name = "EnergyBar"
	_energy_bar.min_value = 0.0
	_energy_bar.max_value = 1.0
	_energy_bar.value = 0.5
	_energy_bar.show_percentage = false
	_energy_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_energy_bar.offset_left = 40
	_energy_bar.offset_right = -40
	_energy_bar.offset_top = 28
	_energy_bar.offset_bottom = 56
	_energy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.85, 0.7, 0.25)
	fill_style.corner_radius_top_left = 6
	fill_style.corner_radius_top_right = 6
	fill_style.corner_radius_bottom_left = 6
	fill_style.corner_radius_bottom_right = 6
	_energy_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.08, 0.65)
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	_energy_bar.add_theme_stylebox_override("background", bg_style)

	root.add_child(_energy_bar)

	# --- Flashlight toggle button (bottom right, lower) ---
	_flashlight_button = Button.new()
	_flashlight_button.name = "FlashlightButton"
	_flashlight_button.text = "LIGHT"
	_flashlight_button.custom_minimum_size = Vector2(220, 220)
	_flashlight_button.add_theme_font_size_override("font_size", 30)
	_flashlight_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_flashlight_button.offset_left = -250
	_flashlight_button.offset_top = -270
	_flashlight_button.offset_right = -30
	_flashlight_button.offset_bottom = -50
	_flashlight_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_flashlight_button.pressed.connect(_on_flashlight_pressed)
	root.add_child(_flashlight_button)

	# --- Crank button (hold to charge), bottom right, above the light button ---
	_crank_button = Button.new()
	_crank_button.name = "CrankButton"
	_crank_button.text = "CRANK"
	_crank_button.custom_minimum_size = Vector2(220, 220)
	_crank_button.add_theme_font_size_override("font_size", 30)
	_crank_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_crank_button.offset_left = -250
	_crank_button.offset_top = -510
	_crank_button.offset_right = -30
	_crank_button.offset_bottom = -290
	_crank_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_crank_button.button_down.connect(_on_crank_down)
	_crank_button.button_up.connect(_on_crank_up)
	root.add_child(_crank_button)

func _on_flashlight_pressed() -> void:
	if _player:
		_player.toggle_flashlight()

func _on_crank_down() -> void:
	if _player:
		_player.start_crank()

func _on_crank_up() -> void:
	if _player:
		_player.stop_crank()

func _on_energy_changed(current: float, max_energy: float) -> void:
	if max_energy > 0.0:
		_energy_bar.value = current / max_energy
