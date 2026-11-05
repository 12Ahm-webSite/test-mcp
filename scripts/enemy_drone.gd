extends CharacterBody3D

signal state_changed(new_state: String)
signal drone_destroyed(drone_name: String)

enum State {
	PATROL,
	ALERT,
	COMBAT_ORBIT,
	EVADE,
	STAGGERED
}

@export_group("Drone Attributes")
@export var character_name: String = "Scout-Drone"
@export var max_health: float = 45.0
@export var patrol_speed: float = 6.2
@export var chase_speed: float = 8.2
@export var evasion_speed: float = 9.8
@export var turn_speed: float = 8.5
@export var target_altitude: float = 2.6
@export var view_distance: float = 28.0
@export var view_angle_deg: float = 140.0
@export var hearing_distance: float = 16.0
@export var alert_broadcast_radius: float = 28.0
@export var combat_preferred_dist: float = 10.0
@export var fire_cooldown: float = 1.4

var health: float = 45.0
var current_state: State = State.PATROL
var is_active: bool = true

# Memory & Target
var _player: Node3D = null
var _patrol_origin: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_timer: float = 0.0
var _fire_timer: float = 0.0
var _alert_timer: float = 0.0
var _stagger_timer: float = 0.0
var _orbit_direction: float = 1.0 # 1.0 = clockwise, -1.0 = counter-clockwise

# Projectile
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

# Node references
@onready var model: Node3D = $Model
@onready var eye_light: OmniLight3D = $Model/ScannerEye/EyeLight if has_node("Model/ScannerEye/EyeLight") else null
@onready var thruster_l_light: OmniLight3D = $Model/ThrusterL/Light if has_node("Model/ThrusterL/Light") else null
@onready var thruster_r_light: OmniLight3D = $Model/ThrusterR/Light if has_node("Model/ThrusterR/Light") else null
@onready var ray_down: RayCast3D = $RayCastDown if has_node("RayCastDown") else null
@onready var ray_forward: RayCast3D = $RayCastForward if has_node("RayCastForward") else null
@onready var ray_left: RayCast3D = $RayCastLeft if has_node("RayCastLeft") else null
@onready var ray_right: RayCast3D = $RayCastRight if has_node("RayCastRight") else null
@onready var muzzle_l: Node3D = $Model/MuzzleL if has_node("Model/MuzzleL") else null
@onready var muzzle_r: Node3D = $Model/MuzzleR if has_node("Model/MuzzleR") else null

# Procedural animation timers
var _anim_time: float = 0.0
var _current_pitch: float = 0.0
var _current_roll: float = 0.0

func _get_pos() -> Vector3:
	return global_position if is_inside_tree() else position

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("drones")
	health = max_health
	_patrol_origin = _get_pos()
	_orbit_direction = 1.0 if randf() > 0.5 else -1.0
	_pick_new_patrol_target()
	_find_player()
	_update_eye_visuals()

func _find_player() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree:
		_player = tree.get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if not is_active:
		# Fall gently if deactivated or dying
		velocity.y = move_toward(velocity.y, -12.0, 18.0 * delta)
		move_and_slide()
		return

	_anim_time += delta
	if _fire_timer > 0.0:
		_fire_timer -= delta

	if _player == null or not is_instance_valid(_player):
		_find_player()

	# Process current state
	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.ALERT:
			_process_alert(delta)
		State.COMBAT_ORBIT:
			_process_combat_orbit(delta)
		State.EVADE:
			_process_evade(delta)
		State.STAGGERED:
			_process_staggered(delta)

	move_and_slide()
	_update_flight_dynamics(delta)

# ----------------------------------------------------
# PERCEPTION & VISION
# ----------------------------------------------------
func can_see_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false

	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > view_distance:
		return false

	# Wide forward cone
	var forward_dir := -global_transform.basis.z.normalized()
	var angle := rad_to_deg(forward_dir.angle_to(to_player.normalized()))
	if angle > (view_angle_deg * 0.5):
		return false

	# Raycast check against environment (Layer 1)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		_player.global_position + Vector3(0, 1.0, 0),
		1
	)
	query.exclude = [get_rid()]
	var res := space_state.intersect_ray(query)
	return res.is_empty()

