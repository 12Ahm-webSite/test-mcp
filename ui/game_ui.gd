extends CanvasLayer

# --- HUD Top Bar ---
@onready var sector_label: Label = $HUD/TopBar/Margin/HBox/SectorLabel
@onready var energy_label: Label = $HUD/TopBar/Margin/HBox/VBoxEnergy/EnergyLabel
@onready var energy_bar: ProgressBar = $HUD/TopBar/Margin/HBox/VBoxEnergy/EnergyBar
@onready var score_label: Label = $HUD/TopBar/Margin/HBox/ScoreLabel
@onready var timer_label: Label = $HUD/TopBar/Margin/HBox/TimerLabel

# --- HUD Abilities & Threat ---
@onready var dash_bar: ProgressBar = $HUD/BottomLeft/DashContainer/DashBar
@onready var dash_label: Label = $HUD/BottomLeft/DashContainer/DashLabel
@onready var buff_speed_badge: PanelContainer = $HUD/BottomLeft/BuffsContainer/SpeedBadge
@onready var buff_speed_label: Label = $HUD/BottomLeft/BuffsContainer/SpeedBadge/Label
@onready var buff_shield_badge: PanelContainer = $HUD/BottomLeft/BuffsContainer/ShieldBadge
@onready var buff_shield_label: Label = $HUD/BottomLeft/BuffsContainer/ShieldBadge/Label
@onready var threat_container: PanelContainer = $HUD/TopCenter/ThreatContainer
@onready var threat_label: Label = $HUD/TopCenter/ThreatContainer/ThreatLabel

# --- Toast Banner ---
@onready var toast_panel: PanelContainer = $HUD/CenterNotice/ToastPanel
@onready var toast_label: Label = $HUD/CenterNotice/ToastPanel/ToastLabel

# --- Menus and Modals ---
@onready var level_clear_panel: Control = $Modals/LevelClearPanel
@onready var level_clear_title: Label = $Modals/LevelClearPanel/Panel/VBox/TitleLabel
@onready var level_clear_stats: Label = $Modals/LevelClearPanel/Panel/VBox/StatsLabel
@onready var btn_next_level: Button = $Modals/LevelClearPanel/Panel/VBox/HBox/BtnNextLevel
@onready var btn_replay_level: Button = $Modals/LevelClearPanel/Panel/VBox/HBox/BtnReplayLevel

@onready var game_over_panel: Control = $Modals/GameOverPanel
@onready var btn_retry: Button = $Modals/GameOverPanel/Panel/VBox/HBox/BtnRetry
@onready var btn_main_menu_over: Button = $Modals/GameOverPanel/Panel/VBox/HBox/BtnMainMenu

@onready var victory_panel: Control = $Modals/VictoryPanel
@onready var victory_stats: Label = $Modals/VictoryPanel/Panel/VBox/StatsLabel
@onready var btn_victory_menu: Button = $Modals/VictoryPanel/Panel/VBox/BtnMainMenu

@onready var pause_panel: Control = $Modals/PausePanel
@onready var btn_resume: Button = $Modals/PausePanel/Panel/VBox/BtnResume
@onready var btn_pause_restart: Button = $Modals/PausePanel/Panel/VBox/BtnRestart
@onready var btn_pause_menu: Button = $Modals/PausePanel/Panel/VBox/BtnMainMenu

var _gm: Node = null
var _player: Node3D = null
var _enemy: Node3D = null
var _toast_tween: Tween = null
var _is_paused: bool = false

func _ready() -> void:
	# Hide modals initially
	level_clear_panel.visible = false
	game_over_panel.visible = false
	victory_panel.visible = false
	pause_panel.visible = false
	toast_panel.modulate.a = 0.0
	
	buff_speed_badge.visible = false
	buff_shield_badge.visible = false
	threat_container.visible = false
	
	# Connect buttons
	btn_next_level.pressed.connect(_on_next_level_pressed)
	btn_replay_level.pressed.connect(_on_replay_pressed)
	btn_retry.pressed.connect(_on_replay_pressed)
	btn_main_menu_over.pressed.connect(_on_main_menu_pressed)
	btn_victory_menu.pressed.connect(_on_main_menu_pressed)
	btn_resume.pressed.connect(_toggle_pause)
	btn_pause_restart.pressed.connect(_on_replay_pressed)
	btn_pause_menu.pressed.connect(_on_main_menu_pressed)
	
	call_deferred("_setup_connections")

