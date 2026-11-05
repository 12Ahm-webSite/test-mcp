extends CanvasLayer

# --- HUD Top Bar ---
@onready var sector_label: Label = $HUD/TopBar/Margin/HBox/SectorLabel
@onready var energy_label: Label = $HUD/TopBar/Margin/HBox/VBoxEnergy/EnergyLabel
@onready var energy_bar: ProgressBar = $HUD/TopBar/Margin/HBox/VBoxEnergy/EnergyBar
@onready var score_label: Label = $HUD/TopBar/Margin/HBox/ScoreLabel
@onready var timer_label: Label = $HUD/TopBar/Margin/HBox/TimerLabel

# --- HUD Player Status & Threat ---
@onready var health_bar: ProgressBar = $HUD/BottomLeft/HealthContainer/HealthBar if has_node("HUD/BottomLeft/HealthContainer/HealthBar") else null
@onready var health_label: Label = $HUD/BottomLeft/HealthContainer/HealthLabel if has_node("HUD/BottomLeft/HealthContainer/HealthLabel") else null
@onready var dash_bar: ProgressBar = $HUD/BottomLeft/DashContainer/DashBar
@onready var dash_label: Label = $HUD/BottomLeft/DashContainer/DashLabel
@onready var buff_speed_badge: PanelContainer = $HUD/BottomLeft/BuffsContainer/SpeedBadge
@onready var buff_speed_label: Label = $HUD/BottomLeft/BuffsContainer/SpeedBadge/Label
@onready var buff_shield_badge: PanelContainer = $HUD/BottomLeft/BuffsContainer/ShieldBadge
@onready var buff_shield_label: Label = $HUD/BottomLeft/BuffsContainer/ShieldBadge/Label
@onready var compass_container: PanelContainer = $HUD/TopCenter/VBox/CompassContainer if has_node("HUD/TopCenter/VBox/CompassContainer") else null
@onready var compass_label: Label = $HUD/TopCenter/VBox/CompassContainer/CompassLabel if has_node("HUD/TopCenter/VBox/CompassContainer/CompassLabel") else null
@onready var threat_container: PanelContainer = $HUD/TopCenter/VBox/ThreatContainer if has_node("HUD/TopCenter/VBox/ThreatContainer") else get_node_or_null("HUD/TopCenter/ThreatContainer")
@onready var threat_label: Label = $HUD/TopCenter/VBox/ThreatContainer/ThreatLabel if has_node("HUD/TopCenter/VBox/ThreatContainer/ThreatLabel") else get_node_or_null("HUD/TopCenter/ThreatContainer/ThreatLabel")

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
	if btn_next_level and not btn_next_level.pressed.is_connected(_on_next_level_pressed):
		btn_next_level.pressed.connect(_on_next_level_pressed)
	if btn_replay_level and not btn_replay_level.pressed.is_connected(_on_replay_pressed):
		btn_replay_level.pressed.connect(_on_replay_pressed)
	if btn_retry and not btn_retry.pressed.is_connected(_on_replay_pressed):
		btn_retry.pressed.connect(_on_replay_pressed)
	if btn_main_menu_over and not btn_main_menu_over.pressed.is_connected(_on_main_menu_pressed):
		btn_main_menu_over.pressed.connect(_on_main_menu_pressed)
	if btn_victory_menu and not btn_victory_menu.pressed.is_connected(_on_main_menu_pressed):
		btn_victory_menu.pressed.connect(_on_main_menu_pressed)
	if btn_resume and not btn_resume.pressed.is_connected(_toggle_pause):
		btn_resume.pressed.connect(_toggle_pause)
	if btn_pause_restart and not btn_pause_restart.pressed.is_connected(_on_replay_pressed):
		btn_pause_restart.pressed.connect(_on_replay_pressed)
	if btn_pause_menu and not btn_pause_menu.pressed.is_connected(_on_main_menu_pressed):
		btn_pause_menu.pressed.connect(_on_main_menu_pressed)
	
	call_deferred("_setup_connections")