func can_hear_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var dist := global_position.distance_to(_player.global_position)
	if dist > hearing_distance:
		return false
	var player_char := _player as CharacterBody3D
	if player_char:
		if "is_dashing" in player_char and player_char.is_dashing:
			return true
		if Input.is_action_pressed("sprint") and player_char.velocity.length() > 6.0:
			return true
	return false

# ----------------------------------------------------
# STATE LOGIC
# ----------------------------------------------------
func _process_patrol(delta: float) -> void:
	if can_see_player() or can_hear_player():
		_enter_state(State.ALERT)
		return

	_patrol_timer -= delta
	var dist_to_target := _get_pos().distance_to(_patrol_target)
	if _patrol_timer <= 0.0 or dist_to_target < 2.0:
		_pick_new_patrol_target()

	_fly_toward(_patrol_target, patrol_speed, delta)

func _process_alert(delta: float) -> void:
	# Brief alarm broadcast window (0.45s) where drone sounds alarm and turns to face player
	_alert_timer -= delta
	if _player and is_instance_valid(_player):
		var to_player := _player.global_position - _get_pos()
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * 1.5 * delta)

	# Hover in place during alert chirp
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	_maintain_altitude(delta)

	if _alert_timer <= 0.0:
		_enter_state(State.COMBAT_ORBIT)

