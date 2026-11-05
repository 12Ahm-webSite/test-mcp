extends CharacterBody3D

signal state_changed(new_state: String)
signal brute_defeated(brute_name: String)

enum State {
	PATROL,
	CHASE,
	SLAM_WINDUP,
	SLAM_IMPACT,
	MORTAR_FIRE,
	STAGGERED
}

@export_group("Brute Attributes")
@export var character_name: String = "Heavy-Brute"
@export var max_health: float = 280.0
@export var patrol_speed: float = 2.4
@export var chase_speed: float = 3.6
@export var turn_speed: float = 4.8
@export var slam_range: float = 4.2
@export var slam_radius: float = 5.5
@export var slam_damage: float = 42.0
@export var mortar_min_range: float = 7.0
@export var mortar_max_range: float = 32.0
@export var mortar_cooldown: float = 3.8
@export var mortar_damage: float = 45.0
@export var view_distance: float = 26.0
@export var view_angle_deg: float = 120.0
@export var gravity: float = 19.6

var health: float = 280.0
var current_state: State = State.PATROL
var is_active: bool = true

# Targets & Timers
var _player: Node3D = null
var _patrol_origin: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_timer: float = 0.0
var _mortar_timer: float = 1.0
var _slam_timer: float = 0.0
var _stagger_timer: float = 0.0
var _shockwave_mesh: MeshInstance3D = null

# Anti-stuck
var _last_pos: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
var _unstick_timer: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO

# Projectile
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

# Node references
@onready var model: Node3D = $Model
@onready var visor_light: OmniLight3D = $Model/Head/VisorLight if has_node("Model/Head/VisorLight") else null
@onready var arm_l_pivot: Node3D = $Model/ArmL_Pivot if has_node("Model/ArmL_Pivot") else null
@onready var arm_r_pivot: Node3D = $Model/ArmR_Pivot if has_node("Model/ArmR_Pivot") else null
@onready var mortar_muzzle: Node3D = $Model/ArmR_Pivot/CannonBarrel/Muzzle if has_node("Model/ArmR_Pivot/CannonBarrel/Muzzle") else null
@onready var shockwave_node: MeshInstance3D = $Shockwave if has_node("Shockwave") else null
@onready var ray_forward: RayCast3D = $RayCastForward if has_node("RayCastForward") else null
@onready var ray_left: RayCast3D = $RayCastLeft if has_node("RayCastLeft") else null
@onready var ray_right: RayCast3D = $RayCastRight if has_node("RayCastRight") else null

var _anim_time: float = 0.0

func _get_pos() -> Vector3:
	return global_position if is_inside_tree() else position

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("brutes")
	health = max_health
	_patrol_origin = _get_pos()
	_last_pos = _get_pos()
	_pick_new_patrol_target()
	_find_player()
	if shockwave_node:
		shockwave_node.visible = false

func _find_player() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree:
		_player = tree.get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if not is_active:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		move_and_slide()
		return

	_anim_time += delta
	if _mortar_timer > 0.0:
		_mortar_timer -= delta

	if _player == null or not is_instance_valid(_player):
		_find_player()

	# Process current state
	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.SLAM_WINDUP:
			_process_slam_windup(delta)
		State.SLAM_IMPACT:
			_process_slam_impact(delta)
		State.MORTAR_FIRE:
			_process_mortar_fire(delta)
		State.STAGGERED:
			_process_staggered(delta)

	move_and_slide()
	_update_brute_animations(delta)

# ----------------------------------------------------
# PERCEPTION
# ----------------------------------------------------
func can_see_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false

	var to_player := _player.global_position - _get_pos()
	var dist := to_player.length()
	if dist > view_distance:
		return false

	var forward_dir := -global_transform.basis.z.normalized()
	var angle := rad_to_deg(forward_dir.angle_to(to_player.normalized()))
	if angle > (view_angle_deg * 0.5):
		return false

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		_get_pos() + Vector3(0, 1.8, 0),
		_player.global_position + Vector3(0, 1.0, 0),
		1
	)
	query.exclude = [get_rid()]
	var res := space_state.intersect_ray(query)
	return res.is_empty()

# ----------------------------------------------------
# STATE LOGIC
# ----------------------------------------------------
func _process_patrol(delta: float) -> void:
	if can_see_player():
		_enter_state(State.CHASE)
		return

	_patrol_timer -= delta
	var dist := _get_pos().distance_to(_patrol_target)
	if _patrol_timer <= 0.0 or dist < 2.0:
		_pick_new_patrol_target()

	_move_towards(_patrol_target, patrol_speed, delta)

