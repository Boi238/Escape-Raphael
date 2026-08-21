extends CanvasLayer

@onready var crank_button: Button = $CrankButton
@onready var light_button: Button = $LightButton
@onready var energy_bar: ProgressBar = $EnergyBar

var _player: Node3D = null

func _ready() -> void:
	crank_button.button_down.connect(_on_crank_down)
	crank_button.button_up.connect(_on_crank_up)
	light_button.pressed.connect(_on_light_pressed)
	_try_bind_player()

func _process(_delta: float) -> void:
	# Self-heals if the player wasn't ready yet on the first attempt —
	# harmless now that add_to_group("player") actually runs in Player.gd,
	# but kept as a safety net so a scene-load order change can't silently
	# break the buttons again.
	if _player == null:
		_try_bind_player()

func _try_bind_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_player = players[0]
	if not _player.energy_changed.is_connected(_on_energy_changed):
		_player.energy_changed.connect(_on_energy_changed)
	_on_energy_changed(_player.energy)

func _on_crank_down() -> void:
	if _player:
		_player.set_cranking(true)

func _on_crank_up() -> void:
	if _player:
		_player.set_cranking(false)

func _on_light_pressed() -> void:
	if _player:
		_player.toggle_flashlight()

func _on_energy_changed(new_energy: float) -> void:
	energy_bar.value = (new_energy / 14.0) * 100.0
