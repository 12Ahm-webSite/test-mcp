extends CharacterBody3D

signal state_changed(new_state: String)

enum State {
	PATROL,
	CHASE,
	SEARCH,
	RETURN,
	STAGGERED
}

@export_group("Sentinel Attributes")
@export var patrol_speed: float = 3.6
@export var chase_speed: float = 5.8
@export var turn_speed: float = 7.0
@export var catch_distance: float = 1.3
@export var view_distance: float = 24.0
@export var view_angle_deg: float = 110.0
@export var hearing_distance: float = 12.0
@export var gravity: float = 19.6
@export var attack_damage: float = 35.0
@export var attack_cooldown: float = 1.4

var current_state: State = State.PATROL
var is_active: bool = true

# Adaptation & Memory
var last_seen_position: Vector3 = Vector3.ZERO
var patrol_origin: Vector3 = Vector3.ZERO
var _search_timer: float = 0.0
var _stagger_timer: float = 0.0
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_timer: float = 0.0
var _hit_cooldown_timer: float = 0.0
var _hiding_zones: Dictionary = {} # zone_key -> count
var _player: Node3D = null

# Anti-stuck & Navigation state
var _last_pos: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
var _unstick_timer: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO

# Node references
@onready var model: Node3D = $Model
@onready var eye_light: OmniLight3D = $Model/Head/EyeLight
@onready var arm_l_pivot: Node3D = $Model/ArmL_Pivot
@onready var arm_r_pivot: Node3D = $Model/ArmR_Pivot
@onready var ray_forward: RayCast3D = $RayCastForward
@onready var ray_left: RayCast3D = $RayCastLeft
@onready var ray_right: RayCast3D = $RayCastRight

# Animation timers
var _anim_time: float = 0.0
var _base_model_y: float = 1.0

func _get_pos() -> Vector3:
	return global_position if is_inside_tree() else position

func _ready() -> void:
	add_to_group("enemy")
	patrol_origin = _get_pos()
	_last_pos = _get_pos()
	_pick_new_patrol_target()
	_find_player()

func _find_player() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree:
		_player = tree.get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if _hit_cooldown_timer > 0.0:
		_hit_cooldown_timer -= delta

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if not is_active:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		move_and_slide()
		return

	if _player == null or not is_instance_valid(_player):
		_find_player()

	# Process current State
	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.SEARCH:
			_process_search(delta)
		State.RETURN:
			_process_return(delta)
		State.STAGGERED:
			_process_staggered(delta)

	move_and_slide()
	_update_animations(delta)

# ----------------------------------------------------
# PERCEPTION & DETECTION
# ----------------------------------------------------
func can_see_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false

	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > view_distance:
		return false

	# Check Vision Cone Angle (forward is -Z in local space)
	var forward_dir := -global_transform.basis.z.normalized()
	var angle_to_player := rad_to_deg(forward_dir.angle_to(to_player.normalized()))
	if angle_to_player > (view_angle_deg * 0.5):
		return false

	# Line of Sight Raycast check
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.4, 0),
		_player.global_position + Vector3(0, 1.0, 0),
		1 # Collide with environment / world layer 1
	)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	return result.is_empty() # Nothing blocking line of sight!

func can_hear_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false

	var dist := global_position.distance_to(_player.global_position)
	if dist > hearing_distance:
		return false

	# Sensed if player is sprinting or dashing
	var player_char := _player as CharacterBody3D
	if player_char:
		if "is_dashing" in player_char and player_char.is_dashing:
			return true
		if Input.is_action_pressed("sprint") and player_char.velocity.length() > 6.0:
			return true
	return false

# ----------------------------------------------------
# STATE PROCESSORS
# ----------------------------------------------------
func _process_patrol(delta: float) -> void:
	if can_see_player():
		_enter_state(State.CHASE)
		return

	if can_hear_player():
		last_seen_position = _player.global_position
		_enter_state(State.SEARCH)
		return

	_patrol_timer -= delta
	if _patrol_timer <= 0.0 or global_position.distance_to(_patrol_target) < 1.5:
		_pick_new_patrol_target()

	_move_towards(_patrol_target, patrol_speed, delta)

