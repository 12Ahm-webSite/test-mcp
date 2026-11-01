extends CharacterBody3D

signal shield_changed(active: bool, duration: float)
signal speed_boost_changed(active: bool, duration: float)
signal dash_cooldown_updated(current: float, max_cooldown: float)
signal health_changed(current: float, max_hp: float)
signal weapon_swapped(type: int, weapon_dict: Dictionary)
signal ammo_updated(type: int, current_ammo: int)
signal player_eliminated(killer: Node3D)
signal player_respawned()

@export_group("Combat & Health")
@export var max_health: float = 120.0

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
@onready var model: Node3D = $Model if has_node("Model") else null
@onready var arm_l_pivot: Node3D = $Model/ArmL_Pivot if has_node("Model/ArmL_Pivot") else null
@onready var arm_r_pivot: Node3D = $Model/ArmR_Pivot if has_node("Model/ArmR_Pivot") else null
@onready var leg_l_pivot: Node3D = $Model/LegL_Pivot if has_node("Model/LegL_Pivot") else null
@onready var leg_r_pivot: Node3D = $Model/LegR_Pivot if has_node("Model/LegR_Pivot") else null
@onready var shield_bubble: MeshInstance3D = $Model/ShieldBubble if has_node("Model/ShieldBubble") else null

# First Person / Camera references
@onready var head: Node3D = $Head if has_node("Head") else null
@onready var camera: Camera3D = $Head/Camera3D if has_node("Head/Camera3D") else ($CameraPivot/SpringArm3D/Camera3D if has_node("CameraPivot/SpringArm3D/Camera3D") else null)
@onready var camera_pivot: Node3D = $CameraPivot if has_node("CameraPivot") else null
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D if has_node("CameraPivot/SpringArm3D") else null

# Weapon Socket & Models (FPS viewmodel under camera prioritized)
@onready var weapon_socket: Node3D = $Head/Camera3D/FpsWeaponSocket if has_node("Head/Camera3D/FpsWeaponSocket") else ($Model/WeaponSocket if has_node("Model/WeaponSocket") else null)
@onready var pistol_model: Node3D = weapon_socket.get_node("PistolModel") if weapon_socket and weapon_socket.has_node("PistolModel") else null
@onready var smg_model: Node3D = weapon_socket.get_node("SMGModel") if weapon_socket and weapon_socket.has_node("SMGModel") else null
@onready var grenade_model: Node3D = weapon_socket.get_node("GrenadeModel") if weapon_socket and weapon_socket.has_node("GrenadeModel") else null
@onready var muzzle_point: Node3D = weapon_socket.get_node("MuzzlePoint") if weapon_socket and weapon_socket.has_node("MuzzlePoint") else null
@onready var muzzle_flash: OmniLight3D = muzzle_point.get_node("MuzzleFlash") if muzzle_point and muzzle_point.has_node("MuzzleFlash") else null

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

# Combat & Weapon state
var character_name: String = "Unit-07"
var health: float = 120.0
var is_dead: bool = false
var unlocked_weapons: Array[int] = [
	WeaponData.WeaponType.PISTOL,
	WeaponData.WeaponType.SMG,
	WeaponData.WeaponType.GRENADE
]
var current_weapon: int = WeaponData.WeaponType.PISTOL
var ammo: Dictionary = {
	WeaponData.WeaponType.PISTOL: 999,
	WeaponData.WeaponType.SMG: 80,
	WeaponData.WeaponType.GRENADE: 3
}
var _fire_timer: float = 0.0
var _recoil_offset: float = 0.0
var _step_bob_time: float = 0.0
var _is_first_person: bool = true
var is_aiming: bool = false
var ads_fov: float = 44.0

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
	
	if head:
		_is_first_person = true
		if model:
			model.visible = false # Hide 3rd-person body in First Person view
	elif camera_pivot:
		_is_first_person = false
		camera_pivot.top_level = true
		camera_pivot.global_position = global_position + Vector3(0, 1.4, 0)
		camera_pivot.rotation.y = _camera_yaw
		if spring_arm:
			spring_arm.rotation.x = _camera_pitch
	
	if shield_bubble:
		shield_bubble.visible = false
		
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	health = max_health
	_update_weapon_models()
	health_changed.emit(health, max_health)
	weapon_swapped.emit(current_weapon, WeaponData.get_weapon(current_weapon))
	ammo_updated.emit(current_weapon, ammo[current_weapon])

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
				
