class_name BattleBot
extends CharacterBody3D

signal eliminated(bot_name: String, killer: Node3D)
signal respawned(bot_name: String)
signal alliance_state_changed(bot_name: String, is_allied: bool)

enum State {
	ROAM_HUNT,
	ENGAGE,
	SCAVENGE,
	ALLIED_TRUCE,
	DEAD
}

@export var character_name: String = "Bot-Alpha"
@export var bot_id: int = 1
@export var max_health: float = 100.0
@export var walk_speed: float = 3.6
@export var run_speed: float = 5.5
@export var attack_range: float = 18.0
@export var fire_accuracy: float = 0.72

var health: float = 100.0
var state: State = State.ROAM_HUNT
var is_allied_with_player: bool = false
var ally_partner: Node3D = null
var current_target: Node3D = null
var is_dead: bool = false
var _reaction_timer: float = 0.5

# Weapon & Combat
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const PICKUP_SCENE := preload("res://scenes/pickup_weapon.tscn")
var current_weapon: int = WeaponData.WeaponType.PISTOL
var ammo: Dictionary = {
	WeaponData.WeaponType.PISTOL: 999,
	WeaponData.WeaponType.SMG: 0
}
var _fire_cooldown_timer: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0
var _rethink_timer: float = 0.0
var _nav_target_pos: Vector3 = Vector3.ZERO
var _has_nav_target: bool = false

# Buffs
var has_shield: bool = false
var speed_boost_factor: float = 1.0

# Anti-stuck & obstacle navigation
var _last_pos: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
var _unstick_timer: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO

# Node references
@onready var model: Node3D = $Model
@onready var weapon_mount: Node3D = $Model/WeaponMount if has_node("Model/WeaponMount") else null
@onready var pistol_model: Node3D = $Model/WeaponMount/PistolModel if has_node("Model/WeaponMount/PistolModel") else null
@onready var smg_model: Node3D = $Model/WeaponMount/SMGModel if has_node("Model/WeaponMount/SMGModel") else null
@onready var muzzle_point: Node3D = $Model/WeaponMount/MuzzlePoint if has_node("Model/WeaponMount/MuzzlePoint") else null
@onready var muzzle_flash: OmniLight3D = $Model/WeaponMount/MuzzlePoint/MuzzleFlash if has_node("Model/WeaponMount/MuzzlePoint/MuzzleFlash") else null
@onready var billboard_label: Label3D = $BillboardLabel
@onready var ray_obstacle_center: RayCast3D = $RayObstacleCenter
@onready var ray_obstacle_left: RayCast3D = $RayObstacleLeft
@onready var ray_obstacle_right: RayCast3D = $RayObstacleRight

func _get_safe_tree() -> SceneTree:
	return get_tree() if is_inside_tree() else null

func _get_pos() -> Vector3:
	return global_position if is_inside_tree() else position

func _ready() -> void:
	add_to_group("battle_bot")
	add_to_group("combatant")
	_last_pos = _get_pos()
	_apply_difficulty()
	_update_billboard()
	_update_weapon_models()
	_pick_new_roam_target()

func _apply_difficulty() -> void:
	var tree := _get_safe_tree()
	var bm = tree.get_first_node_in_group("battle_manager") if tree else null
	if bm and bm.has_method("get_difficulty_params"):
		var p: Dictionary = bm.get_difficulty_params()
		max_health = p.get("bot_max_health", 65.0)
		walk_speed = p.get("bot_walk_speed", 3.0)
		run_speed = p.get("bot_run_speed", 4.5)
		fire_accuracy = p.get("bot_accuracy", 0.45)
		_reaction_timer = p.get("bot_reaction_delay", 0.8)
	else:
		max_health = 65.0
		walk_speed = 3.0
		run_speed = 4.5
		fire_accuracy = 0.45
		_reaction_timer = 0.8
	health = max_health

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	# Fire rate cooldown
	if _fire_cooldown_timer > 0.0:
		_fire_cooldown_timer -= delta
		
	# Periodic AI rethink & Target acquisition
	_rethink_timer -= delta
	if _rethink_timer <= 0.0:
		_rethink_timer = randf_range(0.35, 0.65)
		_evaluate_ai_state()
		
	# State execution
	match state:
		State.ROAM_HUNT:
			_process_roam(delta)
		State.ENGAGE, State.ALLIED_TRUCE:
			_process_engage(delta)
		State.SCAVENGE:
			_process_scavenge(delta)
			
	# Gravity
	if not is_on_floor():
		velocity.y -= 19.6 * delta
	else:
		if velocity.y <= 0.0:
			velocity.y = 0.0
			
	move_and_slide()
	_update_billboard()

