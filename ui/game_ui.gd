extends CanvasLayer

@onready var score_label: Label = $HUD/MarginContainer/PanelContainer/VBoxContainer/ScoreLabel
@onready var hint_label: Label = $HUD/MarginContainer/PanelContainer/VBoxContainer/HintLabel
@onready var win_panel: Control = $EndScreen/WinPanel
@onready var lose_panel: Control = $EndScreen/LosePanel
@onready var restart_win_button: Button = $EndScreen/WinPanel/VBoxContainer/RestartButton
@onready var restart_lose_button: Button = $EndScreen/LosePanel/VBoxContainer/RestartButton

func _ready() -> void:
    win_panel.visible = false
    lose_panel.visible = false
    restart_win_button.pressed.connect(_on_restart_pressed)
    restart_lose_button.pressed.connect(_on_restart_pressed)
    
    call_deferred("_connect_game_manager")

func _connect_game_manager() -> void:
    var gm = get_tree().get_first_node_in_group("game_manager")
    if gm:
        gm.score_changed.connect(_on_score_changed)
        gm.game_ended.connect(_on_game_ended)
        _on_score_changed(gm.collected_crystals, gm.max_crystals)

func _on_score_changed(current: int, total: int) -> void:
    if score_label:
        score_label.text = "💎 Crystals: %d / %d" % [current, total]

func _on_game_ended(won: bool) -> void:
    if won:
        win_panel.visible = true
        lose_panel.visible = false
        restart_win_button.grab_focus()
    else:
        lose_panel.visible = true
        win_panel.visible = false
        restart_lose_button.grab_focus()

func _on_restart_pressed() -> void:
    get_tree().reload_current_scene()