func _unhandled_input(event: InputEvent) -> void:
	if not is_active or is_dead:
		return
		
	# Mouse lock / unlock controls
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			var w_data := WeaponData.get_weapon(current_weapon)
			if not w_data.get("is_automatic", false):
				try_shoot()
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Mouse look rotation (scaled by ADS zoom)
	var is_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	if is_captured and event is InputEventMouseMotion:
		var sens: float = mouse_sensitivity * (0.50 if is_aiming else 1.0)
		if _is_first_person:
			rotate_y(-event.relative.x * sens)
			_camera_pitch = clamp(_camera_pitch - event.relative.y * sens, deg_to_rad(-85.0), deg_to_rad(85.0))
			if head:
				head.rotation.x = _camera_pitch
		else:
			_camera_yaw -= event.relative.x * sens
			_camera_pitch -= event.relative.y * sens
			_camera_pitch = clamp(_camera_pitch, min_pitch, max_pitch)

	# Weapon selection (1, 2, 3) - support physical_keycode and keycode for all keyboard layouts
	if event is InputEventKey and event.pressed:
		var pk: Key = event.physical_keycode
		var kc: Key = event.keycode
		if pk == KEY_1 or kc == KEY_1 or pk == KEY_KP_1:
			select_weapon(WeaponData.WeaponType.PISTOL)
		elif pk == KEY_2 or kc == KEY_2 or pk == KEY_KP_2:
			select_weapon(WeaponData.WeaponType.SMG)
		elif pk == KEY_3 or kc == KEY_3 or pk == KEY_KP_3:
			select_weapon(WeaponData.WeaponType.GRENADE)

	# Weapon cycle (mouse wheel)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_weapon(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_weapon(1)

func _physics_process(delta: float) -> void:
	# Update cooldown timers
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta
		dash_cooldown_updated.emit(clamp(_dash_cooldown_timer, 0.0, dash_cooldown), dash_cooldown)

	# Aim Down Sights (Right Mouse Button)
	is_aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and is_active and not is_dead

	# Fire cooldown & weapon recoil recovery
	if _fire_timer > 0.0:
		_fire_timer -= delta
	_recoil_offset = lerp(_recoil_offset, 0.0, 14.0 * delta)
	if weapon_socket:
		if _is_first_person:
			var h_speed := Vector2(velocity.x, velocity.z).length()
			var bob_mult := 0.25 if is_aiming else 1.0
			var bob_x: float = 0.0
			var bob_y: float = 0.0
			if is_on_floor() and h_speed > 0.5:
				_step_bob_time += delta * 10.0 * clamp(h_speed / walk_speed, 0.8, 1.8)
				bob_x = cos(_step_bob_time * 0.5) * 0.012 * bob_mult
				bob_y = absf(sin(_step_bob_time)) * 0.015 * bob_mult
			else:
				_step_bob_time += delta * 2.0
				bob_y = sin(_step_bob_time) * 0.004 * bob_mult
				
			var hip_pos := Vector3(0.24 + bob_x, -0.20 + bob_y, -0.42 + _recoil_offset)
			var ads_pos := Vector3(0.0 + (bob_x * 0.2), -0.15 + (bob_y * 0.2), -0.36 + (_recoil_offset * 0.5))
			var target_pos := ads_pos if is_aiming else hip_pos
			weapon_socket.position = weapon_socket.position.lerp(target_pos, 16.0 * delta)
		else:
			weapon_socket.position.z = -0.32 + _recoil_offset

	# Continuous automatic firing
	if is_active and not is_dead and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var w_data = WeaponData.get_weapon(current_weapon)
			if w_data.get("is_automatic", false):
				try_shoot()

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

	if not is_active or is_dead:
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

	# Movement relative to camera / body
	var move_dir := Vector3.ZERO
	if _is_first_person:
		var forward := -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		move_dir = (right * input_dir.x - forward * input_dir.y).normalized()
	elif camera_pivot != null:
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
		
		# Smooth model rotation toward movement direction (only in 3rd person)
		if not _is_first_person and model:
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
	elif _is_first_person:
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		_dash_direction = fwd.normalized()
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
	
	# Instantly face dash direction (only in 3rd person)
	if not _is_first_person and model:
		model.rotation.y = atan2(-_dash_direction.x, -_dash_direction.z)
	add_camera_shake(0.35)
	
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio and audio.has_method("play_dash"):
		audio.play_dash()

func _update_camera(delta: float) -> void:
	if camera_pivot:
		camera_pivot.global_position = camera_pivot.global_position.lerp(global_position + Vector3(0, 1.4, 0), 20.0 * delta)
		camera_pivot.rotation.y = _camera_yaw
		if spring_arm:
			spring_arm.rotation.x = _camera_pitch

	# Dynamic FOV based on state (ADS zoom, Dash, Sprint)
	if camera:
		var target_fov := base_fov
		if is_aiming:
			target_fov = ads_fov
		elif is_dashing:
			target_fov = dash_fov
		elif Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > walk_speed:
			target_fov = sprint_fov
		camera.fov = lerp(camera.fov, target_fov, 14.0 * delta)

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
		velocity.y = 4.0
		return false # Survived!
	take_damage(100.0)
	return true # Fatal hit

func take_damage(amount: float, attacker: Node3D = null) -> void:
	if is_dead:
		return
	if has_shield:
		deactivate_shield()
		add_camera_shake(0.55)
		var audio = get_tree().get_first_node_in_group("audio_manager")
		if audio and audio.has_method("play_shield_hit"):
			audio.play_shield_hit()
		velocity.y = 3.0
		return
		
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	add_camera_shake(0.35)
	
	if health <= 0.0:
		_die(attacker)