func _process_combat_orbit(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_enter_state(State.PATROL)
		return

	var dist := _get_pos().distance_to(_player.global_position)

	# If player closed in too close, evade!
	if dist < 5.0:
		_enter_state(State.EVADE)
		return

	# Calculate circling combat vector around player
	var to_player := (_player.global_position - _get_pos()).normalized()
	var tangent := to_player.cross(Vector3.UP).normalized() * _orbit_direction
	
	# Radial distance adjustment (move closer if too far, back up if too close)
	var radial_bias: Vector3 = Vector3.ZERO
	if dist > combat_preferred_dist + 2.5:
		radial_bias = to_player * 0.7
	elif dist < combat_preferred_dist - 2.5:
		radial_bias = -to_player * 0.7

	var target_fly_dir := (tangent + radial_bias).normalized()
	_apply_flight_velocity(target_fly_dir, chase_speed, delta)

	# Face towards player for aiming
	var target_yaw := atan2(-to_player.x, -to_player.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

	# Firing logic
	if _fire_timer <= 0.0 and can_see_player():
		_shoot_pulse_burst()

func _process_evade(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_enter_state(State.PATROL)
		return

	var dist := _get_pos().distance_to(_player.global_position)
	if dist > combat_preferred_dist:
		_enter_state(State.COMBAT_ORBIT)
		return

	# Back away rapidly while strafing
	var away_dir := (_get_pos() - _player.global_position).normalized()
	away_dir.y = 0.0
	var strafe := away_dir.cross(Vector3.UP).normalized() * _orbit_direction * 0.6
	var evade_dir := (away_dir + strafe).normalized()

	_apply_flight_velocity(evade_dir, evasion_speed, delta)

	# Face player while retreating
	var to_player := (_player.global_position - _get_pos()).normalized()
	var target_yaw := atan2(-to_player.x, -to_player.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * 1.8 * delta)

	# Defensive retaliatory shot
	if _fire_timer <= 0.0:
		_shoot_pulse_burst()

func _process_staggered(delta: float) -> void:
	_stagger_timer -= delta
	# Thruster instability wobble
	velocity.x = move_toward(velocity.x, sin(_anim_time * 20.0) * 2.0, 15.0 * delta)
	velocity.z = move_toward(velocity.z, cos(_anim_time * 20.0) * 2.0, 15.0 * delta)
	_maintain_altitude(delta)

	if _stagger_timer <= 0.0:
		_enter_state(State.COMBAT_ORBIT)

# ----------------------------------------------------
# COMBAT & ATTACKS
# ----------------------------------------------------
func _shoot_pulse_burst() -> void:
	_fire_timer = fire_cooldown
	if _player == null:
		return

	# Twin pulse laser shot from left and right muzzles
	_fire_single_pulse(muzzle_l if muzzle_l else self)
	
	# Staggered second shot via timer
	var tree := get_tree() if is_inside_tree() else null
	if tree:
		tree.create_timer(0.12, true, false, true).timeout.connect(func():
			if is_instance_valid(self) and is_active and _player:
				_fire_single_pulse(muzzle_r if muzzle_r else self)
		, CONNECT_ONE_SHOT)

func _fire_single_pulse(muzzle_node: Node3D) -> void:
	var muzzle_pos: Vector3 = muzzle_node.global_position if is_inside_tree() else _get_pos()
	var target_pos := _player.global_position + Vector3(0, 1.0, 0)
	
	# Slight aim lead
	var player_char := _player as CharacterBody3D
	if player_char:
		target_pos += player_char.velocity * 0.15

	var dir := (target_pos - muzzle_pos).normalized()

	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	var parent_scene := get_parent()
	if parent_scene:
		parent_scene.add_child(proj)
		proj.global_position = muzzle_pos
		proj.setup(self, dir, {
			"projectile_speed": 45.0,
			"damage": 12.0,
			"gravity_scale": 0.0,
			"is_explosive": false
		})

	# Sound
	var tree := get_tree() if is_inside_tree() else null
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	if audio and audio.has_method("play_drone_laser"):
		audio.play_drone_laser()
	elif audio and audio.has_method("play_pistol"):
		audio.play_pistol()

func broadcast_alert_to_allies() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if not tree:
		return

	var current_pos := _get_pos()
	var allies := tree.get_nodes_in_group("enemy")
	for ally in allies:
		if ally == self:
			continue
		var ally_pos: Vector3 = ally.global_position if ally.is_inside_tree() else ally.position
		if current_pos.distance_to(ally_pos) <= alert_broadcast_radius:
			if ally.has_method("receive_alert"):
				ally.receive_alert(_player.global_position if _player else current_pos)

	# Audio alert chirp
	var audio = tree.get_first_node_in_group("audio_manager")
	if audio and audio.has_method("play_drone_alert"):
		audio.play_drone_alert()
	elif audio and audio.has_method("play_alert"):
		audio.play_alert()

func receive_alert(target_pos: Vector3) -> void:
	if current_state == State.PATROL:
		_patrol_target = target_pos
		_enter_state(State.ALERT)

# ----------------------------------------------------
# DAMAGE & ELIMINATION
# ----------------------------------------------------
func take_damage(amount: float, attacker: Node3D = null) -> void:
	if not is_active:
		return

	health -= amount
	_stagger_timer = 0.8
	_enter_state(State.STAGGERED)

	# Flash eye light bright red/white
	if eye_light:
		eye_light.light_color = Color(1.0, 0.2, 0.1)
		eye_light.light_energy = 5.0

	var tree := get_tree() if is_inside_tree() else null
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	if audio and audio.has_method("play_hit"):
		audio.play_hit()

	if health <= 0.0:
		_die(attacker)

func _die(killer: Node3D) -> void:
	is_active = false
	remove_from_group("enemy")
	remove_from_group("drones")
	drone_destroyed.emit(character_name)

	# Notify GameManager if present for score
	var tree := get_tree() if is_inside_tree() else null
	var gm = tree.get_first_node_in_group("game_manager") if tree else null
	if gm and gm.has_method("add_score"):
		gm.add_score(150)

	# Death sequence: spin out and explode
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", rotation.y + 12.0, 0.4)
	tw.parallel().tween_property(self, "position:y", position.y - 1.5, 0.4)
	tw.chain().tween_callback(_spawn_death_explosion)

func _spawn_death_explosion() -> void:
	var tree := get_tree() if is_inside_tree() else null
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	if audio and audio.has_method("play_explosion"):
		audio.play_explosion()
	queue_free()

# ----------------------------------------------------
# FLIGHT DYNAMICS & STEERING
# ----------------------------------------------------
func _fly_toward(target_pos: Vector3, speed_val: float, delta: float) -> void:
	var to_dest := target_pos - _get_pos()
	to_dest.y = 0.0
	var fly_dir := to_dest.normalized()

	_apply_flight_velocity(fly_dir, speed_val, delta)

	if fly_dir.length_squared() > 0.01:
		var target_yaw := atan2(-fly_dir.x, -fly_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

func _apply_flight_velocity(desired_dir: Vector3, speed_val: float, delta: float) -> void:
	var avoidance := Vector3.ZERO
	if ray_forward and ray_forward.is_colliding():
		var norm = ray_forward.get_collision_normal()
		norm.y = 0.0
		avoidance += norm.normalized() * 3.0
	if ray_left and ray_left.is_colliding():
		avoidance += global_transform.basis.x * 2.0
	if ray_right and ray_right.is_colliding():
		avoidance += -global_transform.basis.x * 2.0

	var final_dir: Vector3
	if avoidance.length_squared() > 0.01:
		final_dir = (desired_dir + avoidance).normalized()
	else:
		final_dir = desired_dir

	velocity.x = move_toward(velocity.x, final_dir.x * speed_val, 15.0 * delta)
	velocity.z = move_toward(velocity.z, final_dir.z * speed_val, 15.0 * delta)
	_maintain_altitude(delta)

func _maintain_altitude(delta: float) -> void:
	var current_y := _get_pos().y
	var ground_y := 0.0

	if ray_down and ray_down.is_colliding():
		ground_y = ray_down.get_collision_point().y
	else:
		ground_y = _patrol_origin.y

	var desired_y := ground_y + target_altitude + sin(_anim_time * 3.5) * 0.18
	var diff_y := desired_y - current_y
	velocity.y = move_toward(velocity.y, diff_y * 4.5, 20.0 * delta)

func _update_flight_dynamics(delta: float) -> void:
	if not model:
		return

	# Bank into turns (roll) and tilt into forward acceleration (pitch)
	var local_vel := global_transform.basis.inverse() * velocity
	var target_pitch := clampf(-local_vel.z * 0.035, -0.35, 0.35)
	var target_roll := clampf(-local_vel.x * 0.045, -0.4, 0.4)

	_current_pitch = lerp(_current_pitch, target_pitch, 8.0 * delta)
	_current_roll = lerp(_current_roll, target_roll, 8.0 * delta)

	model.rotation.x = _current_pitch
	model.rotation.z = _current_roll

	# Thruster flicker
	var thruster_energy := 2.5 + sin(_anim_time * 25.0) * 0.8
	if thruster_l_light:
		thruster_l_light.light_energy = thruster_energy
	if thruster_r_light:
		thruster_r_light.light_energy = thruster_energy

func _enter_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(State.keys()[new_state])
	_update_eye_visuals()

	match new_state:
		State.ALERT:
			_alert_timer = 0.45
			broadcast_alert_to_allies()
		State.EVADE:
			_orbit_direction = -_orbit_direction # Reverse orbit on retreat

func _update_eye_visuals() -> void:
	if not eye_light:
		return
	match current_state:
		State.PATROL:
			eye_light.light_color = Color(0.1, 0.9, 1.0) # Calm cyan
			eye_light.light_energy = 2.0
		State.ALERT:
			eye_light.light_color = Color(1.0, 0.8, 0.1) # Warning amber
			eye_light.light_energy = 4.5
		State.COMBAT_ORBIT, State.EVADE:
			eye_light.light_color = Color(1.0, 0.15, 0.15) # Combat crimson
			eye_light.light_energy = 3.5
		State.STAGGERED:
			eye_light.light_color = Color(1.0, 0.6, 0.1) # Glitch yellow
			eye_light.light_energy = 1.0

func _pick_new_patrol_target() -> void:
	_patrol_timer = randf_range(4.5, 7.5)
	var offset := Vector3(randf_range(-16.0, 16.0), 0.0, randf_range(-16.0, 16.0))
	_patrol_target = _patrol_origin + offset

