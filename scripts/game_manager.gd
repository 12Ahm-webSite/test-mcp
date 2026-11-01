extends Node

signal energy_updated(current: int, required: int)
signal score_updated(score: int)
signal toast_announced(message: String)
signal level_completed(level_name: String, time_taken: float, score: int, is_final_level: bool)
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
	add_to_group("game_manager")
	add_child(save_mgr)
	add_child(audio_mgr)
	call_deferred("_init_level")

func _init_level() -> void:
	energy_updated.emit(collected_energy_crystals, required_energy_crystals)
	score_updated.emit(current_score)
	toast_announced.emit("Objective: Collect %d Energy Crystals!" % required_energy_crystals)
	if audio_mgr and audio_mgr.has_method("play_bgm_for_level"):
		audio_mgr.play_bgm_for_level(level_id)

func _process(delta: float) -> void:
	if not is_game_over:
		elapsed_time += delta

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

func on_portal_reached() -> void:
	if is_game_over or not is_portal_active:
		return
	is_game_over = true
	
	if audio_mgr and audio_mgr.has_method("duck_bgm"):
		audio_mgr.duck_bgm()
	
	# Stop entities
	_freeze_actors()
	
	# Save progress
	if save_mgr:
		save_mgr.register_level_completion(level_id, current_score, elapsed_time)
		
	var is_final := (next_level_scene == "")
	level_completed.emit(level_title, elapsed_time, current_score, is_final)
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
