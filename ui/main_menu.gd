extends Control

@onready var play_button: Button = $CenterContainer/MainPanel/VBox/BtnPlay
@onready var battle_button: Button = $CenterContainer/MainPanel/VBox/BtnBattle
@onready var level_select_button: Button = $CenterContainer/MainPanel/VBox/BtnLevelSelect
@onready var controls_button: Button = $CenterContainer/MainPanel/VBox/BtnControls
@onready var quit_button: Button = $CenterContainer/MainPanel/VBox/BtnQuit

@onready var level_panel: Control = $CenterContainer/LevelSelectPanel
@onready var btn_level_1: Button = $CenterContainer/LevelSelectPanel/VBox/Grid/BtnLevel1
@onready var btn_level_2: Button = $CenterContainer/LevelSelectPanel/VBox/Grid/BtnLevel2
@onready var btn_level_3: Button = $CenterContainer/LevelSelectPanel/VBox/Grid/BtnLevel3
@onready var lbl_stats_1: Label = $CenterContainer/LevelSelectPanel/VBox/Grid/Stats1
@onready var lbl_stats_2: Label = $CenterContainer/LevelSelectPanel/VBox/Grid/Stats2
@onready var lbl_stats_3: Label = $CenterContainer/LevelSelectPanel/VBox/Grid/Stats3
@onready var btn_back_levels: Button = $CenterContainer/LevelSelectPanel/VBox/BtnBack

@onready var controls_panel: Control = $CenterContainer/ControlsPanel
@onready var btn_back_controls: Button = $CenterContainer/ControlsPanel/VBox/BtnBack
@onready var slider_sensitivity: HSlider = $CenterContainer/ControlsPanel/VBox/HBoxSens/SensitivitySlider
@onready var lbl_sens_val: Label = $CenterContainer/ControlsPanel/VBox/HBoxSens/SensValLabel

var _save_mgr: Node = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	_save_mgr = preload("res://scripts/save_manager.gd").new()
	add_child(_save_mgr)
	
	level_panel.visible = false
	controls_panel.visible = false
	
	play_button.pressed.connect(_on_play_pressed)
	if battle_button:
		battle_button.pressed.connect(_on_battle_pressed)
	level_select_button.pressed.connect(_show_level_select)
	controls_button.pressed.connect(_show_controls)
	quit_button.pressed.connect(_on_quit_pressed)
	
	btn_level_1.pressed.connect(func(): _load_level("res://scenes/levels/level_1_ruins.tscn"))
	btn_level_2.pressed.connect(func(): _load_level("res://scenes/levels/level_2_canyon.tscn"))
	btn_level_3.pressed.connect(func(): _load_level("res://scenes/levels/level_3_caverns.tscn"))
	btn_back_levels.pressed.connect(_show_main_menu)
	btn_back_controls.pressed.connect(_show_main_menu)
	
	if slider_sensitivity:
		slider_sensitivity.value_changed.connect(_on_sensitivity_changed)
		var current_sens: float = _save_mgr.get_setting("mouse_sensitivity", 0.003)
		slider_sensitivity.value = current_sens * 1000.0
		lbl_sens_val.text = "%.1f" % slider_sensitivity.value
		
	_refresh_level_buttons()
	play_button.grab_focus()

func _refresh_level_buttons() -> void:
	if not _save_mgr:
		return
		
	if _save_mgr.unlocked_levels > 1:
		play_button.text = "CONTINUE (SECTOR %d)" % mini(_save_mgr.unlocked_levels, 3)
	else:
		play_button.text = "START EXPEDITION"
		
	# Level 1 always unlocked
	btn_level_1.disabled = false
	var hs1: int = _save_mgr.get_high_score("level_1")
	var bt1: float = _save_mgr.get_best_time("level_1")
	lbl_stats_1.text = "Best: %d PTS | Time: %s" % [hs1, _format_time(bt1)]
	
	# Level 2 unlocked if level_1 completed
	var unlocked_2: bool = _save_mgr.is_level_unlocked("level_2")
	btn_level_2.disabled = not unlocked_2
	if unlocked_2:
		var hs2: int = _save_mgr.get_high_score("level_2")
		var bt2: float = _save_mgr.get_best_time("level_2")
		lbl_stats_2.text = "Best: %d PTS | Time: %s" % [hs2, _format_time(bt2)]
	else:
		lbl_stats_2.text = "🔒 Locked - Clear Sector 1"
		
	# Level 3 unlocked if level_2 completed
	var unlocked_3: bool = _save_mgr.is_level_unlocked("level_3")
	btn_level_3.disabled = not unlocked_3
	if unlocked_3:
		var hs3: int = _save_mgr.get_high_score("level_3")
		var bt3: float = _save_mgr.get_best_time("level_3")
		lbl_stats_3.text = "Best: %d PTS | Time: %s" % [hs3, _format_time(bt3)]
	else:
		lbl_stats_3.text = "🔒 Locked - Clear Sector 2"

func _format_time(t: float) -> String:
	if t <= 0.0 or t >= 999999.0:
		return "--:--"
	var mins: int = int(t / 60.0)
	var secs: float = fmod(t, 60.0)
	return "%02d:%04.1f" % [mins, secs]

func _on_play_pressed() -> void:
	# Start at latest unlocked level or level 1
	if _save_mgr and _save_mgr.is_level_unlocked("level_3"):
		_load_level("res://scenes/levels/level_3_caverns.tscn")
	elif _save_mgr and _save_mgr.is_level_unlocked("level_2"):
		_load_level("res://scenes/levels/level_2_canyon.tscn")
	else:
		_load_level("res://scenes/levels/level_1_ruins.tscn")

func _on_battle_pressed() -> void:
	_load_level("res://scenes/levels/battle_1_ruins.tscn")

func _load_level(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _show_level_select() -> void:
	$CenterContainer/MainPanel.visible = false
	controls_panel.visible = false
	level_panel.visible = true
	_refresh_level_buttons()
	btn_back_levels.grab_focus()

func _show_controls() -> void:
	$CenterContainer/MainPanel.visible = false
	level_panel.visible = false
	controls_panel.visible = true
	btn_back_controls.grab_focus()

func _show_main_menu() -> void:
	level_panel.visible = false
	controls_panel.visible = false
	$CenterContainer/MainPanel.visible = true
	play_button.grab_focus()

func _on_sensitivity_changed(value: float) -> void:
	var sens: float = value / 1000.0
	lbl_sens_val.text = "%.1f" % value
	if _save_mgr:
		_save_mgr.set_setting("mouse_sensitivity", sens)

func _on_quit_pressed() -> void:
	get_tree().quit()