func _process_chase(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_enter_state(State.PATROL)
		return

	var dist := _get_pos().distance_to(_player.global_position)

	# Close range -> Trigger Ground Slam
	if dist <= slam_range:
		_enter_state(State.SLAM_WINDUP)
		return

	# Medium-long range -> Check Mortar Artillery
	if dist >= mortar_min_range and dist <= mortar_max_range and _mortar_timer <= 0.0 and can_see_player():
		_enter_state(State.MORTAR_FIRE)
		return

	# Chase player
	_move_towards(_player.global_position, chase_speed, delta)

func _process_slam_windup(delta: float) -> void:
	# Stop and telegraph attack
	velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)

	# Turn slowly toward player during windup
	if _player:
		var to_player := _player.global_position - _get_pos()
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 3.5 * delta)

	_slam_timer -= delta
	if _slam_timer <= 0.0:
		_execute_ground_slam()

func _execute_ground_slam() -> void:
	current_state = State.SLAM_IMPACT
	_slam_timer = 0.55

	# Heavy camera shake on player
	var tree := get_tree() if is_inside_tree() else null
	if _player and _player.has_method("add_camera_shake"):
		var dist := _get_pos().distance_to(_player.global_position)
		if dist < 20.0:
			var shake := clampf(1.0 - (dist / 20.0), 0.2, 0.85)
			_player.add_camera_shake(shake)

	# Audio
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	if audio and audio.has_method("play_explosion"):
		audio.play_explosion()

	# Expand shockwave ring
	if shockwave_node:
		shockwave_node.visible = true
		shockwave_node.scale = Vector3(0.5, 0.1, 0.5)
		var tw := create_tween()
		tw.tween_property(shockwave_node, "scale", Vector3(slam_radius * 2.0, 0.2, slam_radius * 2.0), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(shockwave_node, "transparency", 1.0, 0.35)
		tw.chain().tween_callback(func():
			if shockwave_node:
				shockwave_node.visible = false
				shockwave_node.transparency = 0.0
		)

	# Hit player if in radius
	if _player:
		var dist := _get_pos().distance_to(_player.global_position)
		if dist <= slam_radius:
			if _player.has_method("take_hit"):
				_player.take_hit(slam_damage, self)
			elif _player.has_method("take_damage"):
				_player.take_damage(slam_damage, self)

func _process_slam_impact(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	_slam_timer -= delta
	if _slam_timer <= 0.0:
		_enter_state(State.CHASE)

func _process_mortar_fire(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)

	# Face target
	if _player:
		var to_player := _player.global_position - _get_pos()
		var target_yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 5.0 * delta)

	# Fire mortar shell
	_launch_mortar_shell()
	_mortar_timer = mortar_cooldown
	_enter_state(State.CHASE)

func _launch_mortar_shell() -> void:
	if _player == null:
		return

	var spawn_pos := mortar_muzzle.global_position if (mortar_muzzle and is_inside_tree()) else (_get_pos() + Vector3(0, 2.0, 0))
	var target_pos := _player.global_position
	var to_target := target_pos - spawn_pos
	var horiz_dist := Vector2(to_target.x, to_target.z).length()

	# Calculate upward arc trajectory
	var launch_dir := to_target.normalized()
	launch_dir.y += clampf(horiz_dist * 0.04, 0.25, 0.65)
	launch_dir = launch_dir.normalized()

	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	var parent_scene := get_parent()
	if parent_scene:
		parent_scene.add_child(proj)
		proj.global_position = spawn_pos
		proj.setup(self, launch_dir, {
			"projectile_speed": 24.0,
			"damage": mortar_damage,
			"gravity_scale": 1.1,
			"is_explosive": true,
			"explosion_radius": 6.2
		})

	# Mortar launch sound
	var tree := get_tree() if is_inside_tree() else null
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	if audio and audio.has_method("play_grenade_throw"):
		audio.play_grenade_throw()

func _process_staggered(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	_stagger_timer -= delta
	if _stagger_timer <= 0.0:
		_enter_state(State.CHASE)

# ----------------------------------------------------
# NAVIGATION & MOVEMENT
# ----------------------------------------------------
func _move_towards(target_pos: Vector3, move_speed: float, delta: float) -> void:
	var to_target := target_pos - _get_pos()
	to_target.y = 0.0
	var dist := to_target.length()
	if dist < 0.3:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		return

	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		velocity.x = _unstick_dir.x * move_speed
		velocity.z = _unstick_dir.z * move_speed
		return

	var desired_dir := to_target.normalized()
	var avoidance := Vector3.ZERO
	if ray_forward and ray_forward.is_colliding():
		var norm = ray_forward.get_collision_normal()
		norm.y = 0.0
		avoidance += norm.normalized() * 2.5
	if ray_left and ray_left.is_colliding():
		avoidance += global_transform.basis.x * 1.5
	if ray_right and ray_right.is_colliding():
		avoidance += -global_transform.basis.x * 1.5

	var final_dir: Vector3
	if avoidance.length_squared() > 0.01:
		final_dir = (desired_dir + avoidance).normalized()
	else:
		final_dir = desired_dir

	velocity.x = move_toward(velocity.x, final_dir.x * move_speed, 8.0 * delta)
	velocity.z = move_toward(velocity.z, final_dir.z * move_speed, 8.0 * delta)

	var target_yaw := atan2(-final_dir.x, -final_dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

	# Anti-stuck monitor
	var moved := _get_pos().distance_to(_last_pos)
	if moved < 0.03 and move_speed > 1.0:
		_stuck_timer += delta
		if _stuck_timer > 0.5:
			_stuck_timer = 0.0
			_unstick_timer = 0.7
			var right_vec := final_dir.cross(Vector3.UP).normalized()
			_unstick_dir = (-final_dir * 0.5 + right_vec * (1.0 if randf() > 0.5 else -1.0)).normalized()
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta)
	_last_pos = _get_pos()

# ----------------------------------------------------
# DAMAGE & RECEPTION
# ----------------------------------------------------
func take_damage(amount: float, attacker: Node3D = null) -> void:
	if not is_active:
		return

	# Armored hull absorbs 20% of incoming damage
	var absorbed_damage := amount * 0.8
	health -= absorbed_damage

	# Poise: Heavy Brute only staggers briefly (0.35s)
	_stagger_timer = 0.35
	_enter_state(State.STAGGERED)

	if visor_light:
		visor_light.light_energy = 5.0
		visor_light.light_color = Color(1.0, 0.4, 0.1)

	var tree := get_tree() if is_inside_tree() else null
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	if audio and audio.has_method("play_hit"):
		audio.play_hit()

	if health <= 0.0:
		_die(attacker)

func receive_alert(target_pos: Vector3) -> void:
	if current_state == State.PATROL:
		_patrol_target = target_pos
		_enter_state(State.CHASE)

func _die(killer: Node3D) -> void:
	is_active = false
	remove_from_group("enemy")
	remove_from_group("brutes")
	brute_defeated.emit(character_name)

	var tree := get_tree() if is_inside_tree() else null
	var gm = tree.get_first_node_in_group("game_manager") if tree else null
	if gm and gm.has_method("add_score"):
		gm.add_score(350)

	# Reactor meltdown death animation
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.2, 0.7, 1.2), 0.5).set_trans(Tween.TRANS_ELASTIC)
	tw.chain().tween_callback(func():
		var audio = tree.get_first_node_in_group("audio_manager") if tree else null
		if audio and audio.has_method("play_explosion"):
			audio.play_explosion()
		queue_free()
	)

