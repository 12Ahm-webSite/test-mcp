class_name PropFuelBarrel
extends StaticBody3D

signal exploded(position: Vector3)

@export var max_health: float = 20.0
@export var explosion_damage: float = 100.0
@export var explosion_radius: float = 6.0

var health: float = 20.0
var is_exploded: bool = false

@onready var intact_model: Node3D = $IntactModel
@onready var destroyed_model: Node3D = $DestroyedModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("fuel_barrels")
	add_to_group("destructible")
	health = max_health
	if destroyed_model:
		destroyed_model.visible = false
	if intact_model:
		intact_model.visible = true

func take_damage(amount: float, attacker: Node3D = null) -> void:
	if is_exploded:
		return
		
	health -= amount
	# Slight wobble on hit
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.08, 0.92, 1.08), 0.06)
	tw.tween_property(self, "scale", Vector3.ONE, 0.08)
	
	if health <= 0.0:
		explode(attacker)

func explode(attacker: Node3D = null) -> void:
	if is_exploded:
		return
	is_exploded = true
	
	if intact_model:
		intact_model.visible = false
	if destroyed_model:
		destroyed_model.visible = true
	if collision_shape:
		collision_shape.disabled = true
		
	if not is_inside_tree():
		return
		
	exploded.emit(global_position)
		
	# SFX
	var tree := get_tree()
	if tree:
		var audio = tree.get_first_node_in_group("audio_manager")
		if audio and audio.has_method("play_explosion"):
			audio.play_explosion()
			
		# Screen shake
		var player = tree.get_first_node_in_group("player")
		if player and player.has_method("add_camera_shake"):
			var dist: float = global_position.distance_to(player.global_position)
			if dist < 22.0:
				var shake_pwr: float = clampf(1.0 - (dist / 22.0), 0.2, 0.9)
				player.add_camera_shake(shake_pwr)
			
	# Radial AoE Damage
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.5, 0))
	query.collision_mask = 1 | 2 | 4 | 8
	
	var results = space_state.intersect_shape(query, 32)
	for res in results:
		var target = res.collider
		if target and target != self and target.has_method("take_damage"):
			var dist: float = global_position.distance_to(target.global_position)
			var falloff: float = clampf(1.0 - (dist / explosion_radius), 0.35, 1.0)
			# Attacker attribution for battle score
			target.take_damage(explosion_damage * falloff, attacker if attacker else self)
			
	# Flash light
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.45, 0.05)
	flash.light_energy = 8.0
	flash.omni_range = explosion_radius * 1.8
	add_child(flash)
	flash.global_position = global_position + Vector3(0, 0.8, 0)
	
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.45)
	tw.tween_callback(flash.queue_free)
	
	exploded.emit(global_position)