func _evaluate_ai_state() -> void:
	# Check Scavenge condition: low health -> seek medkit
	if health < 40.0:
		var medkit = _find_nearest_pickup(PickupWeapon.PickupType.MEDKIT)
		if medkit:
			state = State.SCAVENGE
			_nav_target_pos = medkit.global_position
			_has_nav_target = true
			return
			
	# Check Alliance opportunity with Leader
	var tree := _get_safe_tree()
	var bm = tree.get_first_node_in_group("battle_manager") if tree else null
	if bm and bm.has_method("get_leader"):
		var leader: Node3D = bm.get_leader()
		var player = tree.get_first_node_in_group("player") if tree else null
		
		# If leader pulled ahead (>=2 kills lead), check if we team up
		if leader and leader != self:
			var leader_lead: int = bm.get_leader_lead()
			if leader_lead >= 2:
				if leader == player:
					# Player is dominating! Bot is hostile and hunts player
					is_allied_with_player = false
					current_target = player
					state = State.ENGAGE
					return
				else:
					# Another bot is dominating! Ally with player against that leader bot!
					if not is_allied_with_player:
						form_alliance_with(player)
					current_target = leader
					state = State.ALLIED_TRUCE
					return
					
	# Normal target acquisition
	var target = _find_best_target()
	if target:
		current_target = target
		var dist = global_position.distance_to(target.global_position)
		if dist <= attack_range:
			state = State.ENGAGE
		else:
			state = State.ROAM_HUNT
			_nav_target_pos = target.global_position
			_has_nav_target = true
	else:
		state = State.ROAM_HUNT
		if not _has_nav_target or global_position.distance_to(_nav_target_pos) < 2.0:
			_pick_new_roam_target()

func _find_best_target() -> Node3D:
	var candidates: Array[Node3D] = []
	
	var tree := _get_safe_tree()
	if not tree:
		return null
		
	# Add player if not allied
	var player = tree.get_first_node_in_group("player")
	if player and not is_allied_with_player and not ("is_dead" in player and player.is_dead):
		candidates.append(player)
		
	# Add other bots
	var all_bots = tree.get_nodes_in_group("battle_bot")
	for b in all_bots:
		var bot = b as BattleBot
		if bot and bot != self and not bot.is_dead:
			if is_allied_with_player and bot == ally_partner:
				continue
			candidates.append(bot)
			
	# Find closest candidate with line of sight prioritized
	var closest: Node3D = null
	var min_dist: float = 9999.0
	for cand in candidates:
		var d = global_position.distance_to(cand.global_position)
		if d < min_dist:
			min_dist = d
			closest = cand
			
	return closest

func _process_roam(delta: float) -> void:
	if not _has_nav_target or global_position.distance_to(_nav_target_pos) < 2.5:
		_pick_new_roam_target()
		
	_move_towards(_nav_target_pos, walk_speed, delta)

func _process_scavenge(delta: float) -> void:
	if health >= 85.0:
		state = State.ROAM_HUNT
		return
	_move_towards(_nav_target_pos, run_speed, delta)

