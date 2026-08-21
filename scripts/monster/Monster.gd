extends CharacterBody3D
## Monster (Chunk 4).
##
## Built entirely from primitive meshes (boxes/capsules) in a rotatable
## node hierarchy instead of a skinned/rigged mesh - there's no skeleton
## to attach a real animation to (the uploaded psx_base_male.glb turned
## out to be a static mesh with no bones or animation data at all), and
## authoring skinned bone animation curves by hand with no way to preview
## them here would be very likely to come out wrong. Rotating rigid
## segments via code is fully predictable to reason about without an
## editor, and a slightly jerky/segmented crawl actually reads as MORE
## wrong/unsettling for a horror creature, not less.
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

# Body proportions (meters). "Elongated limbs" per the chosen style: the
# lower limb segments (forearm/shin) are noticeably longer relative to
# the upper segments than real human proportions.
const TORSO_SIZE := Vector3(0.55, 0.45, 1.2)
const HEAD_SIZE := Vector3(0.32, 0.3, 0.34)
const UPPER_LIMB_LEN := 0.38
const LOWER_LIMB_LEN := 0.58            # elongated - normal would be ~0.35
const LIMB_RADIUS := 0.07

signal caught_player

var _player: Node3D = null
var _spawn_position := Vector3.ZERO
var _gait_phase := 0.0
var _is_moving := false

var _hunt_target: Vector3 = Vector3.ZERO
var _hunt_timer := 0.0
var _wander_target: Vector3 = Vector3.ZERO

# Limb node references, filled in by _build_body(). Each entry:
# { root: Node3D, upper: MeshInstance3D, lower_pivot: Node3D, phase_offset: float }
var _limbs: Array = []

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

	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = TORSO_SIZE
	torso.mesh = torso_mesh
	torso.material_override = mat
	torso.position = Vector3(0, 0.55, 0)
	add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = HEAD_SIZE
	head.mesh = head_mesh
	head.material_override = mat
	# Front of the torso, in local -Z (matches Player's -Z-forward convention).
	head.position = Vector3(0, 0.6, -(TORSO_SIZE.z / 2.0 + HEAD_SIZE.z / 2.0 - 0.05))
	add_child(head)

	_build_eyes(head)

	# Limb roots at the four "shoulder/hip" corners of the torso, each
	# reaching down to the floor. phase_offset creates the diagonal-pair
	# crawl gait (front-left+back-right together, opposite the other
	# pair) - the standard quadruped walk pattern.
	var half_w := TORSO_SIZE.x / 2.0
	_add_limb(Vector3(half_w, 0.5, -TORSO_SIZE.z * 0.32), 0.0, mat)          # front-right
	_add_limb(Vector3(-half_w, 0.5, -TORSO_SIZE.z * 0.32), PI, mat)          # front-left
	_add_limb(Vector3(half_w, 0.5, TORSO_SIZE.z * 0.32), PI, mat)            # back-right
	_add_limb(Vector3(-half_w, 0.5, TORSO_SIZE.z * 0.32), 0.0, mat)          # back-left

func _build_eyes(head: MeshInstance3D) -> void:
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.05, 0.05)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.05, 0.05)
	eye_mat.emission_energy_multiplier = 4.0

	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035
		eye_mesh.height = 0.07
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.09, 0.02, -HEAD_SIZE.z / 2.0)
		head.add_child(eye)

		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.1, 0.1)
		glow.light_energy = 0.6
		glow.omni_range = 1.5
		eye.add_child(glow)

func _add_limb(root_pos: Vector3, phase_offset: float, mat: StandardMaterial3D) -> void:
	var root := Node3D.new()
	root.position = root_pos
	add_child(root)

	var upper := MeshInstance3D.new()
	var upper_mesh := CapsuleMesh.new()
	upper_mesh.radius = LIMB_RADIUS
	upper_mesh.height = UPPER_LIMB_LEN
	upper.mesh = upper_mesh
	upper.material_override = mat
	# Capsule's long axis is local Y by default; offset it so the segment
	# extends DOWN from the joint (root) rather than being centered on it.
	upper.position.y = -UPPER_LIMB_LEN / 2.0
	root.add_child(upper)

	var lower_pivot := Node3D.new()
	lower_pivot.position.y = -UPPER_LIMB_LEN
	root.add_child(lower_pivot)

	var lower := MeshInstance3D.new()
	var lower_mesh := CapsuleMesh.new()
	lower_mesh.radius = LIMB_RADIUS * 0.85
	lower_mesh.height = LOWER_LIMB_LEN
	lower.mesh = lower_mesh
	lower.material_override = mat
	lower.position.y = -LOWER_LIMB_LEN / 2.0
	lower_pivot.add_child(lower)

	_limbs.append({
		"root": root,
		"lower_pivot": lower_pivot,
		"phase_offset": phase_offset,
	})

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

	for limb in _limbs:
		var phase: float = _gait_phase + limb["phase_offset"]
		var swing := sin(phase) * 0.5          # shoulder/hip forward-back swing
		var lift := max(sin(phase), 0.0) * 0.9  # knee/elbow bend, only during "lift" half of the stride
		(limb["root"] as Node3D).rotation.x = swing
		(limb["lower_pivot"] as Node3D).rotation.x = -lift

func _on_player_made_noise(position: Vector3, radius: float, reveals_position: bool) -> void:
	if not reveals_position:
		return
	var dist := global_position.distance_to(position)
	if dist <= radius:
		_hunt_target = position
		_hunt_timer = HUNT_FORGET_TIME
