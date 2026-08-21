extends CanvasLayer
## DebugHUD (temporary diagnostic tool - NOT part of the game, delete once
## the light/crank/darkness issue is actually found and fixed).
##
## Purpose: after several rounds of "I fixed it" / "nothing changed" that
## turned out to all be deploy/signing issues (now fixed), this exists to
## get hard proof instead of more guessing. It shows, live, on screen,
## in bright readable text regardless of how dark the 3D scene is:
##   - A build marker (if you don't see THIS at all, the new APK never
##     actually made it onto the phone - full stop, ignore everything
##     else on this list and go back to checking the deploy steps)
##   - The actual ambient_light_energy value Godot loaded from
##     default_env.tres at runtime (proves whether the environment file's
##     new values are really what's active, not just what's committed)
##   - Whether TouchControls found a valid Player reference
##   - The player's live energy/flashlight/cranking state, so pressing
##     the buttons and watching these numbers change (or not) shows
##     exactly which link in the chain is broken

var _label: Label

func _ready() -> void:
	layer = 100  # above everything, including TouchControls
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.offset_top = 60
	bg.offset_bottom = 240
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.offset_left = 16
	_label.offset_top = 64
	_label.offset_right = -16
	_label.offset_bottom = 236
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func _process(_delta: float) -> void:
	var lines: Array[String] = []
	lines.append("BUILD MARKER: chunk4+bugfix+keystore-fix, DebugHUD v1")

	var world_env := get_tree().get_first_node_in_group("world_environment_debug")
	var env: Environment = null
	var we := get_tree().current_scene.get_node_or_null("WorldEnvironment") if get_tree().current_scene else null
	if we and we is WorldEnvironment:
		env = (we as WorldEnvironment).environment
	if env:
		lines.append("env ambient_light_energy = %.3f (expect 0.6)" % env.ambient_light_energy)
		lines.append("env fog_density = %.4f (expect 0.008)" % env.fog_density)
	else:
		lines.append("env: NOT FOUND (WorldEnvironment node missing?)")

	var player := get_tree().get_first_node_in_group("player")
	if player:
		lines.append("player: FOUND")
		lines.append("  flashlight_on=%s  energy=%.2f  is_cranking=%s" % [
			str(player.get("flashlight_on")),
			float(player.get("energy")),
			str(player.get("is_cranking")),
		])
	else:
		lines.append("player: NOT FOUND (group 'player' empty)")

	_label.text = "\n".join(lines)
