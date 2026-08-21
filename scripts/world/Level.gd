extends Node3D
## Level root (Chunk 3: player spawn. Chunk 4 addition: monster spawn +
## catch handling).
##
## Moves the Player and Monster to their marker positions from
## data/level_data.json after LevelBuilder has built them, so spawn
## positions live in exactly one place (the JSON) instead of being
## duplicated here by hand.
##
## Node _ready() order in Godot runs children first, then the parent -
## so by the time this runs, LevelBuilder's _ready() has already built its
## Spawns markers and get_spawn() is safe to call.

@onready var _level_builder: Node3D = $LevelBuilder
@onready var _player: CharacterBody3D = $Player
@onready var _monster: CharacterBody3D = $Monster

func _ready() -> void:
	var start := _level_builder.get_spawn("player_start")
	if start != Vector3.ZERO:
		_player.global_position = start
	# player_start_look_at in level_data.json is straight along -Z from
	# player_start, which is the default forward direction at rotation.y
	# = 0, so no extra rotation is needed here.

	var monster_start := _level_builder.get_spawn("monster_spawn_initial")
	if monster_start != Vector3.ZERO:
		_monster.global_position = monster_start

	_monster.caught_player.connect(_on_caught_player)

func _on_caught_player() -> void:
	# Stopgap until Chunk 5's real death screen exists: just reload the
	# level. No jumpscare, no fade, no "you died" text yet - this only
	# exists so getting caught has SOME consequence instead of nothing.
	get_tree().reload_current_scene()