func _setup_connections() -> void:
	var tree := get_tree() if is_inside_tree() else null
	_gm = tree.get_first_node_in_group("game_manager") if tree else null
	if _gm:
		if _gm.has_signal("energy_updated") and not _gm.energy_updated.is_connected(_on_energy_updated):
			_gm.energy_updated.connect(_on_energy_updated)
		if _gm.has_signal("score_updated") and not _gm.score_updated.is_connected(_on_score_updated):
			_gm.score_updated.connect(_on_score_updated)
		if _gm.has_signal("toast_announced") and not _gm.toast_announced.is_connected(show_toast):
			_gm.toast_announced.connect(show_toast)
		if _gm.has_signal("level_completed") and not _gm.level_completed.is_connected(_on_level_completed):
			_gm.level_completed.connect(_on_level_completed)
		if _gm.has_signal("game_ended") and not _gm.game_ended.is_connected(_on_game_ended):
			_gm.game_ended.connect(_on_game_ended)
			
		sector_label.text = _gm.level_title.to_upper()
		_on_energy_updated(_gm.collected_energy_crystals, _gm.required_energy_crystals)
		_on_score_updated(_gm.current_score)
		
	_player = tree.get_first_node_in_group("player") if tree else null
	if _player:
		if _player.has_signal("health_changed") and not _player.health_changed.is_connected(_on_health_changed):
			_player.health_changed.connect(_on_health_changed)
		if _player.has_signal("dash_cooldown_updated") and not _player.dash_cooldown_updated.is_connected(_on_dash_cooldown_updated):
			_player.dash_cooldown_updated.connect(_on_dash_cooldown_updated)
		if _player.has_signal("speed_boost_changed") and not _player.speed_boost_changed.is_connected(_on_speed_boost_changed):
			_player.speed_boost_changed.connect(_on_speed_boost_changed)
		if _player.has_signal("shield_changed") and not _player.shield_changed.is_connected(_on_shield_changed):
			_player.shield_changed.connect(_on_shield_changed)
			
		# Sync initial health
		_on_health_changed(_player.health, _player.max_health)
			
	_enemy = tree.get_first_node_in_group("enemy") if tree else null

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
		
	# Update Crystal Radar Compass
	_update_crystal_compass()
		
	# Update Threat meter based on Enemy proximity
	var closest_enemy: Node3D = null
	var min_threat_dist: float = 999.0
	var tree := get_tree() if is_inside_tree() else null
	if is_instance_valid(_player) and tree:
		var enemies: Array[Node] = tree.get_nodes_in_group("enemy")
		for e in enemies:
			if is_instance_valid(e) and "is_active" in e and e.is_active:
				var enemy_node := e as Node3D
				if enemy_node:
					var d: float = _player.global_position.distance_to(enemy_node.global_position)
					if d < min_threat_dist:
						min_threat_dist = d
						closest_enemy = enemy_node

	if is_instance_valid(closest_enemy) and threat_container and threat_label:
		var enemy_title: String = closest_enemy.get("character_name") if "character_name" in closest_enemy else "SENTINEL"
		var is_chasing: bool = ("current_state" in closest_enemy and (closest_enemy.current_state == 1 or closest_enemy.current_state == 2))
		if min_threat_dist < 26.0 or is_chasing:
			threat_container.visible = true
			if min_threat_dist < 12.0 or is_chasing:
				threat_label.text = "⚠️ THREAT CRITICAL: %s ENGAGED! [%.1fm]" % [enemy_title.to_upper(), min_threat_dist]
				threat_container.modulate = Color(1.0, 0.2, 0.2, 1.0)
			else:
				threat_label.text = "👁️ PROXIMITY ALERT: %s PATROLLING [%.1fm]" % [enemy_title.to_upper(), min_threat_dist]
				threat_container.modulate = Color(1.0, 0.8, 0.2, 0.9)
		else:
			threat_container.visible = false
	elif threat_container:
		threat_container.visible = false

