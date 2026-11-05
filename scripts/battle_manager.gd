class_name BattleManager
extends Node

signal scores_updated(scores: Dictionary, leader_name: String, leader_score: int)
signal kill_feed_announced(killer_name: String, victim_name: String, weapon_icon: String)
signal quota_updated(current_player_kills: int, quota: int, sector_title: String)
signal alliance_announced(message: String, is_positive: bool)
signal battle_ended(player_won: bool, winner_name: String)

@export var sector_id: String = "battle_1"
@export var sector_title: String = "Sector 1: Sunken Ruins"
@export var kill_quota: int = 5
@export var next_sector_scene: String = "res://scenes/levels/battle_2_canyon.tscn"
@export var is_championship_final: bool = false

enum Difficulty {
	EASY,
	MEDIUM,
	HARD
}
@export var difficulty: Difficulty = Difficulty.EASY

func get_difficulty_params() -> Dictionary:
	match difficulty:
		Difficulty.EASY:
			return {
				"bot_damage": 7.0,
				"bot_accuracy": 0.45,
				"bot_reaction_delay": 0.8,
				"bot_max_health": 65.0,
				"bot_walk_speed": 3.0,
				"bot_run_speed": 4.5,
				"kill_quota": kill_quota
			}
		Difficulty.MEDIUM:
			return {
				"bot_damage": 12.0,
				"bot_accuracy": 0.65,
				"bot_reaction_delay": 0.5,
				"bot_max_health": 85.0,
				"bot_walk_speed": 3.6,
				"bot_run_speed": 5.5,
				"kill_quota": kill_quota
			}
		Difficulty.HARD:
			return {
				"bot_damage": 18.0,
				"bot_accuracy": 0.80,
				"bot_reaction_delay": 0.3,
				"bot_max_health": 100.0,
				"bot_walk_speed": 4.2,
				"bot_run_speed": 6.5,
				"kill_quota": kill_quota
			}
	return {}

var scores: Dictionary = {}
var leader_name: String = ""
var leader_score: int = 0
var is_battle_over: bool = false
var is_match_starting: bool = true
var portal_active: bool = false
var spawn_points: Array[Vector3] = []
var waypoints: Array[Vector3] = []

@onready var audio_mgr: Node = preload("res://scripts/audio_manager.gd").new()

const BOT_NAMES := [
	"Bot-Alpha",
	"Bot-Bravo",
	"Bot-Charlie",
	"Bot-Delta",
	"Bot-Echo",
	"Bot-Foxtrot",
	"Bot-Golf"
]

func _ready() -> void:
	Engine.time_scale = 1.0
	add_to_group("battle_manager")
	add_child(audio_mgr)
	
	_init_combatants()
	_collect_spawn_points_and_waypoints()
	
	call_deferred("_start_match")

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _init_combatants() -> void:
	scores["Unit-07"] = 0
	for b_name in BOT_NAMES:
		scores[b_name] = 0
	leader_name = "None"
	leader_score = 0

func _collect_spawn_points_and_waypoints() -> void:
	# Look for SpawnPoints group or generate from arena bounds
	var tree := get_tree() if is_inside_tree() else null
	var sp_nodes = tree.get_nodes_in_group("spawn_points") if tree else []
	if not sp_nodes.is_empty():
		for sp in sp_nodes:
			if sp is Node3D:
				spawn_points.append(sp.global_position)
	else:
		# Fallback radial points around center
		for i in range(8):
			var angle := (float(i) / 8.0) * TAU
			var pt := Vector3(cos(angle) * 16.0, 0.5, sin(angle) * 16.0)
			spawn_points.append(pt)
			
	waypoints = spawn_points.duplicate()
	waypoints.append(Vector3.ZERO)
	waypoints.append(Vector3(8, 0.5, 8))
	waypoints.append(Vector3(-8, 0.5, -8))
	waypoints.append(Vector3(8, 0.5, -8))
	waypoints.append(Vector3(-8, 0.5, 8))

func _start_match() -> void:
	if audio_mgr and audio_mgr.has_method("play_bgm_for_level"):
		audio_mgr.play_bgm_for_level(sector_id)
		
	quota_updated.emit(scores.get("Unit-07", 0), kill_quota, sector_title)
	scores_updated.emit(scores, leader_name, leader_score)
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_signal("player_eliminated"):
		player.player_eliminated.connect(func(killer): _on_player_died(killer))

	# 3-second match start countdown
	is_match_starting = true
	alliance_announced.emit("⏳ MATCH STARTING IN 3...", true)
	if is_inside_tree() and get_tree():
		await get_tree().create_timer(1.0).timeout
		alliance_announced.emit("⏳ MATCH STARTING IN 2...", true)
		await get_tree().create_timer(1.0).timeout
		alliance_announced.emit("⏳ MATCH STARTING IN 1...", true)
		await get_tree().create_timer(1.0).timeout
		alliance_announced.emit("🔥 FIGHT! REACH %d KILLS TO UNLOCK EXTRACTION!" % kill_quota, true)
	is_match_starting = false

func _on_player_died(killer: Node3D) -> void:
	# Continuous player respawn (fast 1.8s timer)
	await get_tree().create_timer(1.8).timeout
	if is_inside_tree() and get_tree():
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("respawn_at"):
			var safe_sp := get_safe_spawn_point()
			player.respawn_at(safe_sp)

