extends Node3D

@export var target_path: NodePath
@export var follow_speed: float = 10.0
@export var offset: Vector3 = Vector3(0.0, 1.5, 0.0)

var _target: Node3D = null

func _ready() -> void:
    set_as_top_level(true)
    _find_target()

func _find_target() -> void:
    if not target_path.is_empty():
        _target = get_node_or_null(target_path)
    if _target == null:
        _target = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
    if _target == null or not is_instance_valid(_target):
        _find_target()
        return
    var target_pos := _target.global_position + offset
    global_position = global_position.lerp(target_pos, follow_speed * delta)
