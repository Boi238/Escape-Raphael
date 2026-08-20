extends CharacterBody3D
## Player controller (Chunk 3).
##
## Touch controls:
##   - Drag on the LEFT half of the screen  -> move (forward/back/strafe)
##   - Drag on the RIGHT half of the screen -> look around
##   - On-screen CRANK button (hold, see TouchControls.gd) -> crank the
##     dynamo flashlight
##   - On-screen LIGHT button (tap, see TouchControls.gd)  -> toggle the
##     flashlight on/off
##
## Dynamo flashlight rules (per spec):
##   - 5 seconds of continuous cranking fully charges 14 seconds of light.
##     Energy is stored directly in "seconds of light remaining" so the
##     math is just two flat rates - no separate 0..1 charge value to keep
##     in sync with a display unit.
##   - Cranking multiplies move speed by CRANK_SPEED_MULTIPLIER (-10%).
##   - Cranking pings GameEvents.player_made_noise every NOISE_INTERVAL
##     seconds with reveals_position = true. Monster AI (Chunk 4) will use
##     this to instantly know the player's position when it can't
##     otherwise see them - the crank is loud enough to hear through the
##     whole house, hence the large radius.
##   - If energy hits 0 while the flashlight is on, it force-turns-off.

const MOVE_SPEED := 3.2
const CRANK_SPEED_MULTIPLIER := 0.9
const LOOK_SENSITIVITY := 0.005
const GRAVITY := 12.0
const PITCH_LIMIT := 1.3

const MAX_ENERGY := 14.0                      # seconds of flashlight runtime, fully charged
const CRANK_FILL_RATE := MAX_ENERGY / 5.0     # 2.8 energy/sec while cranking (5s crank = full)
const DRAIN_RATE := MAX_ENERGY / 14.0         # 1.0 energy/sec while the light is on
const NOISE_INTERVAL := 0.35                  # how often cranking pings GameEvents
const CRANK_NOISE_RADIUS := 30.0              # crank noise carries through the whole house

@onready var _head: Node3D = $Head
@onready var _flashlight: SpotLight3D = $Head/Camera3D/Flashlight

var energy := MAX_ENERGY * 0.5   # start half-charged so the intro isn't pitch dark forever
var is_cranking := false
var flashlight_on := false

const JOYSTICK_MAX_RADIUS := 90.0  # px of drag from the anchor point for 100% move speed

var _move_touch_index := -1
var _move_anchor := Vector2.ZERO
var _look_touch_index := -1
var _move_vector := Vector2.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _noise_timer := 0.0

## Emitted every physics frame with (current, max) so the HUD energy bar
## can just bind to this instead of polling.
signal energy_changed(current: float, max_energy: float)

func _ready() -> void:
	add_to_group("player")
	_yaw = rotation.y
	_pitch = _head.rotation.x

	# The Basement->Upper ramp inclines at ~27 degrees. CharacterBody3D's
	# default floor_max_angle (45 deg) should technically already cover
	# that, but the default floor_snap_length is short enough that
	# transitioning from flat ground onto an incline can pop the body off
	# the floor and register as "not on floor" for a frame, which reads
	# as "stuck." Setting both explicitly here removes the guesswork.
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35

	_flashlight.visible = false
	_flashlight.light_energy = 7.0
	_flashlight.spot_range = 15.0
	_flashlight.spot_angle = 30.0
	_flashlight.spot_angle_attenuation = 2.0
	_flashlight.light_color = Color(1.0, 0.96, 0.85)
	_flashlight.shadow_enabled = true

func _unhandled_input(event: InputEvent) -> void:
	# Buttons in TouchControls have mouse_filter = STOP, so touches that
	# start on them never reach here - no manual rect exclusion needed.
	if event is InputEventScreenTouch:
		var half_width := get_viewport().get_visible_rect().size.x / 2.0
		if event.pressed:
			if event.position.x < half_width and _move_touch_index == -1:
				_move_touch_index = event.index
				_move_anchor = event.position  # joystick center = where the thumb landed
			elif event.position.x >= half_width and _look_touch_index == -1:
				_look_touch_index = event.index
		else:
			if event.index == _move_touch_index:
				_move_touch_index = -1
				_move_vector = Vector2.ZERO
			if event.index == _look_touch_index:
				_look_touch_index = -1
	elif event is InputEventScreenDrag:
		if event.index == _move_touch_index:
			# Direction is (current finger pos - anchor), not the raw
			# per-frame delta - using the delta was the bug behind the
			# "left-right-left-right" jitter, since tiny frame-to-frame
			# finger jiggle was being read as a direction change every
			# single event instead of a stable direction from a fixed
			# joystick center.
			var offset := event.position - _move_anchor
			_move_vector = (offset / JOYSTICK_MAX_RADIUS).limit_length(1.0)
		elif event.index == _look_touch_index:
			_yaw -= event.relative.x * LOOK_SENSITIVITY
			_pitch -= event.relative.y * LOOK_SENSITIVITY
			_pitch = clamp(_pitch, -PITCH_LIMIT, PITCH_LIMIT)

func _physics_process(delta: float) -> void:
	rotation.y = _yaw
	_head.rotation.x = _pitch

	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var move_dir := (forward * -_move_vector.y + right * _move_vector.x)
	move_dir.y = 0
	if move_dir.length() > 0.001:
		move_dir = move_dir.normalized()

	var speed := MOVE_SPEED
	if is_cranking:
		speed *= CRANK_SPEED_MULTIPLIER

	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()

	_process_flashlight(delta)

func _process_flashlight(delta: float) -> void:
	if is_cranking:
		energy = min(energy + CRANK_FILL_RATE * delta, MAX_ENERGY)
		_noise_timer -= delta
		if _noise_timer <= 0.0:
			_noise_timer = NOISE_INTERVAL
			GameEvents.player_made_noise.emit(global_position, CRANK_NOISE_RADIUS, true)

	if flashlight_on:
		energy = max(energy - DRAIN_RATE * delta, 0.0)
		if energy <= 0.0:
			_set_flashlight(false)

	energy_changed.emit(energy, MAX_ENERGY)

## Called by TouchControls.gd on CRANK button_down.
func start_crank() -> void:
	is_cranking = true
	_noise_timer = 0.0  # ping immediately on the first frame of cranking

## Called by TouchControls.gd on CRANK button_up.
func stop_crank() -> void:
	is_cranking = false

## Called by TouchControls.gd on LIGHT button press.
func toggle_flashlight() -> void:
	if not flashlight_on and energy <= 0.0:
		return  # dead battery, nothing to turn on
	_set_flashlight(not flashlight_on)

func _set_flashlight(on: bool) -> void:
	flashlight_on = on
	_flashlight.visible = on
	GameEvents.flashlight_state_changed.emit(on)