func record_elimination(killer: Node3D, victim: Node3D) -> void:
	if is_battle_over and not portal_active:
		return
		
	var killer_str := _resolve_name(killer)
	var victim_str := _resolve_name(victim)
	
	if killer_str.is_empty():
		killer_str = "Hazard"
		
	if not scores.has(killer_str):
		scores[killer_str] = 0
		
	if killer != victim:
		scores[killer_str] += 1
		
	# Update leader
	_refresh_leader()
	
	# Announce in killfeed
	var weapon_icon := "⚡"
	if killer and "current_weapon" in killer:
		match killer.current_weapon:
			WeaponData.WeaponType.PISTOL: weapon_icon = "🔫 ZC57"
			WeaponData.WeaponType.SMG: weapon_icon = "💥 MGP7"
			WeaponData.WeaponType.GRENADE: weapon_icon = "💣 M67"
	elif killer is PropFuelBarrel:
		weapon_icon = "🔥 Barrel"
		
	kill_feed_announced.emit(killer_str, victim_str, weapon_icon)
	var p_kills: int = scores.get("Unit-07", 0)
	quota_updated.emit(p_kills, kill_quota, sector_title)
	scores_updated.emit(scores, leader_name, leader_score)
	
	# Check for Quota Achievement
	if scores.get(killer_str, 0) >= kill_quota and not is_battle_over:
		_on_quota_reached(killer_str)

func _refresh_leader() -> void:
	var top_score := -1
	var top_name := "None"
	for k in scores:
		if scores[k] > top_score:
			top_score = scores[k]
			top_name = k
	leader_score = top_score
	leader_name = top_name

func get_leader() -> Node3D:
	if leader_name == "Unit-07":
		return get_tree().get_first_node_in_group("player")
	var bots = get_tree().get_nodes_in_group("battle_bot")
	for b in bots:
		if b.character_name == leader_name:
			return b
	return null

func get_leader_lead() -> int:
	var sorted_scores: Array[int] = []
	for k in scores:
		sorted_scores.append(scores[k])
	sorted_scores.sort()
	sorted_scores.reverse()
	if sorted_scores.size() >= 2:
		return sorted_scores[0] - sorted_scores[1]
	return 0

func notify_alliance(bot_name: String, is_allied: bool) -> void:
	if is_allied:
		alliance_announced.emit("🤝 %s formed a temporary truce with you!" % bot_name, true)
	else:
		alliance_announced.emit("⚠️ %s broke the alliance! Watch your back!" % bot_name, false)

func get_safe_spawn_point() -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 1.0, 0)
		
	# Find spawn point furthest from active combatants
	var combatants: Array[Node3D] = []
	var player = get_tree().get_first_node_in_group("player")
	if player and not ("is_dead" in player and player.is_dead):
		combatants.append(player)
	var bots = get_tree().get_nodes_in_group("battle_bot")
	for b in bots:
		if not b.is_dead:
			combatants.append(b)
			
	var best_sp := spawn_points[0]
	var max_min_dist := -1.0
	
	for sp in spawn_points:
		var min_d_to_combatant := 9999.0
		for c in combatants:
			var d = sp.distance_to(c.global_position)
			if d < min_d_to_combatant:
				min_d_to_combatant = d
		if min_d_to_combatant > max_min_dist:
			max_min_dist = min_d_to_combatant
			best_sp = sp
			
	return best_sp + Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))

func get_random_waypoint() -> Vector3:
	if waypoints.is_empty():
		return Vector3(randf_range(-15, 15), 0.5, randf_range(-15, 15))
	return waypoints.pick_random() + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))

func _resolve_name(node: Node3D) -> String:
	if not node:
		return "Unknown"
	if node.is_in_group("player") or node.name == "Player" or node.name.begins_with("Player") or (node is CharacterBody3D and "character_name" in node and node.character_name == "Unit-07"):
		return "Unit-07"
	if "character_name" in node and not str(node.character_name).is_empty():
		return str(node.character_name)
	if node is PropFuelBarrel or node.name.contains("Barrel"):
		return "Fuel Barrel"
	return node.name

func _on_quota_reached(winner_str: String) -> void:
	var player_won := (winner_str == "Unit-07")
	
	if is_championship_final:
		is_battle_over = true
		battle_ended.emit(player_won, winner_str)
		return
		
	if player_won:
		# Player reached quota! Activate Extraction Portal
		var portal = get_tree().get_first_node_in_group("portal")
		if portal and portal.has_method("activate"):
			portal.activate()
			portal_active = true
			if audio_mgr and audio_mgr.has_method("play_portal_open"):
				audio_mgr.play_portal_open()
			var msg := "🎉 SECTOR COMPLETE! 🌀 EXTRACTION PORTAL UNLOCKED! (GO TO PORTAL BEACON)"
			alliance_announced.emit(msg, true)
		else:
			# Fallback if arena doesn't have a portal
			is_battle_over = true
			if is_inside_tree() and get_tree():
				await get_tree().create_timer(3.0).timeout
				if not next_sector_scene.is_empty():
					get_tree().change_scene_to_file(next_sector_scene)
				else:
					battle_ended.emit(true, winner_str)
	else:
		# Bot reached quota before player -> defeat!
		is_battle_over = true
		battle_ended.emit(false, winner_str)

func on_portal_reached() -> void:
	if not portal_active or is_battle_over:
		return
	is_battle_over = true
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio and audio.has_method("play_victory"):
		audio.play_victory()
		
	if not next_sector_scene.is_empty():
		get_tree().call_deferred("change_scene_to_file", next_sector_scene)
	else:
		battle_ended.emit(true, "Unit-07")
