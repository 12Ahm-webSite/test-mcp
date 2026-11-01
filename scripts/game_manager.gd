extends Node

signal score_changed(current: int, total: int)
signal game_ended(won: bool)

@export var max_crystals: int = 10
var collected_crystals: int = 0
var is_game_over: bool = false

func _ready() -> void:
    add_to_group("game_manager")
    call_deferred("_init_game")

func _init_game() -> void:
    score_changed.emit(collected_crystals, max_crystals)

func add_crystal() -> void:
    if is_game_over:
        return
    collected_crystals += 1
    score_changed.emit(collected_crystals, max_crystals)
    if collected_crystals >= max_crystals:
        trigger_game_over(true)

func trigger_game_over(won: bool) -> void:
    if is_game_over:
        return
    is_game_over = true
    
    if is_inside_tree():
        var tree := get_tree()
        if tree != null:
            var player := tree.get_first_node_in_group("player") as Node3D
            if player and "is_active" in player:
                player.is_active = false
                
            var enemy := tree.get_first_node_in_group("enemy") as Node3D
            if enemy and "is_active" in enemy:
                enemy.is_active = false
            
    game_ended.emit(won)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
