extends CanvasLayer

@onready var label: Label = $Label
var _env: Environment = null

func _ready() -> void:
	var world_env := get_tree().get_first_node_in_group("world_environment")
	if world_env == null:
		# fall back to searching the tree directly if not grouped
		for node in get_tree().get_nodes_in_group("player"):
			pass
	_env = _find_environment(get_tree().root)

func _find_environment(node: Node) -> Environment:
	if node is WorldEnvironment:
		return (node as WorldEnvironment).environment
	for child in node.get_children():
		var found := _find_environment(child)
		if found:
			return found
	return null

func _process(_delta: float) -> void:
	var text := "BUILD MARKER: chunk4+bugfix+keystore-fix+group-fix, DebugHUD v2\n"
	if _env:
		text += "env ambient_light_energy = %.3f (expect 0.6)\n" % _env.ambient_light_energy
		text += "env fog_density = %.4f (expect 0.008)\n" % _env.fog_density
	else:
		text += "env: WorldEnvironment not found\n"

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		text += "player: NOT FOUND (group 'player' empty)\n"
	else:
		var p = players[0]
		text += "player: FOUND\n"
		text += "  flashlight_on=%s  energy=%.2f  is_cranking=%s\n" % [p.flashlight_on, p.energy, p.is_cranking]

	label.text = text
