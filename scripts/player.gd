extends CharacterBody3D

signal shield_changed(active: bool, duration: float)
signal speed_boost_changed(active: bool, duration: float)
signal dash_cooldown_updated(current: float, max_cooldown: float)

@export_group("Locomotion")
@export var walk_speed: float = 6.5
@export var run_speed: float = 9.8
@export var acceleration: float = 14.0
@export var friction: float = 12.0
@export var gravity: float = 19.6

@export_group("Jump & Acrobatics")
@export var jump_velocity: float = 7.5
@export var max_jumps: int = 2
@export var dash_speed: float = 22.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 1.2

@export_group("Camera & Feel")
@export var rotation_speed: float = 12.0
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = deg_to_rad(-65.0)
@export var max_pitch: float = deg_to_rad(25.0)
@export var base_fov: float = 70.0
@export var sprint_fov: float = 78.0
@export var dash_fov: float = 86.0

var is_active: bool = true

# Node references
@onready var model: Node3D = $Model
@onready var arm_l_pivot: Node3D = $Model/ArmL_Pivot
@onready var arm_r_pivot: Node3D = $Model/ArmR_Pivot
@onready var leg_l_pivot: Node3D = $Model/LegL_Pivot
@onready var leg_r_pivot: Node3D = $Model/LegR_Pivot
@onready var shield_bubble: MeshInstance3D = $Model/ShieldBubble
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

# Camera state
var _camera_yaw: float = 0.0
var _camera_pitch: float = deg_to_rad(-18.0)
var _shake_trauma: float = 0.0

# Jumps & Acrobatics state
var _jump_count: int = 0
var is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