func _process_engage(delta: float) -> void:
	if not is_instance_valid(current_target) or ("is_dead" in current_target and current_target.is_dead):
		current_target = null
		state = State.ROAM_HUNT
		return
		
	var target_pos := current_target.global_position
	var dist := global_position.distance_to(target_pos)
	
	# Rotate towards enemy
	var target_dir := (target_pos - global_position).normalized()
	target_dir.y = 0.0
	if target_dir.length_squared() > 0.01:
		var target_rot := atan2(-target_dir.x, -target_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_rot, 12.0 * delta)
		
	# Combat footwork: maintain tactical distance (~7-12m) and strafe
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.2, 2.5)
		_strafe_dir = -_strafe_dir if randf() > 0.3 else _strafe_dir
		
	var move_vec := Vector3.ZERO
	if dist > 12.0:
		move_vec += target_dir * 0.7 # Close distance
	elif dist < 6.0:
		move_vec -= target_dir * 0.9 # Back up
		
	# Lateral strafe
	var right_vec := Vector3(-target_dir.z, 0, target_dir.x)
	move_vec += right_vec * _strafe_dir * 0.8
	
	_apply_movement_with_avoidance(move_vec.normalized(), walk_speed, delta)
	
	# Attack if in range and line of sight is clear
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm and "is_match_starting" in bm and bm.is_match_starting:
		return
		
	if _reaction_timer > 0.0:
		_reaction_timer -= delta
	elif dist <= attack_range and _has_line_of_sight(current_target):
		_try_bot_shoot(target_pos)

func _move_towards(target_pt: Vector3, speed: float, delta: float) -> void:
	var dir := (target_pt - global_position).normalized()
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		var target_rot := atan2(-dir.x, -dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_rot, 8.0 * delta)
	_apply_movement_with_avoidance(dir, speed, delta)

func _apply_movement_with_avoidance(desired_dir: Vector3, speed: float, delta: float) -> void:
	# Active unstick maneuver
	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		velocity.x = _unstick_dir.x * speed * speed_boost_factor
		velocity.z = _unstick_dir.z * speed * speed_boost_factor
		var unstick_rot := atan2(-_unstick_dir.x, -_unstick_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, unstick_rot, 10.0 * delta)
		return

	var final_dir := desired_dir
	var avoidance := Vector3.ZERO
	
	# Raycast obstacle steering with collision normals
	if ray_obstacle_center and ray_obstacle_center.is_colliding():
		var norm = ray_obstacle_center.get_collision_normal()
		norm.y = 0.0
		if norm.length_squared() > 0.01:
			avoidance += norm.normalized() * 2.2
		elif ray_obstacle_left and not ray_obstacle_left.is_colliding():
			avoidance += -model.global_transform.basis.x * 1.5
		elif ray_obstacle_right and not ray_obstacle_right.is_colliding():
			avoidance += model.global_transform.basis.x * 1.5
		else:
			avoidance += -desired_dir * 1.5
			
	if ray_obstacle_left and ray_obstacle_left.is_colliding():
		var norm = ray_obstacle_left.get_collision_normal()
		norm.y = 0.0
		if norm.length_squared() > 0.01:
			avoidance += norm.normalized() * 1.4
		else:
			avoidance += model.global_transform.basis.x * 1.4

	if ray_obstacle_right and ray_obstacle_right.is_colliding():
		var norm = ray_obstacle_right.get_collision_normal()
		norm.y = 0.0
		if norm.length_squared() > 0.01:
			avoidance += norm.normalized() * 1.4
		else:
			avoidance += -model.global_transform.basis.x * 1.4

	if avoidance.length_squared() > 0.01:
		final_dir = (desired_dir + avoidance).normalized()
			
	velocity.x = move_toward(velocity.x, final_dir.x * speed * speed_boost_factor, 14.0 * delta)
	velocity.z = move_toward(velocity.z, final_dir.z * speed * speed_boost_factor, 14.0 * delta)

	# Anti-stuck detection: monitor physical displacement
	if speed > 1.0 and desired_dir.length_squared() > 0.01:
		var curr_pos := _get_pos()
		var moved_dist := curr_pos.distance_to(_last_pos)
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

