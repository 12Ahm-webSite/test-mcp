extends Area3D

signal collected(type: int, score: int)

enum CrystalType {
	ENERGY,
	SPEED,
	SHIELD,
	RARE
}

@export var crystal_type: CrystalType = CrystalType.ENERGY
@export var rotation_speed: float = 2.5
@export var bob_speed: float = 3.0
@export var bob_height: float = 0.2

var _base_y: float = 0.0
var _time: float = 0.0
var _is_collected: bool = false

@onready var model_top: MeshInstance3D = $Model/TopCone
@onready var model_bottom: MeshInstance3D = $Model/BottomCone
@onready var light: OmniLight3D = $OmniLight3D

const BURST_VFX := preload("res://scenes/vfx_crystal_burst.tscn")
const MAT_ENERGY := preload("res://assets/materials/mat_crystal.tres")
const MAT_SPEED := preload("res://assets/materials/mat_crystal_speed.tres")
const MAT_SHIELD := preload("res://assets/materials/mat_crystal_shield.tres")
const MAT_RARE := preload("res://assets/materials/mat_crystal_rare.tres")

func _ready() -> void:
	add_to_group("crystals")
	if crystal_type == CrystalType.ENERGY:
		add_to_group("energy_crystals")
	_base_y = position.y
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_apply_visuals()

func _apply_visuals() -> void:
	var mat: StandardMaterial3D = MAT_ENERGY
	var color := Color(0.2, 0.9, 1.0)
	
	match crystal_type:
		CrystalType.ENERGY:
			mat = MAT_ENERGY
			color = Color(0.15, 0.9, 1.0)
		CrystalType.SPEED:
			mat = MAT_SPEED
			color = Color(1.0, 0.78, 0.15)
		CrystalType.SHIELD:
			mat = MAT_SHIELD
			color = Color(0.2, 1.0, 0.5)
		CrystalType.RARE:
			mat = MAT_RARE
			color = Color(0.9, 0.2, 1.0)
			
	if model_top:
		model_top.material_override = mat
	if model_bottom:
		model_bottom.material_override = mat
	if light:
		light.light_color = color

func _process(delta: float) -> void:
	if _is_collected:
		return
	_time += delta
	rotation.y += rotation_speed * delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if _is_collected:
		return
		
	var player := body as CharacterBody3D
	if not player and body.is_in_group("player"):
		player = body as CharacterBody3D
		
	if player:
		_is_collected = true
		remove_from_group("crystals")
		remove_from_group("energy_crystals")
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		
		# Apply buffs to player if applicable
		var score := 100
		match crystal_type:
			CrystalType.ENERGY:
				score = 100
			CrystalType.SPEED:
				score = 150
				if player.has_method("activate_speed_boost"):
					player.activate_speed_boost(1.45, 8.0)
			CrystalType.SHIELD:
				score = 150
				if player.has_method("activate_shield"):
					player.activate_shield(12.0)
			CrystalType.RARE:
				score = 500
				
		collected.emit(crystal_type, score)
		
		# Notify GameManager
		if is_inside_tree() and get_tree():
			var gm = get_tree().get_first_node_in_group("game_manager")
			if gm and gm.has_method("collect_crystal"):
				gm.collect_crystal(crystal_type, score)
			elif gm and gm.has_method("add_crystal"):
				gm.add_crystal()
			
		# Spawn Crystal Burst particles
		_spawn_burst_vfx()
		
		# Elegant pickup scale animation
		var tween := create_tween().set_parallel(true)
		var model_node = get_node_or_null("Model")
		if model_node:
			tween.tween_property(model_node, "scale", Vector3(0.01, 0.01, 0.01), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		else:
			tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "position:y", position.y + 0.6, 0.2).set_ease(Tween.EASE_OUT)
		tween.chain().tween_callback(queue_free)

func _spawn_burst_vfx() -> void:
	if BURST_VFX and is_inside_tree():
		var vfx: GPUParticles3D = BURST_VFX.instantiate()
		var parent_node := get_parent()
		if parent_node:
			parent_node.add_child(vfx)
			vfx.global_position = global_position
			var burst_color := Color(0.2, 0.9, 1.0)
			match crystal_type:
				CrystalType.SPEED:
					burst_color = Color(1.0, 0.78, 0.15)
				CrystalType.SHIELD:
					burst_color = Color(0.2, 1.0, 0.5)
				CrystalType.RARE:
					burst_color = Color(0.9, 0.2, 1.0)
			if vfx.has_method("set_burst_color"):
				vfx.set_burst_color(burst_color)