# Buffs state
var has_shield: bool = false
var shield_duration_remaining: float = 0.0
var speed_boost_factor: float = 1.0
var speed_boost_remaining: float = 0.0

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
	
	if shield_bubble:
		shield_bubble.visible = false
		
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_input_map() -> void:
	var actions := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"dash": [KEY_Q, KEY_E]
	}
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: int in actions[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key as Key
				InputMap.action_add_event(action, ev)
				
	# Also allow right-click for dash
	if InputMap.has_action("dash"):
		var mouse_ev := InputEventMouseButton.new()
		mouse_ev.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("dash", mouse_ev)

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
	# Update cooldown timers
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta
		dash_cooldown_updated.emit(clamp(_dash_cooldown_timer, 0.0, dash_cooldown), dash_cooldown)

	# Update active buffs
	_update_buffs(delta)

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y <= 0.0:
			velocity.y = 0.0
			_jump_count = 0

	# Update camera pivot tracking and trauma shake
	_update_camera(delta)

	if not is_active:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		move_and_slide()
		_update_procedural_animation(delta, 0.0, Vector2.ZERO)
		return

	# Dashing mechanics
	if is_dashing:
		_dash_timer -= delta
		velocity.x = _dash_direction.x * dash_speed
		velocity.z = _dash_direction.z * dash_speed
		velocity.y = 0.0 # Maintain dash height
		if _dash_timer <= 0.0:
			is_dashing = false
		move_and_slide()
		_update_procedural_animation(delta, dash_speed, Vector2.ZERO)
		return

	# Handle jump & double jump
	if Input.is_action_just_pressed("jump"):
		if is_on_floor() or _jump_count < max_jumps:
			velocity.y = jump_velocity
			_jump_count += 1
			if _jump_count == 2:
				add_camera_shake(0.2) # Small punch on double jump
			var audio = get_tree().get_first_node_in_group("audio_manager")
			if audio and audio.has_method("play_jump"):
				audio.play_jump()

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

	# Handle Dash trigger
	if Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		dash(move_dir)
		return

	# Sprint and speed buff calculation
	var is_sprinting := Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)
	var base_speed := run_speed if is_sprinting else walk_speed
	var target_speed := base_speed * speed_boost_factor

	# Move character
	if move_dir.length() > 0.05:
		velocity.x = move_toward(velocity.x, move_dir.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * target_speed, acceleration * delta)
		
		# Smooth model rotation toward movement direction
		var target_rot := atan2(-move_dir.x, -move_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_rot, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	move_and_slide()

	# Procedural limb animation & body banking
	var h_speed := Vector2(velocity.x, velocity.z).length()
	_update_procedural_animation(delta, h_speed, input_dir)

func dash(move_dir: Vector3 = Vector3.ZERO) -> bool:
	if not is_active or _dash_cooldown_timer > 0.0 or is_dashing:
		return false
	_start_dash(move_dir)
	return true

func _start_dash(move_dir: Vector3) -> void:
	is_dashing = true
	_dash_timer = dash_duration
	_dash_cooldown_timer = dash_cooldown
	
	if move_dir.length() > 0.1:
		_dash_direction = move_dir.normalized()
	elif camera_pivot != null:
		var fwd := -camera_pivot.global_transform.basis.z
		fwd.y = 0.0
		_dash_direction = fwd.normalized()
	else:
		_dash_direction = -model.global_transform.basis.z
		
	# Immediate velocity impulse
	velocity.x = _dash_direction.x * dash_speed
	velocity.z = _dash_direction.z * dash_speed
	velocity.y = 0.0
	
	# Instantly face dash direction
	model.rotation.y = atan2(-_dash_direction.x, -_dash_direction.z)
	add_camera_shake(0.35)
	
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio and audio.has_method("play_dash"):
		audio.play_dash()

func _update_camera(delta: float) -> void:
	if not camera_pivot:
		return
		
	camera_pivot.global_position = camera_pivot.global_position.lerp(global_position + Vector3(0, 1.4, 0), 20.0 * delta)
	camera_pivot.rotation.y = _camera_yaw
	if spring_arm:
		spring_arm.rotation.x = _camera_pitch

	# Dynamic FOV based on state
	if camera:
		var target_fov := base_fov
		if is_dashing:
			target_fov = dash_fov
		elif Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > walk_speed:
			target_fov = sprint_fov
		camera.fov = lerp(camera.fov, target_fov, 8.0 * delta)

		# Trauma camera shake
		if _shake_trauma > 0.0:
			_shake_trauma = max(0.0, _shake_trauma - delta * 2.0)
			var shake_pwr := _shake_trauma * _shake_trauma
			camera.h_offset = sin(Time.get_ticks_msec() * 0.06) * 0.16 * shake_pwr
			camera.v_offset = cos(Time.get_ticks_msec() * 0.07) * 0.16 * shake_pwr
		else:
			camera.h_offset = lerp(camera.h_offset, 0.0, 12.0 * delta)
			camera.v_offset = lerp(camera.v_offset, 0.0, 12.0 * delta)

func add_camera_shake(amount: float) -> void:
	_shake_trauma = clamp(_shake_trauma + amount, 0.0, 1.0)

func _update_buffs(delta: float) -> void:
	# Shield timer
	if has_shield:
		shield_duration_remaining -= delta
		if shield_duration_remaining <= 0.0:
			deactivate_shield()
			
	# Speed boost timer
	if speed_boost_factor > 1.0:
		speed_boost_remaining -= delta
		if speed_boost_remaining <= 0.0:
			speed_boost_factor = 1.0
			speed_boost_changed.emit(false, 0.0)

func activate_shield(duration: float = 12.0) -> void:
	has_shield = true
	shield_duration_remaining = duration
	if shield_bubble:
		shield_bubble.visible = true
	shield_changed.emit(true, duration)

func deactivate_shield() -> void:
	has_shield = false
	shield_duration_remaining = 0.0
	if shield_bubble:
		shield_bubble.visible = false
	shield_changed.emit(false, 0.0)

func activate_speed_boost(multiplier: float = 1.45, duration: float = 8.0) -> void:
	speed_boost_factor = multiplier
	speed_boost_remaining = duration
	speed_boost_changed.emit(true, duration)

func take_hit() -> bool:
	if has_shield:
		# Shield absorbs the hit!
		deactivate_shield()
		add_camera_shake(0.55)
		var audio = get_tree().get_first_node_in_group("audio_manager")
		if audio and audio.has_method("play_shield_hit"):
			audio.play_shield_hit()
		# Repel backwards slightly
		velocity.y = 4.0
		return false # Survived!
	return true # Fatal hit

func _update_procedural_animation(delta: float, h_speed: float, input_dir: Vector2) -> void:
	# Detect landing impact
	if is_on_floor() and not _was_on_floor:
		_landing_squash = -0.12
		add_camera_shake(0.18) # Camera bump on landing
	_was_on_floor = is_on_floor()

	# Smooth landing recovery
	_landing_squash = lerp(_landing_squash, 0.0, 10.0 * delta)

	# Lateral leaning / banking into turns
	var target_lean: float = -clamp(input_dir.x * 0.12, -0.18, 0.18)
	model.rotation.z = lerp_angle(model.rotation.z, target_lean, 10.0 * delta)

	if not is_on_floor():
		# Airborne state (Jump / Fall)
		var air_factor: float = clamp(abs(velocity.y) / jump_velocity, 0.2, 1.0)
		leg_l_pivot.rotation.x = lerp_angle(leg_l_pivot.rotation.x, deg_to_rad(24.0 * air_factor), 10.0 * delta)
		leg_r_pivot.rotation.x = lerp_angle(leg_r_pivot.rotation.x, deg_to_rad(18.0 * air_factor), 10.0 * delta)
		arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, deg_to_rad(-42.0 * air_factor), 10.0 * delta)
		arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, deg_to_rad(-42.0 * air_factor), 10.0 * delta)
		arm_l_pivot.rotation.z = lerp_angle(arm_l_pivot.rotation.z, deg_to_rad(-14.0), 10.0 * delta)
		arm_r_pivot.rotation.z = lerp_angle(arm_r_pivot.rotation.z, deg_to_rad(14.0), 10.0 * delta)
		model.position.y = lerp(model.position.y, _base_model_y + _landing_squash, 12.0 * delta)
	elif is_dashing:
		# Dash posture: lean forward aggressively, arms trailing back
		model.rotation.x = lerp_angle(model.rotation.x, deg_to_rad(28.0), 18.0 * delta)
		arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, deg_to_rad(45.0), 18.0 * delta)
		arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, deg_to_rad(45.0), 18.0 * delta)
	elif h_speed > 0.5:
		model.rotation.x = lerp_angle(model.rotation.x, 0.0, 12.0 * delta)
		# Ground Locomotion (Walk / Run)
		var speed_ratio: float = clamp(h_speed / walk_speed, 0.4, 2.2)
		var freq: float = 9.5 * speed_ratio
		var leg_amp: float = deg_to_rad(32.0 * clamp(speed_ratio, 0.8, 1.5))
		var arm_amp: float = deg_to_rad(36.0 * clamp(speed_ratio, 0.8, 1.5))

		_anim_time += delta * freq
		var swing: float = sin(_anim_time)

		# Legs swing opposite each other
		leg_l_pivot.rotation.x = lerp_angle(leg_l_pivot.rotation.x, swing * leg_amp, 18.0 * delta)
		leg_r_pivot.rotation.x = lerp_angle(leg_r_pivot.rotation.x, -swing * leg_amp, 18.0 * delta)
		leg_l_pivot.rotation.z = lerp_angle(leg_l_pivot.rotation.z, 0.0, 10.0 * delta)
		leg_r_pivot.rotation.z = lerp_angle(leg_r_pivot.rotation.z, 0.0, 10.0 * delta)

		# Arms swing opposite legs
		arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, -swing * arm_amp, 18.0 * delta)
		arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, swing * arm_amp, 18.0 * delta)
		arm_l_pivot.rotation.z = lerp_angle(arm_l_pivot.rotation.z, deg_to_rad(-4.0), 10.0 * delta)
		arm_r_pivot.rotation.z = lerp_angle(arm_r_pivot.rotation.z, deg_to_rad(4.0), 10.0 * delta)

		# Vertical footstep bounce
		var step_bob: float = abs(sin(_anim_time)) * (0.038 * clamp(speed_ratio, 0.8, 1.4))
		model.position.y = _base_model_y + step_bob + _landing_squash
	else:
		model.rotation.x = lerp_angle(model.rotation.x, 0.0, 12.0 * delta)
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