func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)

func _die(killer: Node3D) -> void:
	is_dead = true
	is_active = false
	visible = false
	player_eliminated.emit(killer)
	
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm and bm.has_method("record_elimination"):
		bm.record_elimination(killer, self)

func respawn_at(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	health = max_health
	is_dead = false
	is_active = true
	visible = true
	if _is_first_person and model:
		model.visible = false
	activate_shield(3.0) # 3-second spawn invulnerability protection
	ammo[WeaponData.WeaponType.SMG] = maxi(ammo.get(WeaponData.WeaponType.SMG, 0), 40)
	health_changed.emit(health, max_health)
	ammo_updated.emit(current_weapon, ammo.get(current_weapon, 0))
	player_respawned.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- Weapon & Combat Systems ---

func select_weapon(w_type: int) -> bool:
	if not unlocked_weapons.has(w_type):
		return false
	if current_weapon == w_type:
		return true
	current_weapon = w_type
	_update_weapon_models()
	weapon_swapped.emit(current_weapon, WeaponData.get_weapon(current_weapon))
	ammo_updated.emit(current_weapon, ammo.get(current_weapon, 0))
	return true

func cycle_weapon(dir: int) -> void:
	if unlocked_weapons.is_empty():
		return
	var idx := unlocked_weapons.find(current_weapon)
	if idx == -1:
		idx = 0
	var new_idx := (idx + dir) % unlocked_weapons.size()
	if new_idx < 0:
		new_idx += unlocked_weapons.size()
	select_weapon(unlocked_weapons[new_idx])

func pickup_weapon(w_type: int, amount: int) -> void:
	if not unlocked_weapons.has(w_type):
		unlocked_weapons.append(w_type)
	ammo[w_type] = mini(ammo.get(w_type, 0) + amount, WeaponData.get_weapon(w_type).get("max_ammo", 999))
	if current_weapon == WeaponData.WeaponType.PISTOL:
		select_weapon(w_type)
	else:
		ammo_updated.emit(current_weapon, ammo.get(current_weapon, 0))

func _update_weapon_models() -> void:
	if pistol_model:
		pistol_model.visible = (current_weapon == WeaponData.WeaponType.PISTOL)
	if smg_model:
		smg_model.visible = (current_weapon == WeaponData.WeaponType.SMG)
	if grenade_model:
		grenade_model.visible = (current_weapon == WeaponData.WeaponType.GRENADE)

func try_shoot() -> bool:
	if not is_active or is_dead or _fire_timer > 0.0:
		return false
	var cur_ammo: int = ammo.get(current_weapon, 0)
	if cur_ammo <= 0:
		return false
		
	var w_data := WeaponData.get_weapon(current_weapon)
	_fire_timer = w_data.get("fire_rate", 0.25)
	
	if current_weapon != WeaponData.WeaponType.PISTOL:
		ammo[current_weapon] -= 1
		ammo_updated.emit(current_weapon, ammo[current_weapon])
		if ammo[current_weapon] <= 0:
			select_weapon(WeaponData.WeaponType.PISTOL)
			
	# Recoil kick
	_recoil_offset = 0.06
	
	# Muzzle flash
	if muzzle_flash:
		muzzle_flash.visible = true
		get_tree().create_timer(0.05).timeout.connect(func(): if muzzle_flash: muzzle_flash.visible = false)
		
	# SFX
	var audio = get_tree().get_first_node_in_group("audio_manager")
	var sfx_name: String = w_data.get("sfx_method", "play_pistol")
	if audio and audio.has_method(sfx_name):
		audio.call(sfx_name)
		
	# Origin & direction calculation
	var origin: Vector3 = muzzle_point.global_position if muzzle_point else global_position + Vector3(0, 1.4, -0.5)
	var shoot_dir: Vector3 = -global_transform.basis.z
	
	if camera:
		var cam_pos: Vector3 = camera.global_position
		var cam_forward: Vector3 = -camera.global_transform.basis.z
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(cam_pos, cam_pos + cam_forward * 100.0)
		query.exclude = [self]
		query.collision_mask = 1 | 4 | 8
		var hit = space_state.intersect_ray(query)
		var target_pt: Vector3 = hit.position if not hit.is_empty() else cam_pos + cam_forward * 80.0
		shoot_dir = (target_pt - origin).normalized()
	
	# Spread deviation (sharply reduced when aiming down sights for pin-point accuracy)
	var spread: float = w_data.get("spread", 0.015)
	if is_aiming:
		spread *= 0.20 # 80% tighter accuracy when aiming down sights
	shoot_dir = (shoot_dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	
	# Spawn Projectile
	var proj = PROJECTILE_SCENE.instantiate()
	get_parent().add_child(proj)
	proj.global_position = origin
	proj.setup(self, shoot_dir, w_data)
	
	add_camera_shake(0.08 if current_weapon == WeaponData.WeaponType.SMG else 0.16)
	return true

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
