extends CharacterBody3D
## Monster (Chunk 4, body updated in Chunk 4.1 to use Raph_with_UV.obj).
##
## Visual body is the uploaded Raph_with_UV.obj mesh - solid black
## (procedurally cracked, no face texture), glowing red eyes, no
## identifying features. Like psx_base_male.glb before it, this is a
## single static mesh with no skeleton/bones, so it can't be given a
## real per-limb crawl animation - instead the whole mesh is pitched
## into a crouched stance and given a whole-body bob/sway/lurch while
## moving (see _animate_gait). The face-texture slot referenced by the
## included .mtl is intentionally left unset for now (shape only, no
## texture) pending a follow-up asset.
##
## Behavior (per spec):
##   - Only moves while NOT lit by the player's flashlight.
##   - Freezes the instant the light hits it - implemented as a per-frame
##     illumination check rather than a one-shot event latch, so it's
##     always correct regardless of when/how the light turns on relative
##     to the monster's position, and un-freezes just as instantly the
##     moment it's no longer lit.
##   - Hunts toward the player's exact position when GameEvents reports
##     noise with reveals_position = true (the crank), otherwise wanders.
##
## NOTE for whoever next has this open in a real Godot editor: every size/
## offset constant below was chosen by math and reasoning, not by eye -
## flag anything that looks proportioned wrong and it's a five-second
## tweak, not a rebuild.

const MOVE_SPEED := 2.6
const GAIT_CYCLE_SPEED := 5.0          # radians/sec of gait phase advance while moving
const CATCH_RADIUS := 1.0              # distance to player that counts as "caught"
const WANDER_RADIUS := 6.0             # how far from spawn it wanders when not hunting
const HUNT_FORGET_TIME := 12.0         # seconds after a noise ping before giving up the chase

# Flashlight detection - mirrors Player.gd's flashlight cone (spot_angle
# 42 deg, spot_range 22.0). Kept as separate constants (not read directly
# off the light) so this script has no hard dependency on Player's node
# structure - if those numbers change on the Player side, update here too.
const LIGHT_CONE_HALF_ANGLE_COS := 0.934   # cos(21 deg) - half of Player's 42 deg spot_angle
const LIGHT_RANGE := 22.0

# --- Body model (Chunk 4.1: replaced primitive-box body with the
# uploaded Raph_with_UV.obj shape) ---
# This is a single static mesh (~2.13m standing height in its own file
# units, no skeleton/bones - same situation as psx_base_male.glb
# earlier), so there's no way to bend it into a real four-limb crawl
# pose or drive individual limb joints like the old primitive rig did.
# What IS done instead: the whole mesh is scaled down, pitched forward
# into a crouched/crawling stance, and given a whole-body bob+sway while
# moving (see _animate_gait) so it still reads as "crawling," just as a
# single-piece lurch rather than a per-limb gait.
# MODEL_SCALE / MODEL_TILT_DEG / MONSTER_EYE_OFFSET below are estimates
# based on the file's raw vertex bounding box, not a visual preview (no
# Godot editor in this pipeline) - if the pitch or eye position looks
# off once you actually see it running, these three constants are the
# only things you need to nudge.
const MODEL_PATH := "res://assets/models/monster/Raph_with_UV.obj"
const MODEL_SCALE := 0.55                    # shrinks ~2.13m tall model to a more monster-sized ~1.15m long when tilted
const MODEL_TILT_DEG := 65.0                 # forward pitch, standing -> crouched/crawling-ish
const MODEL_EYE_LOCAL_POS := Vector3(-0.095, 1.97, -0.13)   # estimated head/face area, in the model's own (untilted, unscaled) coordinate space
const MODEL_EYE_SPACING := 0.07

signal caught_player

var _player: Node3D = null
var _spawn_position := Vector3.ZERO
var _gait_phase := 0.0
var _is_moving := false

var _hunt_target: Vector3 = Vector3.ZERO
var _hunt_timer := 0.0
var _wander_target: Vector3 = Vector3.ZERO

var _body_visual: Node3D = null   # the tilted/scaled model root - _animate_gait bobs/sways this

func _ready() -> void:
	add_to_group("monster")
	collision_layer = 4   # "monster" (see project.godot layer_names)
	collision_mask = 1    # "world" - collides with walls/floors only
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35

	_spawn_position = global_position
	_wander_target = _spawn_position

	_build_collision()
	_build_body()

	_player = get_tree().get_first_node_in_group("player")
	GameEvents.player_made_noise.connect(_on_player_made_noise)

func _build_collision() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 1.0
	var col := CollisionShape3D.new()
	col.shape = shape
	# Crawling creature's collision capsule lies on its side, roughly at
	# knee height, rather than standing upright like the player's.
	col.rotation.x = deg_to_rad(90.0)
	col.position.y = 0.5
	add_child(col)