func _update_crystal_compass() -> void:
	if not compass_container:
		compass_container = get_node_or_null("HUD/TopCenter/VBox/CompassContainer")
	if not compass_label:
		compass_label = get_node_or_null("HUD/TopCenter/VBox/CompassContainer/CompassLabel")
	if not compass_container or not compass_label:
		return

	var tree := get_tree() if is_inside_tree() else null
	if not tree and _player and is_instance_valid(_player) and _player.is_inside_tree():
		tree = _player.get_tree()
	if not tree:
		var ml = Engine.get_main_loop()
		if ml is SceneTree:
			tree = ml as SceneTree
	if not tree:
		return

	var crystals = tree.get_nodes_in_group("crystals")
	var active_crystals: Array[Node3D] = []
	for c in crystals:
		if c is Node3D and not ("_is_collected" in c and c._is_collected):
			active_crystals.append(c)

	if active_crystals.is_empty():
		var parent = get_parent()
		var c_container = parent.find_child("Crystals", true, false) if parent else null
		if c_container:
			for c in c_container.get_children():
				if c is Node3D and not ("_is_collected" in c and c._is_collected):
					active_crystals.append(c)

	var p = _player
	if not p or not is_instance_valid(p):
		p = tree.get_first_node_in_group("player")
	if not p or not is_instance_valid(p):
		var parent = get_parent()
		if parent:
			p = parent.find_child("Player", true, false)

	if active_crystals.is_empty():
		compass_label.text = "🧭 ✨ ALL CRYSTALS COLLECTED! PORTAL OPEN"
		compass_label.modulate = Color(0.3, 1.0, 0.6)
		return

	if not p or not is_instance_valid(p):
		compass_container.visible = false
		return

	compass_container.visible = true
	var p_pos: Vector3 = p.global_position if p.is_inside_tree() else p.position

	# Find closest crystal
	var closest: Node3D = null
	var min_dist: float = 99999.0
	for c in active_crystals:
		var c_pos: Vector3 = c.global_position if c.is_inside_tree() else c.position
		var d = p_pos.distance_to(c_pos)
		if d < min_dist:
			min_dist = d
			closest = c

	if not closest:
		return

	# Determine forward heading from camera or player
	var forward := Vector3.FORWARD
	var vp = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam and cam.is_inside_tree():
		forward = -cam.global_transform.basis.z
	elif p.is_inside_tree():
		forward = -p.global_transform.basis.z
	elif p.transform.basis != Basis():
		forward = -p.transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var closest_pos: Vector3 = closest.global_position if closest.is_inside_tree() else closest.position
	var to_c := closest_pos - p_pos
	to_c.y = 0.0
	if to_c.length_squared() > 0.001:
		to_c = to_c.normalized()
	else:
		to_c = forward

	var dot := clampf(forward.dot(to_c), -1.0, 1.0)
	var cross_y := forward.cross(to_c).y
	var angle_deg := rad_to_deg(atan2(cross_y, dot))

	var dist_m := int(min_dist)
	var bar := ""
	if absf(angle_deg) <= 15.0:
		bar = "🧭 [  •  •  ◆  •  •  ] %dm (AHEAD)" % dist_m
		compass_label.modulate = Color(0.2, 1.0, 0.8)
	elif angle_deg > 15.0 and angle_deg <= 50.0:
		bar = "🧭 [  •  •  •  ◆  •  ] ➔ %dm" % dist_m
		compass_label.modulate = Color(0.3, 0.9, 1.0)
	elif angle_deg > 50.0 and angle_deg <= 110.0:
		bar = "🧭 [  •  •  •  •  ◆  ] ▶ %dm (RIGHT)" % dist_m
		compass_label.modulate = Color(0.4, 0.85, 1.0)
	elif angle_deg > 110.0:
		bar = "🧭 ▼ [ BEHIND RIGHT ] %dm" % dist_m
		compass_label.modulate = Color(0.6, 0.75, 1.0)
	elif angle_deg < -15.0 and angle_deg >= -50.0:
		bar = "🧭 ⬅ [  •  ◆  •  •  •  ] %dm" % dist_m
		compass_label.modulate = Color(0.3, 0.9, 1.0)
	elif angle_deg < -50.0 and angle_deg >= -110.0:
		bar = "🧭 (LEFT) ◀ [  ◆  •  •  •  •  ] %dm" % dist_m
		compass_label.modulate = Color(0.4, 0.85, 1.0)
	else:
		bar = "🧭 ▼ [ BEHIND LEFT ] %dm" % dist_m
		compass_label.modulate = Color(0.6, 0.75, 1.0)

	compass_label.text = bar

func _on_energy_updated(current: int, required: int) -> void:
	if energy_bar:
		energy_bar.max_value = required
		energy_bar.value = current
	if energy_label:
		energy_label.text = "CHRONO ENERGY: %d / %d" % [current, required]

func _on_score_updated(score: int) -> void:
	if score_label:
		score_label.text = "SCORE: %05d" % score

func _on_health_changed(current: float, max_hp: float) -> void:
	if not health_bar:
		health_bar = get_node_or_null("HUD/BottomLeft/HealthContainer/HealthBar")
	if not health_label:
		health_label = get_node_or_null("HUD/BottomLeft/HealthContainer/HealthLabel")
		
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current
		if current <= max_hp * 0.25:
			health_bar.modulate = Color(1.0, 0.25, 0.25)
		elif current <= max_hp * 0.5:
			health_bar.modulate = Color(1.0, 0.75, 0.2)
		else:
			health_bar.modulate = Color(1.0, 1.0, 1.0)
	if health_label:
		health_label.text = "HEALTH: %d / %d HP" % [int(current), int(max_hp)]

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