func _has_line_of_sight(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from_pos := global_position + Vector3(0, 1.2, 0)
	var to_pos := target.global_position + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [self]
	query.collision_mask = 1 | 8 # Walls and Barrels
	var hit := space.intersect_ray(query)
	return hit.is_empty()

func _try_bot_shoot(target_pos: Vector3) -> void:
	if _fire_cooldown_timer > 0.0:
		return
		
	var w_data: Dictionary = WeaponData.get_weapon(current_weapon).duplicate()
	var tree := _get_safe_tree()
	var bm = tree.get_first_node_in_group("battle_manager") if tree else null
	var bot_dmg: float = 8.0
	if bm and bm.has_method("get_difficulty_params"):
		bot_dmg = bm.get_difficulty_params().get("bot_damage", 8.0)
	w_data["damage"] = bot_dmg
	_fire_cooldown_timer = w_data.get("fire_rate", 0.3) * randf_range(1.1, 1.4)
	
	var origin: Vector3 = muzzle_point.global_position if muzzle_point else global_position + Vector3(0, 1.1, -0.4)
	var aim_target: Vector3 = target_pos + Vector3(0, 0.9, 0)
	
	# Slight bot inaccuracy
	var inaccuracy: float = (1.0 - fire_accuracy) * 0.8
	aim_target += Vector3(randf_range(-inaccuracy, inaccuracy), randf_range(-inaccuracy * 0.5, inaccuracy * 0.5), randf_range(-inaccuracy, inaccuracy))
	
	var shoot_dir: Vector3 = (aim_target - origin).normalized()
	
	# Spawn Projectile
	var proj = PROJECTILE_SCENE.instantiate()
	get_parent().add_child(proj)
	proj.global_position = origin
	proj.setup(self, shoot_dir, w_data)
	
	# Audio & Muzzle flash
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	var sfx_name: String = w_data.get("sfx_method", "play_pistol")
	if audio and audio.has_method(sfx_name):
		audio.call(sfx_name)
		
	if muzzle_flash:
		muzzle_flash.visible = true
		if tree:
			tree.create_timer(0.04).timeout.connect(func(): if muzzle_flash: muzzle_flash.visible = false)

func take_damage(amount: float, attacker: Node3D = null) -> void:
	if is_dead:
		return
		
	# Alliance betrayal check
	if is_allied_with_player and attacker and attacker.is_in_group("player"):
		break_alliance("Betrayal! Player fired upon ally.")
		current_target = attacker
		state = State.ENGAGE
		
	health = maxf(0.0, health - amount)
	_update_billboard()
	
	# React to attacker
	if attacker and attacker != self and (not current_target or randf() > 0.5):
		if not (is_allied_with_player and attacker.is_in_group("player")):
			current_target = attacker
			state = State.ENGAGE
			
	if health <= 0.0:
		_die(attacker)

func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(max_health, health + amount)
	_update_billboard()

func pickup_weapon(w_type: int, amount: int) -> void:
	current_weapon = w_type
	ammo[w_type] = mini(ammo.get(w_type, 0) + amount, WeaponData.get_weapon(w_type).get("max_ammo", 999))
	_update_weapon_models()

func form_alliance_with(partner: Node3D) -> void:
	is_allied_with_player = true
	ally_partner = partner
	alliance_state_changed.emit(character_name, true)
	_update_billboard()
	
	if is_inside_tree() and get_tree():
		var bm = get_tree().get_first_node_in_group("battle_manager")
		if bm and bm.has_method("notify_alliance"):
			bm.notify_alliance(character_name, true)

func break_alliance(reason: String = "") -> void:
	if not is_allied_with_player:
		return
	is_allied_with_player = false
	ally_partner = null
	alliance_state_changed.emit(character_name, false)
	_update_billboard()
	
	if is_inside_tree() and get_tree():
		var bm = get_tree().get_first_node_in_group("battle_manager")
		if bm and bm.has_method("notify_alliance"):
			bm.notify_alliance(character_name, false)

func _die(killer: Node3D) -> void:
	is_dead = true
	state = State.DEAD
	visible = false
	velocity = Vector3.ZERO
	set_physics_process(false)
	
	_drop_loot()
	eliminated.emit(character_name, killer)
	
	if is_inside_tree() and get_tree():
		var bm = get_tree().get_first_node_in_group("battle_manager")
		if bm and bm.has_method("record_elimination"):
			bm.record_elimination(killer, self)
			
		# Respawn after 2.5s
		await get_tree().create_timer(2.5).timeout
		if is_instance_valid(self) and is_inside_tree():
			_respawn()

func _drop_loot() -> void:
	var parent_node := get_parent()
	if not parent_node:
		return
	var pickup = PICKUP_SCENE.instantiate()
	var roll := randf()
	if current_weapon == WeaponData.WeaponType.SMG or roll < 0.60:
		pickup.pickup_type = PickupWeapon.PickupType.SMG
	elif roll < 0.85:
		pickup.pickup_type = PickupWeapon.PickupType.GRENADE
	else:
		pickup.pickup_type = PickupWeapon.PickupType.MEDKIT
		
	parent_node.add_child(pickup)
	if is_inside_tree() and pickup.is_inside_tree():
		pickup.global_position = global_position + Vector3(0, 0.4, 0)
	else:
		pickup.position = position + Vector3(0, 0.4, 0)

func _respawn() -> void:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	var spawn_pos: Vector3 = global_position
	if bm and bm.has_method("get_safe_spawn_point"):
		spawn_pos = bm.get_safe_spawn_point()
	else:
		spawn_pos = global_position + Vector3(randf_range(-12.0, 12.0), 0.5, randf_range(-12.0, 12.0))
		
	global_position = spawn_pos
	health = max_health
	is_dead = false
	visible = true
	set_physics_process(true)
	current_target = null
	state = State.ROAM_HUNT
	_update_billboard()
	respawned.emit(character_name)

func _update_billboard() -> void:
	if not billboard_label:
		return
		
	var hp_pct: int = int((health / max_health) * 100.0)
	var hp_bar: String = ""
	var bars_count: int = int(health / 10.0)
	for i in range(10):
		hp_bar += "█" if i < bars_count else "░"
		
	var status_text := ""
	var status_color := Color.YELLOW
	if is_allied_with_player:
		status_text = "🟢 ALLIED (TRUCE)"
		status_color = Color(0.2, 1.0, 0.4)
	elif state == State.SCAVENGE:
		status_text = "🟡 SCAVENGING"
		status_color = Color(1.0, 0.85, 0.2)
	elif state == State.ENGAGE:
		status_text = "🔴 ENGAGED"
		status_color = Color(1.0, 0.3, 0.3)
	else:
		status_text = "⚪ PATROL"
		status_color = Color(0.8, 0.85, 0.9)
		
	billboard_label.text = "%s\n[%s] %d%%\n%s" % [character_name, hp_bar, hp_pct, status_text]
	billboard_label.modulate = status_color

func _update_weapon_models() -> void:
	if pistol_model:
		pistol_model.visible = (current_weapon == WeaponData.WeaponType.PISTOL)
	if smg_model:
		smg_model.visible = (current_weapon == WeaponData.WeaponType.SMG)

func _pick_new_roam_target() -> void:
	var tree := _get_safe_tree()
	var bm = tree.get_first_node_in_group("battle_manager") if tree else null
	if bm and bm.has_method("get_random_waypoint"):
		_nav_target_pos = bm.get_random_waypoint()
	else:
		_nav_target_pos = Vector3(randf_range(-20.0, 20.0), 0.5, randf_range(-20.0, 20.0))
	_has_nav_target = true

func _find_nearest_pickup(pickup_type: int) -> Node3D:
	var tree := _get_safe_tree()
	var pickups = tree.get_nodes_in_group("pickups") if tree else []
	var nearest: Node3D = null
	var min_dist: float = 9999.0
	for p in pickups:
		var pickup = p as PickupWeapon
		if pickup and pickup.visible and pickup.pickup_type == pickup_type:
			var d = global_position.distance_to(pickup.global_position)
			if d < min_dist:
				min_dist = d
				nearest = pickup
	return nearest

# Buff hooks
func activate_shield(duration: float = 12.0) -> void:
	has_shield = true
	var tree := _get_safe_tree()
	if tree:
		var timer := tree.create_timer(duration)
		await timer.timeout
	if is_instance_valid(self):
		has_shield = false

func activate_speed_boost(multiplier: float = 1.45, duration: float = 8.0) -> void:
	speed_boost_factor = multiplier
	var tree := _get_safe_tree()
	if tree:
		var timer := tree.create_timer(duration)
		await timer.timeout
	if is_instance_valid(self):
		speed_boost_factor = 1.0