func _setup_connections() -> void:
	_gm = get_tree().get_first_node_in_group("game_manager")
	if _gm:
		if _gm.has_signal("energy_updated"):
			_gm.energy_updated.connect(_on_energy_updated)
		if _gm.has_signal("score_updated"):
			_gm.score_updated.connect(_on_score_updated)
		if _gm.has_signal("toast_announced"):
			_gm.toast_announced.connect(show_toast)
		if _gm.has_signal("level_completed"):
			_gm.level_completed.connect(_on_level_completed)
		if _gm.has_signal("game_ended"):
			_gm.game_ended.connect(_on_game_ended)
			
		sector_label.text = _gm.level_title.to_upper()
		_on_energy_updated(_gm.collected_energy_crystals, _gm.required_energy_crystals)
		_on_score_updated(_gm.current_score)
		
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		if _player.has_signal("dash_cooldown_updated"):
			_player.dash_cooldown_updated.connect(_on_dash_cooldown_updated)
		if _player.has_signal("speed_boost_changed"):
			_player.speed_boost_changed.connect(_on_speed_boost_changed)
		if _player.has_signal("shield_changed"):
			_player.shield_changed.connect(_on_shield_changed)
			
	_enemy = get_tree().get_first_node_in_group("enemy")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not level_clear_panel.visible and not game_over_panel.visible and not victory_panel.visible:
			_toggle_pause()

func _process(_delta: float) -> void:
	# Update timer from GM
	if _gm and not _gm.is_game_over:
		var mins: int = int(_gm.elapsed_time / 60.0)
		var secs: float = fmod(_gm.elapsed_time, 60.0)
		timer_label.text = "%02d:%04.1f" % [mins, secs]
		
	# Update Threat meter based on Enemy proximity
	if is_instance_valid(_player) and is_instance_valid(_enemy) and _enemy.is_active:
		var dist: float = _player.global_position.distance_to(_enemy.global_position)
		if dist < 26.0 or ("current_state" in _enemy and _enemy.current_state == 1): # 1 is CHASE
			threat_container.visible = true
			if dist < 12.0 or ("current_state" in _enemy and _enemy.current_state == 1):
				threat_label.text = "⚠️ THREAT CRITICAL: SENTINEL ENGAGED! [%.1fm]" % dist
				threat_container.modulate = Color(1.0, 0.2, 0.2, 1.0)
			else:
				threat_label.text = "👁️ PROXIMITY ALERT: SENTINEL PATROLLING [%.1fm]" % dist
				threat_container.modulate = Color(1.0, 0.8, 0.2, 0.9)
		else:
			threat_container.visible = false
	else:
		threat_container.visible = false

func _on_energy_updated(current: int, required: int) -> void:
	if energy_bar:
		energy_bar.max_value = required
		energy_bar.value = current
	if energy_label:
		energy_label.text = "CHRONO ENERGY: %d / %d" % [current, required]

func _on_score_updated(score: int) -> void:
	if score_label:
		score_label.text = "SCORE: %05d" % score

func _on_dash_cooldown_updated(current: float, max_cd: float) -> void:
	if not dash_bar:
		return
	if current <= 0.001:
		dash_bar.value = 1.0
		dash_label.text = "DASH: READY [Q/E]"
		dash_bar.modulate = Color(0.2, 1.0, 0.7)
	else:
		dash_bar.value = 1.0 - (current / max_cd)
		dash_label.text = "DASH: %.1fs" % current
		dash_bar.modulate = Color(0.6, 0.6, 0.6)

func _on_speed_boost_changed(active: bool, duration: float) -> void:
	if buff_speed_badge:
		buff_speed_badge.visible = active
		if active:
			buff_speed_label.text = "⚡ OVERDRIVE (%.1fs)" % duration

func _on_shield_changed(active: bool, duration: float) -> void:
	if buff_shield_badge:
		buff_shield_badge.visible = active
		if active:
			buff_shield_label.text = "🛡️ SHIELD (%.1fs)" % duration

func show_toast(msg: String) -> void:
	if not toast_label or not toast_panel:
		return
	toast_label.text = msg
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
		
	_toast_tween = create_tween()
	toast_panel.modulate.a = 0.0
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.5)

func _on_level_completed(lvl_name: String, time_taken: float, final_score: int, is_final: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_final:
		victory_panel.visible = true
		var mins: int = int(time_taken / 60.0)
		var secs: float = fmod(time_taken, 60.0)
		victory_stats.text = "ALL SECTORS SECURED!\n\nTotal Time: %02d:%04.1f\nFinal Score: %d PTS" % [mins, secs, final_score]
		btn_victory_menu.grab_focus()
	else:
		level_clear_panel.visible = true
		level_clear_title.text = "%s CLEARED!" % lvl_name.to_upper()
		var mins: int = int(time_taken / 60.0)
		var secs: float = fmod(time_taken, 60.0)
		level_clear_stats.text = "Extraction Successful\nTime: %02d:%04.1f\nScore: %d PTS" % [mins, secs, final_score]
		btn_next_level.grab_focus()

func _on_game_ended(won: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not won:
		game_over_panel.visible = true
		btn_retry.grab_focus()

func _toggle_pause() -> void:
	_is_paused = not _is_paused
	pause_panel.visible = _is_paused
	get_tree().paused = _is_paused
	if _is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		btn_resume.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_next_level_pressed() -> void:
	if _gm:
		_gm.go_to_next_level()

func _on_replay_pressed() -> void:
	get_tree().paused = false
	if _gm:
		_gm.restart_current_level()

func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
