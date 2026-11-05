class_name MobileTouchControls
extends Control

@export var max_joystick_radius: float = 65.0
@export var force_show_for_testing: bool = false

var _player: Node3D = null
var _joystick_touch_id: int = -1
var _look_touch_id: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_default_pos: Vector2 = Vector2.ZERO

# Node references
@onready var joystick_base: Control = $JoystickContainer/BaseRing if has_node("JoystickContainer/BaseRing") else null
@onready var joystick_knob: Control = $JoystickContainer/BaseRing/Knob if has_node("JoystickContainer/BaseRing/Knob") else null
@onready var btn_jump: Button = $ActionsContainer/BtnJump if has_node("ActionsContainer/BtnJump") else null
@onready var btn_dash: Button = $ActionsContainer/BtnDash if has_node("ActionsContainer/BtnDash") else null
@onready var btn_fire: Button = $ActionsContainer/BtnFire if has_node("ActionsContainer/BtnFire") else null
@onready var btn_aim: Button = $ActionsContainer/BtnAim if has_node("ActionsContainer/BtnAim") else null
@onready var btn_swap: Button = $ActionsContainer/BtnSwap if has_node("ActionsContainer/BtnSwap") else null
@onready var look_zone: Control = $LookZone if has_node("LookZone") else null

func _ready() -> void:
	_ensure_input_actions()
	var manual_touch := false
	var save_path := "user://crystal_rush_save.json"
	if FileAccess.file_exists(save_path):
		var file := FileAccess.open(save_path, FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and "settings" in parsed:
				manual_touch = bool(parsed["settings"].get("touch_controls_enabled", false))
			file.close()

	# Configure mobile visibility
	var is_mobile := OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()
	visible = is_mobile or manual_touch or force_show_for_testing
	
	if joystick_base:
		_joystick_default_pos = joystick_base.position
		_joystick_center = joystick_base.size * 0.5
	
	_find_player()
	_connect_action_buttons()

func _ensure_input_actions() -> void:
	var required_actions := ["jump", "dash", "shoot", "move_left", "move_right", "move_forward", "move_back", "sprint"]
	for a: String in required_actions:
		if not InputMap.has_action(a):
			InputMap.add_action(a)

func _find_player() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree:
		_player = tree.get_first_node_in_group("player")

func _connect_action_buttons() -> void:
	if btn_jump:
		btn_jump.button_down.connect(func(): Input.action_press("jump"))
		btn_jump.button_up.connect(func(): Input.action_release("jump"))
	
	if btn_dash:
		btn_dash.button_down.connect(func(): Input.action_press("dash"))
		btn_dash.button_up.connect(func(): Input.action_release("dash"))

	if btn_fire:
		btn_fire.button_down.connect(_on_fire_down)
		btn_fire.button_up.connect(_on_fire_up)

	if btn_aim:
		btn_aim.pressed.connect(_on_aim_toggle)

	if btn_swap:
		btn_swap.pressed.connect(_on_swap_weapon)

func _on_fire_down() -> void:
	if _player and _player.has_method("set_touch_fire"):
		_player.set_touch_fire(true)
	Input.action_press("shoot")

func _on_fire_up() -> void:
	if _player and _player.has_method("set_touch_fire"):
		_player.set_touch_fire(false)
	Input.action_release("shoot")

func _on_aim_toggle() -> void:
	if _player and _player.has_method("toggle_aim"):
		_player.toggle_aim()

func _on_swap_weapon() -> void:
	if _player and _player.has_method("cycle_weapon"):
		_player.cycle_weapon(1)

# ----------------------------------------------------
# MULTI-TOUCH INPUT PROCESSING (JOYSTICK & LOOK SWIPE)
# ----------------------------------------------------
func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _player == null or not is_instance_valid(_player):
		_find_player()

	# 1. SCREEN TOUCH (PRESS / RELEASE)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var screen_w := get_viewport_rect().size.x
		var screen_h := get_viewport_rect().size.y
		
		if touch.pressed:
			# Left screen area -> Virtual Movement Joystick
			if touch.position.x < screen_w * 0.45 and touch.position.y > screen_h * 0.30:
				if _joystick_touch_id == -1:
					_joystick_touch_id = touch.index
					_start_joystick_at(touch.position)
			# Right screen area (excluding bottom-right buttons) -> Camera Look Swipe
			elif touch.position.x >= screen_w * 0.40:
				var in_button_area := (touch.position.x > screen_w * 0.70 and touch.position.y > screen_h * 0.60)
				if not in_button_area and _look_touch_id == -1:
					_look_touch_id = touch.index
		else:
			# Touch released
			if touch.index == _joystick_touch_id:
				_reset_joystick()
			elif touch.index == _look_touch_id:
				_look_touch_id = -1

	# 2. SCREEN DRAG (MOTION)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _joystick_touch_id:
			_update_joystick(drag.position)
		elif drag.index == _look_touch_id:
			if _player and _player.has_method("rotate_camera_touch"):
				_player.rotate_camera_touch(drag.relative)

# ----------------------------------------------------
# JOYSTICK LOGIC
# ----------------------------------------------------
func _start_joystick_at(pos: Vector2) -> void:
	if not joystick_base:
		return
	# Re-center joystick base under finger for dynamic touch response
	joystick_base.global_position = pos - _joystick_center
	_update_joystick(pos)

func _update_joystick(touch_pos: Vector2) -> void:
	if not joystick_base or not joystick_knob:
		return
	var center_global := joystick_base.global_position + _joystick_center
	var delta := touch_pos - center_global
	var dist := delta.length()
	var dir := delta.normalized() if dist > 0.001 else Vector2.ZERO

	var clamped_dist := minf(dist, max_joystick_radius)
	var knob_offset := dir * clamped_dist

	# Center knob inside base
	joystick_knob.position = _joystick_center - (joystick_knob.size * 0.5) + knob_offset

	# Vector for player movement: X = left/right, Y = forward/back
	var move_vec := Vector2.ZERO
	if clamped_dist > 8.0: # Deadzone
		var mag := (clamped_dist - 8.0) / (max_joystick_radius - 8.0)
		move_vec = Vector2(dir.x, dir.y) * mag

	if _player and "touch_move_vector" in _player:
		_player.touch_move_vector = move_vec

func _reset_joystick() -> void:
	_joystick_touch_id = -1
	if joystick_base:
		joystick_base.position = _joystick_default_pos
	if joystick_knob:
		joystick_knob.position = _joystick_center - (joystick_knob.size * 0.5)
	if _player and "touch_move_vector" in _player:
		_player.touch_move_vector = Vector2.ZERO

func toggle_touch_controls() -> void:
	visible = !visible
