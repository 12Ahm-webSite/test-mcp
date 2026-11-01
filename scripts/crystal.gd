extends Area3D

signal collected

@export var rotation_speed: float = 2.5
@export var bob_speed: float = 3.0
@export var bob_height: float = 0.2

var _base_y: float = 0.0
var _time: float = 0.0
var _is_collected: bool = false

func _ready() -> void:
	_base_y = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _is_collected:
		return
	_time += delta
	rotation.y += rotation_speed * delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if _is_collected:
		return
	if body.is_in_group("player") or body.name == "Player":
		_is_collected = true
		set_deferred("monitoring", false)
		collected.emit()
		
		var gm = get_tree().get_first_node_in_group("game_manager")
		if gm and gm.has_method("add_crystal"):
			gm.add_crystal()
		
		var tween := create_tween().set_parallel(true)
		tween.tween_property(self, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "position:y", position.y + 0.6, 0.25).set_ease(Tween.EASE_OUT)
		tween.chain().tween_callback(queue_free)
