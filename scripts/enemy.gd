extends CharacterBody3D

@export var speed: float = 4.8
@export var turn_speed: float = 6.0
@export var catch_distance: float = 1.3
@export var gravity: float = 19.6

var is_active: bool = true
var _player: Node3D = null

func _ready() -> void:
    add_to_group("enemy")
    _find_player()

func _find_player() -> void:
    _player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = 0.0
    
    if not is_active:
        velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
        move_and_slide()
        return
    
    if _player == null or not is_instance_valid(_player):
        _find_player()
        move_and_slide()
        return
    
    var to_player := _player.global_position - global_position
    to_player.y = 0.0
    var dist := to_player.length()
    
    # Check catch condition
    if dist <= catch_distance:
        is_active = false
        var gm = get_tree().get_first_node_in_group("game_manager")
        if gm and gm.has_method("trigger_game_over"):
            gm.trigger_game_over(false)
        return
    
    var move_dir := to_player.normalized()
    velocity.x = move_dir.x * speed
    velocity.z = move_dir.z * speed
    
    var target_angle := atan2(move_dir.x, move_dir.z)
    rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)
    
    move_and_slide()
    
    # Also check collision slide contacts with player
    for i in get_slide_collision_count():
        var col := get_slide_collision(i)
        var collider := col.get_collider() as Node3D
        if collider and collider.is_in_group("player"):
            is_active = false
            var gm = get_tree().get_first_node_in_group("game_manager")
            if gm and gm.has_method("trigger_game_over"):
                gm.trigger_game_over(false)
            break
