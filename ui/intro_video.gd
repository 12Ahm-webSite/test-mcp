extends Control

@export var next_scene_path: String = "res://ui/main_menu.tscn"
@export var fade_duration: float = 0.35

@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var skip_label: Label = $SkipLabel if has_node("SkipLabel") else null
@onready var fade_rect: ColorRect = $FadeRect if has_node("FadeRect") else null

var _is_transitioning: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if fade_rect:
		fade_rect.visible = true
		fade_rect.modulate.a = 1.0
		var t := create_tween()
		t.tween_property(fade_rect, "modulate:a", 0.0, 0.4)
		
	if video_player:
		video_player.finished.connect(_on_video_finished)
		call_deferred("_start_video")
	else:
		_transition_to_menu()
		
	if skip_label:
		skip_label.modulate.a = 0.0
		var t_skip := create_tween()
		t_skip.tween_interval(1.2)
		t_skip.tween_property(skip_label, "modulate:a", 0.75, 0.6)

func _start_video() -> void:
	if video_player and not _is_transitioning:
		video_player.play()

func _input(event: InputEvent) -> void:
	if _is_transitioning:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_transition_to_menu()
	elif event is InputEventMouseButton and event.pressed:
		_transition_to_menu()
	elif event is InputEventScreenTouch and event.pressed:
		_transition_to_menu()

func _on_video_finished() -> void:
	_transition_to_menu()

func _transition_to_menu() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	
	if video_player and video_player.is_playing():
		video_player.stop()
		
	if fade_rect:
		var t := create_tween()
		t.tween_property(fade_rect, "modulate:a", 1.0, fade_duration)
		t.tween_callback(func():
			get_tree().change_scene_to_file(next_scene_path)
		)
	else:
		get_tree().change_scene_to_file(next_scene_path)