func _process_chase(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_enter_state(State.PATROL)
		return

	var dist_to_player := global_position.distance_to(_player.global_position)

	# Check Catch / Attack condition
	if dist_to_player <= catch_distance:
		_attempt_catch()
		return

	if can_see_player():
		last_seen_position = _player.global_position
		
		# Predictive intercept if player is moving fast
		var target_dest := _player.global_position
		var player_char := _player as CharacterBody3D
		if player_char and player_char.velocity.length() > 5.0:
			target_dest += player_char.velocity.normalized() * 1.8
			
		_move_towards(target_dest, chase_speed, delta)
	else:
		# Player broke line of sight! Adapt and switch to search
		_register_player_hiding_spot(last_seen_position)
		_enter_state(State.SEARCH)

func _process_search(delta: float) -> void:
	if can_see_player():
		_enter_state(State.CHASE)
		return

	var dist_to_last_seen := global_position.distance_to(last_seen_position)
	if dist_to_last_seen > 1.8:
		_move_towards(last_seen_position, chase_speed * 0.85, delta)
	else:
		# At last seen location: perform investigation scan
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		
		# Turn left and right while scanning
		rotation.y += sin(_anim_time * 3.0) * 1.5 * delta
		
		_search_timer -= delta
		if _search_timer <= 0.0:
			_enter_state(State.RETURN)

func _process_return(delta: float) -> void:
	if can_see_player():
		_enter_state(State.CHASE)
		return

	if can_hear_player():
		last_seen_position = _player.global_position
		_enter_state(State.SEARCH)
		return

	if global_position.distance_to(patrol_origin) < 2.0:
		_enter_state(State.PATROL)
		return

	_move_towards(patrol_origin, patrol_speed, delta)

func _process_staggered(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	_stagger_timer -= delta
	if _stagger_timer <= 0.0:
		_enter_state(State.SEARCH)

# ----------------------------------------------------
# NAVIGATION & STEERING
# ----------------------------------------------------
func _move_towards(target_pos: Vector3, move_speed: float, delta: float) -> void:
	var to_target := target_pos - _get_pos()
	to_target.y = 0.0
	var dist := to_target.length()
	
	if dist < 0.2:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		return

	# Handle active unstick maneuver
	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		velocity.x = _unstick_dir.x * move_speed
		velocity.z = _unstick_dir.z * move_speed
		var unstick_angle := atan2(-_unstick_dir.x, -_unstick_dir.z)
		rotation.y = lerp_angle(rotation.y, unstick_angle, turn_speed * delta)
		return

	var desired_dir := to_target.normalized()
	var avoidance := Vector3.ZERO

	# Smooth obstacle avoidance with collision normals
	if ray_forward and ray_forward.is_colliding():
		var norm = ray_forward.get_collision_normal()
		norm.y = 0.0
		if norm.length_squared() > 0.01:
			avoidance += norm.normalized() * 2.2
		else:
			avoidance += -desired_dir * 1.5

	if ray_left and ray_left.is_colliding():
		var norm = ray_left.get_collision_normal()
		norm.y = 0.0
		if norm.length_squared() > 0.01:
			avoidance += norm.normalized() * 1.4
		else:
			avoidance += global_transform.basis.x * 1.4

	if ray_right and ray_right.is_colliding():
		var norm = ray_right.get_collision_normal()
		norm.y = 0.0
		if norm.length_squared() > 0.01:
			avoidance += norm.normalized() * 1.4
		else:
			avoidance += -global_transform.basis.x * 1.4

	var final_dir: Vector3
	if avoidance.length_squared() > 0.01:
		final_dir = (desired_dir + avoidance).normalized()
	else:
		final_dir = desired_dir

	velocity.x = move_toward(velocity.x, final_dir.x * move_speed, 12.0 * delta)
	velocity.z = move_toward(velocity.z, final_dir.z * move_speed, 12.0 * delta)

	var target_angle := atan2(-final_dir.x, -final_dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)

	# Anti-stuck detection: monitor physical displacement
	if move_speed > 1.0:
		var moved_dist := _get_pos().distance_to(_last_pos)
		if moved_dist < 0.05:
			_stuck_timer += delta
			if _stuck_timer > 0.45:
				_stuck_timer = 0.0
				_unstick_timer = 0.6
				var right_vec := final_dir.cross(Vector3.UP).normalized()
				var side := 1.0 if randf() > 0.5 else -1.0
				_unstick_dir = (-final_dir * 0.5 + right_vec * side * 0.85).normalized()
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)
	_last_pos = _get_pos()

func _enter_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(State.keys()[new_state])
	
	match new_state:
		State.CHASE:
			if eye_light:
				eye_light.light_color = Color(1.0, 0.0, 0.0)
				eye_light.light_energy = 4.0
				eye_light.omni_range = 7.0
			var tree := get_tree() if is_inside_tree() else null
			var audio = tree.get_first_node_in_group("audio_manager") if tree else null
			if audio and audio.has_method("play_alert"):
				audio.play_alert()
		State.SEARCH:
			# Extra search time if player repeats hiding in this zone
			var extra_time := _get_zone_familiarity(last_seen_position) * 1.5
			_search_timer = 4.0 + min(extra_time, 5.0)
			if eye_light:
				eye_light.light_color = Color(1.0, 0.5, 0.0) # Amber alert
				eye_light.light_energy = 2.5
		State.PATROL, State.RETURN:
			if eye_light:
				eye_light.light_color = Color(0.9, 0.15, 0.15)
				eye_light.light_energy = 2.0
				eye_light.omni_range = 5.0
		State.STAGGERED:
			_stagger_timer = 2.0
			if eye_light:
				eye_light.light_color = Color(1.0, 0.65, 0.1) # Amber glitch
				eye_light.light_energy = 0.6

func _attempt_catch() -> void:
	if _hit_cooldown_timer > 0.0:
		return
	_hit_cooldown_timer = attack_cooldown

	if _player and _player.has_method("take_hit"):
		var fatal: bool = _player.take_hit(attack_damage, self)
		if not fatal:
			# Player survived with partial damage or shield! Sentinel is staggered
			_enter_state(State.STAGGERED)
			return
		else:
			# Fatal catch -> Player health reached zero
			is_active = false
			return

func take_damage(amount: float, attacker: Node3D = null) -> void:
	if not is_active:
		return
	# Tactical player agency: shooting the Sentinel interrupts its chase and stuns it for 2.0s!
	_stagger_timer = 2.0
	_enter_state(State.STAGGERED)
	if eye_light:
		eye_light.light_color = Color(1.0, 0.9, 0.2)
		eye_light.light_energy = 5.0
	var tree := get_tree() if is_inside_tree() else null
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	if audio and audio.has_method("play_hit"):
		audio.play_hit()

func receive_alert(target_pos: Vector3) -> void:
	if not is_active:
		return
	last_seen_position = target_pos
	if current_state == State.PATROL or current_state == State.RETURN:
		_enter_state(State.SEARCH)

# ----------------------------------------------------
# ADAPTATION & PATROL HELPERS
# ----------------------------------------------------
func _pick_new_patrol_target() -> void:
	_patrol_timer = randf_range(4.0, 7.0)
	var offset := Vector3(randf_range(-14.0, 14.0), 0.0, randf_range(-14.0, 14.0))
	_patrol_target = patrol_origin + offset

func _register_player_hiding_spot(pos: Vector3) -> void:
	var zone_key := "%d_%d" % [int(round(pos.x / 10.0)), int(round(pos.z / 10.0))]
	_hiding_zones[zone_key] = _hiding_zones.get(zone_key, 0) + 1

func _get_zone_familiarity(pos: Vector3) -> float:
	var zone_key := "%d_%d" % [int(round(pos.x / 10.0)), int(round(pos.z / 10.0))]
	return float(_hiding_zones.get(zone_key, 0))

# ----------------------------------------------------
# PROCEDURAL ROBOT ANIMATION
# ----------------------------------------------------
func _update_animations(delta: float) -> void:
	_anim_time += delta
	
	# Hover bobbing
	var bob := sin(_anim_time * 4.0) * 0.08
	model.position.y = _base_model_y + bob

	# Eye pulse
	if eye_light and current_state == State.CHASE:
		eye_light.light_energy = 3.5 + sin(_anim_time * 12.0) * 1.5

	# Threatening arm claw motion
	if arm_l_pivot and arm_r_pivot:
		if current_state == State.CHASE:
			# Arms outstretched ready to grab
			arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, deg_to_rad(30.0), 10.0 * delta)
			arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, deg_to_rad(30.0), 10.0 * delta)
			arm_l_pivot.rotation.z = lerp_angle(arm_l_pivot.rotation.z, deg_to_rad(15.0 + sin(_anim_time * 8.0) * 8.0), 10.0 * delta)
			arm_r_pivot.rotation.z = lerp_angle(arm_r_pivot.rotation.z, deg_to_rad(-15.0 - sin(_anim_time * 8.0) * 8.0), 10.0 * delta)
		elif current_state == State.STAGGERED:
			# Arms recoil back
			arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, deg_to_rad(-45.0), 12.0 * delta)
			arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, deg_to_rad(-45.0), 12.0 * delta)
		else:
			# Normal idle/patrol subtle arm sway
			arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, 0.0, 6.0 * delta)
			arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, 0.0, 6.0 * delta)
			arm_l_pivot.rotation.z = lerp_angle(arm_l_pivot.rotation.z, 0.0, 6.0 * delta)
			arm_r_pivot.rotation.z = lerp_angle(arm_r_pivot.rotation.z, 0.0, 6.0 * delta)
