extends Node3D
## Level root (Chunk 3 addition).
##
## Moves the Player to the "player_start" marker from data/level_data.json
## after LevelBuilder has built it, so the spawn position lives in exactly
## one place (the JSON) instead of being duplicated here by hand.
##
## Node _ready() order in Godot runs children first, then the parent -
## so by the time this runs, LevelBuilder's _ready() has already built its
## Spawns markers and get_spawn() is safe to call.

@onready var _level_builder: Node3D = $LevelBuilder
@onready var _player: CharacterBody3D = $Player

func _ready() -> void:
	var start := _level_builder.get_spawn("player_start")
	if start != Vector3.ZERO:
		_player.global_position = start
	# player_start_look_at in level_data.json is straight along -Z from
	# player_start, which is the default forward direction at rotation.y
	# = 0, so no extra rotation is needed here.
