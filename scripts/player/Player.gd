extends CharacterBody3D

# ── THE FIX ───────────────────────────────────────────────────────────────
# DebugHUD (and TouchControls' lookup) both search for this node via
# get_tree().get_nodes_in_group("player") — but this script never actually
# called add_to_group("player"). Layer 2 in the physics settings is a
# COLLISION layer, not a Godot "group" — they're two separate systems.
# So every group lookup returned empty, no matter how many times it retried.
# That's why LIGHT/CRANK looked broken across every round of fixes: the
# buttons were finding nothing to call, every single time.
# ────────────────────────────────────────────────────────────────────────

signal energy_changed(new_energy: float)

const MAX_ENERGY := 14.0
const CRANK_FILL_RATE := MAX_ENERGY / 5.0   # 5s crank = full charge
const DRAIN_RATE := 1.0                      # 1 sec of energy per sec of light
const CRANK_SPEED_MULT := 0.9                # -10% while cranking
const NOISE_INTERVAL := 0.35
const NOISE_RADIUS := 30.0
const MOVE_SPEED := 4.0
const LOOK_SENSITIVITY := 0.0035
const GRAVITY := 9.8

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight

var energy: float = MAX_ENERGY
var is_cranking: bool = false
var flashlight_on: bool = false
var _noise_timer: float = 0.0

var _move_touch_index := -1
var _look_touch_index := -1
var _move_origin := Vector2.ZERO
var _move_current := Vector2.ZERO
var _look_last := Vector2.ZERO

func _ready() -> void:
	add_to_group("player")   # <-- the missing line. This alone fixes it.
	flashlight.light_energy = 0.0
	flashlight.visible = false
	energy_changed.emit(energy)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var screen_w := get_viewport().get_visible_rect().size.x
		var is_left := event.position.x < screen_w * 0.5
		if event.pressed:
			if is_left and _move_touch_index == -1:
				_move_touch_index = event.index
				_move_origin = event.position
				_move_current = event.position
			elif not is_left and _look_touch_index == -1:
				_look_touch_index = event.index
				_look_last = event.position
		else:
			if event.index == _move_touch_index:
				_move_touch_index = -1
				_move_current = _move_origin
			elif event.index == _look_touch_index:
				_look_touch_index = -1

	elif event is InputEventScreenDrag:
		if event.index == _move_touch_index:
			_move_current = event.position
		elif event.index == _look_touch_index:
			var delta: Vector2 = event.position - _look_last
			_look_last = event.position
			rotate_y(-delta.x * LOOK_SENSITIVITY)
			head.rotate_x(-delta.y * LOOK_SENSITIVITY)
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _physics_process(delta: float) -> void:
	# Gravity / floor snap
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1  # keeps snapped to ramps without stair-step logic

	# Movement from the anchored joystick (drag delta from origin, NOT
	# raw per-frame delta — that was the earlier "wonky joystick" bug and
	# stays fixed here)
	var input_dir := Vector2.ZERO
	if _move_touch_index != -1:
		var offset: Vector2 = _move_current - _move_origin
		var max_radius := 80.0
		if offset.length() > max_radius:
			offset = offset.normalized() * max_radius
		input_dir = offset / max_radius

	var speed := MOVE_SPEED
	if is_cranking:
		speed *= CRANK_SPEED_MULT

	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if input_dir.length() > 0.05:
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
	else:
		velocity.x = 0
		velocity.z = 0

	move_and_slide()

	# Crank / flashlight energy
	if is_cranking:
		energy = min(energy + CRANK_FILL_RATE * delta, MAX_ENERGY)
		energy_changed.emit(energy)
		_noise_timer += delta
		if _noise_timer >= NOISE_INTERVAL:
			_noise_timer = 0.0
			GameEvents.player_made_noise.emit(global_position, NOISE_RADIUS, true)

	if flashlight_on:
		energy = max(energy - DRAIN_RATE * delta, 0.0)
		energy_changed.emit(energy)
		if energy <= 0.0:
			set_flashlight(false)

func set_cranking(value: bool) -> void:
	is_cranking = value

func set_flashlight(value: bool) -> void:
	if value and energy <= 0.0:
		return
	flashlight_on = value
	flashlight.visible = flashlight_on
	flashlight.light_energy = 14.0 if flashlight_on else 0.0
	GameEvents.flashlight_state_changed.emit(flashlight_on)

func toggle_flashlight() -> void:
	set_flashlight(not flashlight_on)