func _make_material(base_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.roughness = 1.0
	mat.metallic = 0.0
	# Procedural noise for the "rough/cracked" surface look instead of an
	# image texture file - FastNoiseLite + NoiseTexture2D are built into
	# Godot, so this needs no external assets at all.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.35
	noise.cellular_jitter = 1.0
	noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 128
	noise_tex.height = 128
	mat.albedo_texture = noise_tex
	# Multiply so the noise only ever darkens toward the base black, never
	# lightens past it - keeps it reading as "black, but cracked" instead
	# of a visibly separate grey pattern.
	mat.uv1_triplanar = true
	return mat

func _build_body() -> void:
	var mat := _make_material(Color(0.02, 0.02, 0.02))

	var mesh := load(MODEL_PATH)
	if mesh == null:
		push_error("Monster: failed to load " + MODEL_PATH + " - falling back would require the old primitive body, which has been removed. Check the file was actually committed/pushed.")
		return

	# _body_visual is the node that gets scaled/tilted AND bobbed/swayed
	# in _animate_gait - kept separate from the CharacterBody3D root so
	# the collision capsule (built in _build_collision, already correct)
	# never moves relative to physics, only the visible mesh wiggles.
	_body_visual = Node3D.new()
	_body_visual.rotation.x = deg_to_rad(-MODEL_TILT_DEG)  # pitch forward into a crouch
	add_child(_body_visual)

	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = mesh
	body_mesh.material_override = mat
	body_mesh.scale = Vector3.ONE * MODEL_SCALE
	_body_visual.add_child(body_mesh)

	_build_eyes(body_mesh)

func _build_eyes(body_mesh: MeshInstance3D) -> void:
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.05, 0.05)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.05, 0.05)
	eye_mat.emission_energy_multiplier = 4.0

	# Parented to body_mesh (which already carries MODEL_SCALE) so eye
	# position is authored in the model's own raw coordinate space -
	# MODEL_EYE_LOCAL_POS is an estimate of the head/face area from the
	# vertex bounding box, not a verified point on the actual face.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.06
		eye_mesh.height = 0.12
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = MODEL_EYE_LOCAL_POS + Vector3(side * MODEL_EYE_SPACING, 0, 0)
		body_mesh.add_child(eye)

		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.1, 0.1)
		glow.light_energy = 0.6
		glow.omni_range = 1.5
		eye.add_child(glow)

func _physics_process(delta: float) -> void:
	var lit := _is_illuminated_by_flashlight()

	if lit:
		# Frozen: no gait advance, no movement, hold exactly current pose.
		_is_moving = false
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_update_ai_target(delta)
	_move_toward_target(delta)
	_animate_gait(delta)

func _is_illuminated_by_flashlight() -> bool:
	if _player == null:
		return false
	if not ("flashlight_on" in _player) or not _player.flashlight_on:
		return false

	var to_self: Vector3 = global_position - _player.global_position
	var dist := to_self.length()
	if dist > LIGHT_RANGE or dist < 0.001:
		return false

	# Player's forward is -Z of the Head node, which yaws/pitches with
	# look direction - global_transform.basis.z on the player body only
	# has yaw, not pitch, but the flashlight cone check only needs yaw
	# (a crawling monster is roughly floor-level, same as where the
	# camera pitches to aim anyway when tracking something on the ground).
	var forward: Vector3 = -_player.global_transform.basis.z
	var dot := forward.normalized().dot(to_self.normalized())
	return dot >= LIGHT_CONE_HALF_ANGLE_COS

func _update_ai_target(delta: float) -> void:
	if _hunt_timer > 0.0:
		_hunt_timer -= delta
		return
	# Not actively hunting - wander loosely around the spawn point so it
	# still feels alive in the dark without a full patrol-route system.
	if global_position.distance_to(_wander_target) < 0.5:
		var angle := randf() * TAU
		var r := randf() * WANDER_RADIUS
		_wander_target = _spawn_position + Vector3(cos(angle) * r, 0, sin(angle) * r)

func _move_toward_target(delta: float) -> void:
	var target := _hunt_target if _hunt_timer > 0.0 else _wander_target
	var to_target := target - global_position
	to_target.y = 0
	var dist := to_target.length()

	if dist < 0.3:
		_is_moving = false
		velocity.x = 0
		velocity.z = 0
	else:
		_is_moving = true
		var dir := to_target.normalized()
		velocity.x = dir.x * MOVE_SPEED
		velocity.z = dir.z * MOVE_SPEED
		# Face the direction of travel.
		look_at(global_position + dir, Vector3.UP)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 12.0 * delta

	move_and_slide()

	if _player and global_position.distance_to(_player.global_position) <= CATCH_RADIUS:
		caught_player.emit()

func _animate_gait(delta: float) -> void:
	if _is_moving:
		_gait_phase += GAIT_CYCLE_SPEED * delta
	# else: hold last pose rather than snapping to a fixed idle pose -
	# reads as "was mid-crawl, stopped" rather than resetting oddly.

	if _body_visual == null:
		return

	# No skeleton on this model, so there's no per-limb gait anymore -
	# instead the whole tilted body bobs up/down, sways side to side,
	# and rocks its forward pitch slightly, all driven by the same
	# _gait_phase used before. Amplitudes settle back toward 0 when not
	# moving instead of snapping, so a stop mid-lurch doesn't pop.
	var target_bob := 0.0
	var target_sway := 0.0
	var target_pitch_offset := 0.0
	if _is_moving:
		target_bob = abs(sin(_gait_phase)) * 0.12          # vertical lurch
		target_sway = sin(_gait_phase * 0.5) * 0.08         # slow side-to-side
		target_pitch_offset = sin(_gait_phase) * deg_to_rad(6.0)  # subtle forward/back rock

	var blend := 1.0 - exp(-10.0 * delta)  # smooth toward target, ~0.1s response
	_body_visual.position.y = lerp(_body_visual.position.y, target_bob, blend)
	_body_visual.position.x = lerp(_body_visual.position.x, target_sway, blend)
	_body_visual.rotation.x = lerp(_body_visual.rotation.x, deg_to_rad(-MODEL_TILT_DEG) + target_pitch_offset, blend)

func _on_player_made_noise(position: Vector3, radius: float, reveals_position: bool) -> void:
	if not reveals_position:
		return
	var dist := global_position.distance_to(position)
	if dist <= radius:
		_hunt_target = position
		_hunt_timer = HUNT_FORGET_TIME