# ----------------------------------------------------
# STATE & ANIMATION HELPERS
# ----------------------------------------------------
func _enter_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(State.keys()[new_state])
	_update_visor_visuals()

	match new_state:
		State.SLAM_WINDUP:
			_slam_timer = 0.65
		State.MORTAR_FIRE:
			pass

func _update_visor_visuals() -> void:
	if not visor_light:
		return
	match current_state:
		State.PATROL:
			visor_light.light_color = Color(0.9, 0.2, 0.1)
			visor_light.light_energy = 2.0
		State.CHASE:
			visor_light.light_color = Color(1.0, 0.05, 0.05)
			visor_light.light_energy = 3.8
		State.SLAM_WINDUP:
			visor_light.light_color = Color(1.0, 0.8, 0.1) # Danger yellow
			visor_light.light_energy = 6.0
		State.STAGGERED:
			visor_light.light_color = Color(1.0, 0.5, 0.2)
			visor_light.light_energy = 1.5

func _update_brute_animations(delta: float) -> void:
	# Heavy footsteps bobbing
	var is_moving := velocity.length() > 0.5
	var bob := sin(_anim_time * 5.0) * (0.07 if is_moving else 0.02)
	if model:
		model.position.y = 1.2 + bob

	# Arms posing based on state
	if arm_l_pivot and arm_r_pivot:
		match current_state:
			State.SLAM_WINDUP:
				# Raise arms high above head
				arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, deg_to_rad(-110.0), 8.0 * delta)
				arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, deg_to_rad(-110.0), 8.0 * delta)
			State.SLAM_IMPACT:
				# Slam downward into floor
				arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, deg_to_rad(65.0), 18.0 * delta)
				arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, deg_to_rad(65.0), 18.0 * delta)
			State.MORTAR_FIRE:
				# Cannon arm raised at 45 degree angle
				arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, deg_to_rad(-45.0), 10.0 * delta)
				arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, 0.0, 6.0 * delta)
			_:
				# Normal plodding stride arm swing
				var swing := sin(_anim_time * 4.0) * (0.35 if is_moving else 0.05)
				arm_l_pivot.rotation.x = lerp_angle(arm_l_pivot.rotation.x, swing, 6.0 * delta)
				arm_r_pivot.rotation.x = lerp_angle(arm_r_pivot.rotation.x, -swing, 6.0 * delta)

func _pick_new_patrol_target() -> void:
	_patrol_timer = randf_range(5.0, 9.0)
	var offset := Vector3(randf_range(-12.0, 12.0), 0.0, randf_range(-12.0, 12.0))
	_patrol_target = _patrol_origin + offset

