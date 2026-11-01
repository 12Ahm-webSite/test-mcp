extends CharacterBody3D

@export_group("Movement")
@export var walk_speed: float = 6.5
@export var run_speed: float = 9.5
@export var acceleration: float = 14.0
@export var friction: float = 12.0
@export var jump_velocity: float = 7.5
@export var gravity: float = 19.6

@export_group("Rotation & Camera")
@export var rotation_speed: float = 12.0
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = deg_to_rad(-65.0) # Look up limit
@export var max_pitch: float = deg_to_rad(25.0)  # Look down limit

var is_active: bool = true

@onready var model: Node3D = $Model
@onready var arm_l_pivot: Node3D = $Model/ArmL_Pivot
@onready var arm_r_pivot: Node3D = $Model/ArmR_Pivot
@onready var leg_l_pivot: Node3D = $Model/LegL_Pivot
@onready var leg_r_pivot: Node3D = $Model/LegR_Pivot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D

# Camera state
var _camera_yaw: float = 0.0
var _camera_pitch: float = deg_to_rad(-18.0)

# Procedural animation state
var _anim_time: float = 0.0
var _base_model_y: float = 0.9
var _landing_squash: float = 0.0
var _was_on_floor: bool = true

func _ready() -> void:
	add_to_group("player")
	_setup_input_map()
	
	if camera_pivot:
		camera_pivot.top_level = true
		camera_pivot.global_position = global_position + Vector3(0, 1.4, 0)
		camera_pivot.rotation.y = _camera_yaw
		if spring_arm:
			spring_arm.rotation.x = _camera_pitch
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_input_map() -> void:
	var actions := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT]
	}
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: int in actions[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key as Key
				InputMap.action_add_event(action, ev)

func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
		
	# Mouse lock / unlock controls
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Mouse look rotation
	var is_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	if is_captured and event is InputEventMouseMotion:
		_camera_yaw -= event.relative.x * mouse_sensitivity
		_camera_pitch -= event.relative.y * mouse_sensitivity
		_camera_pitch = clamp(_camera_pitch, min_pitch, max_pitch)

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	
	# Update camera pivot position smoothly
	if camera_pivot:
		camera_pivot.global_position = camera_pivot.global_position.lerp(global_position + Vector3(0, 1.4, 0), 20.0 * delta)
		camera_pivot.rotation.y = _camera_yaw
		if spring_arm:
			spring_arm.rotation.x = _camera_pitch

	if not is_active:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		move_and_slide()
		_update_procedural_animation(delta, 0.0)
		return

	# Handle jump
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Get input vector
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Movement relative to camera
	var move_dir := Vector3.ZERO
	if camera_pivot != null:
		var cam_forward := -camera_pivot.global_transform.basis.z
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
		var cam_right := camera_pivot.global_transform.basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		move_dir = (cam_right * input_dir.x - cam_forward * input_dir.y).normalized()
	else:
		move_dir = Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	# Choose walk or run speed
	var is_sprinting := Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)
	var target_speed := run_speed if is_sprinting else walk_speed

	# Move character
	if move_dir.length() > 0.05:
		velocity.x = move_toward(velocity.x, move_dir.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * target_speed, acceleration * delta)
		
		# Smooth model rotation toward movement direction (separate from camera!)
		var target_rot := atan2(-move_dir.x, -move_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_rot, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	move_and_slide()

	# Procedural limb animation
	var h_speed := Vector2(velocity.x, velocity.z).length()
	_update_procedural_animation(delta, h_speed)

func _update_procedural_animation(delta: float, h_speed: float) -> void:
	# Detect landing
	if is_on_floor() and not _was_on_floor:
		_landing_squash = -0.1
	_was_on_floor = is_on_floor()

	# Smooth landing recovery
	_landing_squash = lerp(_landing_squash, 0.0, 10.0 * delta)

	if not is_on_floor():
		# Airborne state (Jump / Fall)
		var air_factor: float = clamp(abs(velocity.y) / jump_velocity, 0.2, 1.0)
		leg_l_pivot.rotation.x = lerp_angle(leg_l_pivot.rotation.x, deg_to_rad(22.0 * air_factor), 10.0 * delta)
		leg_r_pivot.rotation.x = lerp_angle(leg_r_pivot.rotation.x, deg_to_rad(18.0 * air_factor), 10.0 * delta)
		arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, deg_to_rad(-40.0 * air_factor), 10.0 * delta)
		arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, deg_to_rad(-40.0 * air_factor), 10.0 * delta)
		arm_l_pivot.rotation.z = lerp_angle(arm_l_pivot.rotation.z, deg_to_rad(-12.0), 10.0 * delta)
		arm_r_pivot.rotation.z = lerp_angle(arm_r_pivot.rotation.z, deg_to_rad(12.0), 10.0 * delta)
		model.position.y = lerp(model.position.y, _base_model_y + _landing_squash, 12.0 * delta)
	elif h_speed > 0.5:
		# Ground Locomotion (Walk / Run)
		var speed_ratio: float = clamp(h_speed / walk_speed, 0.4, 2.0)
		var freq: float = 9.5 * speed_ratio
		var leg_amp: float = deg_to_rad(32.0 * clamp(speed_ratio, 0.8, 1.4))
		var arm_amp: float = deg_to_rad(36.0 * clamp(speed_ratio, 0.8, 1.4))

		_anim_time += delta * freq
		var swing: float = sin(_anim_time)

		# Legs swing opposite each other
		leg_l_pivot.rotation.x = lerp_angle(leg_l_pivot.rotation.x, swing * leg_amp, 18.0 * delta)
		leg_r_pivot.rotation.x = lerp_angle(leg_r_pivot.rotation.x, -swing * leg_amp, 18.0 * delta)
		leg_l_pivot.rotation.z = lerp_angle(leg_l_pivot.rotation.z, 0.0, 10.0 * delta)
		leg_r_pivot.rotation.z = lerp_angle(leg_r_pivot.rotation.z, 0.0, 10.0 * delta)

		# Arms swing opposite legs (Left arm swings with Right leg)
		arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, -swing * arm_amp, 18.0 * delta)
		arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, swing * arm_amp, 18.0 * delta)
		arm_l_pivot.rotation.z = lerp_angle(arm_l_pivot.rotation.z, deg_to_rad(-4.0), 10.0 * delta)
		arm_r_pivot.rotation.z = lerp_angle(arm_r_pivot.rotation.z, deg_to_rad(4.0), 10.0 * delta)

		# Vertical footstep bounce
		var step_bob: float = abs(sin(_anim_time)) * (0.035 * clamp(speed_ratio, 0.8, 1.4))
		model.position.y = _base_model_y + step_bob + _landing_squash
	else:
		# Idle (Breathing & subtle natural sway)
		_anim_time += delta * 2.5
		var breath: float = sin(_anim_time)

		leg_l_pivot.rotation.x = lerp_angle(leg_l_pivot.rotation.x, 0.0, 8.0 * delta)
		leg_r_pivot.rotation.x = lerp_angle(leg_r_pivot.rotation.x, 0.0, 8.0 * delta)
		leg_l_pivot.rotation.z = lerp_angle(leg_l_pivot.rotation.z, 0.0, 8.0 * delta)
		leg_r_pivot.rotation.z = lerp_angle(leg_r_pivot.rotation.z, 0.0, 8.0 * delta)

		arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, breath * deg_to_rad(4.0), 8.0 * delta)
		arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, -breath * deg_to_rad(4.0), 8.0 * delta)
		arm_l_pivot.rotation.z = lerp_angle(arm_l_pivot.rotation.z, deg_to_rad(-3.0) + breath * deg_to_rad(1.5), 8.0 * delta)
		arm_r_pivot.rotation.z = lerp_angle(arm_r_pivot.rotation.z, deg_to_rad(3.0) - breath * deg_to_rad(1.5), 8.0 * delta)

		model.position.y = _base_model_y + (breath * 0.012) + _landing_squash
