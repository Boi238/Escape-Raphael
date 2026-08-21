extends CanvasLayer
## DebugHUD v2 (temporary diagnostic overlay).
##
## Purpose: give hard on-screen proof of what build is actually running
## and what state the game is really in, instead of relying on visual
## impressions like "still dark" which can be caused by several
## different unrelated bugs. DELETE THIS FILE + its Level.tscn node
## once the group-fix is confirmed working and Chunk 5 starts.
##
## v2 changes from v1: build marker bumped, and once the player is
## FOUND it now also prints live flashlight_on / energy / is_cranking
## values pulled directly from Player.gd, so future light/crank/energy
## bugs (if any) show up as data instead of another "it's still dark"
## report.

const BUILD_MARKER := "group-fix, DebugHUD v2"

var _label: Label

func _ready() -> void:
	layer = 100  # render above TouchControls (layer 10)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.offset_left = 8
	_label.offset_top = 8
	_label.offset_right = -8
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_label.add_theme_font_size_override("font_size", 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_label)

func _process(_delta: float) -> void:
	var lines := []
	lines.append("BUILD MARKER: %s" % BUILD_MARKER)

	var env := get_viewport().world_3d.environment
	if env:
		lines.append("env ambient_light_energy = %.3f (expect 0.6)" % env.ambient_light_energy)
		lines.append("env fog_density = %.4f (expect 0.008)" % env.fog_density)
	else:
		lines.append("env: NOT FOUND")

	var player := get_tree().get_first_node_in_group("player")
	if player:
		lines.append("player: FOUND")
		lines.append("  flashlight_on = %s" % str(player.flashlight_on))
		lines.append("  energy = %.2f / %.2f" % [player.energy, player.MAX_ENERGY])
		lines.append("  is_cranking = %s" % str(player.is_cranking))
	else:
		lines.append("player: NOT FOUND (group 'player' empty)")

	_label.text = "\n".join(lines)
