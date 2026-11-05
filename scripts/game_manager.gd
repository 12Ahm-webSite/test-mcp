extends Node

signal energy_updated(current: int, required: int)
signal score_updated(score: int)
signal toast_announced(message: String)
signal level_completed(level_name: String, time_taken: float, score: int, is_final_level: bool, rank_data: Dictionary)
signal game_ended(won: bool)

@export var level_id: String = "level_1"
@export var level_title: String = "The Sunken Ruins"
@export var required_energy_crystals: int = 10
@export var next_level_scene: String = "res://scenes/levels/level_2_canyon.tscn"

var collected_energy_crystals: int = 0
var current_score: int = 0
var elapsed_time: float = 0.0
var is_game_over: bool = false
var is_portal_active: bool = false

@onready var save_mgr: Node = preload("res://scripts/save_manager.gd").new()
@onready var audio_mgr: Node = preload("res://scripts/audio_manager.gd").new()

func _ready() -> void:
	Engine.time_scale = 1.0
	add_to_group("game_manager")
	add_child(save_mgr)
	add_child(audio_mgr)
	call_deferred("_init_level")

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _init_level() -> void:
	energy_updated.emit(collected_energy_crystals, required_energy_crystals)
	score_updated.emit(current_score)
	toast_announced.emit("Objective: Collect %d Energy Crystals!" % required_energy_crystals)
	if audio_mgr and audio_mgr.has_method("play_bgm_for_level"):
		audio_mgr.play_bgm_for_level(level_id)

func _process(delta: float) -> void:
	if not is_game_over:
		elapsed_time += delta

func add_score(amount: int) -> void:
	if is_game_over:
		return
	current_score += amount
	score_updated.emit(current_score)

func collect_crystal(crystal_type: int, score: int) -> void:
	if is_game_over:
		return
		
	current_score += score
	score_updated.emit(current_score)
	
	if audio_mgr and audio_mgr.has_method("play_crystal"):
		audio_mgr.play_crystal(crystal_type)
	
	# Every crystal collected increments the stage objective!
	collected_energy_crystals += 1
	energy_updated.emit(collected_energy_crystals, required_energy_crystals)
	
	if collected_energy_crystals >= required_energy_crystals and not is_portal_active:
		_activate_portal()
	
	match crystal_type:
		0: # ENERGY
			pass
		1: # SPEED
			toast_announced.emit("⚡ Overdrive Activated! +Speed (+1 Energy)")
		2: # SHIELD
			toast_announced.emit("🛡️ Energy Barrier Online! +Shield (+1 Energy)")
		3: # RARE
			toast_announced.emit("💎 Rare Chrono-Relic! +500 PTS (+1 Energy)")

func _activate_portal() -> void:
	is_portal_active = true
	if audio_mgr and audio_mgr.has_method("play_portal"):
		audio_mgr.play_portal()
	var portal = get_tree().get_first_node_in_group("portal")
	if not portal:
		portal = get_node_or_null("Portal")
	if portal and portal.has_method("activate"):
		portal.activate()
	toast_announced.emit("🌀 PORTAL ACTIVATED! Reach the extraction gate!")

const LEVEL_PAR_TIMES := {
	"level_1": 75.0,
	"level_2": 95.0,
	"level_3": 120.0
}

func calculate_rank(time_taken: float, score: int, health_val: float = 100.0, max_health_val: float = 100.0) -> Dictionary:
	var par_time: float = float(LEVEL_PAR_TIMES.get(level_id, 90.0))
	var time_ratio: float = time_taken / maxf(par_time, 1.0)
	var health_ratio: float = clampf(health_val / maxf(max_health_val, 1.0), 0.0, 1.0)
	var is_flawless: bool = health_ratio >= 0.99
	
	# Time Bonus: up to 1000 points if finished under par time
	var time_bonus: int = 0
	if time_ratio < 1.0:
		time_bonus = int((1.0 - time_ratio) * 1000.0)
	
	# Health Bonus: up to 500 points based on health remaining
	var health_bonus: int = int(health_ratio * 500.0)
	if is_flawless:
		health_bonus += 250 # Flawless extra bonus
		
	var total_score: int = score + time_bonus + health_bonus
	
	# Rank threshold calculation:
	var rank := "C"
	var title := "SURVIVOR"
	
	if (time_ratio <= 1.05 and health_ratio >= 0.75) or (is_flawless and time_ratio <= 1.35) or total_score >= 2200:
		rank = "S"
		title = "CHRONO MASTER" if not is_flawless else "FLAWLESS SPEEDRUNNER"
	elif (time_ratio <= 1.35 and health_ratio >= 0.50) or total_score >= 1600:
		rank = "A"
		title = "ELITE RECON"
	elif time_ratio <= 1.75 or health_ratio >= 0.25 or total_score >= 1000:
		rank = "B"
		title = "FIELD OPERATOR"
	else:
		rank = "C"
		title = "SURVIVOR"
		
	return {
		"rank": rank,
		"rank_title": title,
		"par_time": par_time,
		"time_bonus": time_bonus,
		"health_bonus": health_bonus,
		"base_score": score,
		"total_score": total_score,
		"is_flawless": is_flawless
	}

func on_portal_reached() -> void:
	if is_game_over or not is_portal_active:
		return
	is_game_over = true
	
	if audio_mgr and audio_mgr.has_method("duck_bgm"):
		audio_mgr.duck_bgm()
	
	# Stop entities
	_freeze_actors()
	
	# Determine player health
	var hp := 100.0
	var max_hp := 100.0
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if "health" in player:
			hp = float(player.health)
		if "max_health" in player:
			max_hp = float(player.max_health)
			
	var rank_data := calculate_rank(elapsed_time, current_score, hp, max_hp)
	var final_score: int = int(rank_data.get("total_score", current_score))
	var final_rank: String = str(rank_data.get("rank", "B"))
	
	# Save progress
	if save_mgr:
		save_mgr.register_level_completion(level_id, final_score, elapsed_time, final_rank)
		
	var is_final := (next_level_scene == "")
	level_completed.emit(level_title, elapsed_time, final_score, is_final, rank_data)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func trigger_game_over(won: bool) -> void:
	if is_game_over:
		return
	is_game_over = true
	if audio_mgr and audio_mgr.has_method("duck_bgm"):
		audio_mgr.duck_bgm()
	_freeze_actors()
	game_ended.emit(won)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _freeze_actors() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and "is_active" in player:
		player.is_active = false
	var enemy = get_tree().get_first_node_in_group("enemy")
	if enemy and "is_active" in enemy:
		enemy.is_active = false

func restart_current_level() -> void:
	get_tree().reload_current_scene()

func go_to_next_level() -> void:
	if next_level_scene != "":
		get_tree().change_scene_to_file(next_level_scene)
	else:
		# Return to main menu
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
