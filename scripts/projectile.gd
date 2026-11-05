class_name Projectile
extends Area3D

@export var speed: float = 55.0
@export var damage: float = 25.0
@export var gravity_scale: float = 0.0
@export var is_explosive: bool = false
@export var explosion_radius: float = 5.0
@export var max_lifetime: float = 3.5

var shooter: Node3D = null
var shooter_name: String = ""
var velocity: Vector3 = Vector3.ZERO
var _lifetime: float = 0.0

@onready var visual_mesh: MeshInstance3D = $MeshInstance3D
@onready var grenade_mesh: MeshInstance3D = $GrenadeMesh
@onready var light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup(p_shooter: Node3D, p_direction: Vector3, p_weapon: Dictionary) -> void:
	shooter = p_shooter
	if shooter:
		shooter_name = shooter.name if not "character_name" in shooter else shooter.character_name
	
	speed = p_weapon.get("projectile_speed", 55.0)
	damage = p_weapon.get("damage", 25.0)
	gravity_scale = p_weapon.get("gravity_scale", 0.0)
	is_explosive = p_weapon.get("is_explosive", false)
	explosion_radius = p_weapon.get("explosion_radius", 5.0)
	
	velocity = p_direction.normalized() * speed
	if is_inside_tree() and p_direction.length_squared() > 0.001:
		var dir := p_direction.normalized()
		var up := Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.98 else Vector3.UP
		look_at(global_position + dir, up)
	
	if is_explosive:
		if visual_mesh:
			visual_mesh.visible = false
		if grenade_mesh:
			grenade_mesh.visible = true
		if light:
			light.light_color = Color(1.0, 0.4, 0.1)
			light.omni_range = 3.5
	else:
		if visual_mesh:
			visual_mesh.visible = true
		if grenade_mesh:
			grenade_mesh.visible = false
		if light:
			light.light_color = Color(1.0, 0.9, 0.3)
			light.omni_range = 2.5

func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= max_lifetime:
		if is_explosive:
			_explode()
		else:
			queue_free()
		return
		
	if gravity_scale > 0.0:
		velocity.y -= 19.6 * gravity_scale * delta
		
	global_position += velocity * delta
	if is_inside_tree() and velocity.length_squared() > 0.01:
		var dir := velocity.normalized()
		var up := Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.98 else Vector3.UP
		look_at(global_position + dir, up)

func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
		
	if is_explosive:
		_explode()
		return
		
	# Direct hit
	if body.has_method("take_damage"):
		body.take_damage(damage, shooter)
		var tree := get_tree() if is_inside_tree() else null
		var audio = tree.get_first_node_in_group("audio_manager") if tree else null
		if audio and audio.has_method("play_hit"):
			audio.play_hit()
			
		# Impact juice: Hit-Stop and Camera Punch if player fired the shot
		if shooter and (shooter.is_in_group("player") or shooter.name.begins_with("Player")):
			if shooter.has_method("trigger_hit_stop"):
				shooter.trigger_hit_stop(0.04, 0.15)
			else:
				_trigger_hit_stop(0.04, 0.15)
			if shooter.has_method("add_camera_shake"):
				shooter.add_camera_shake(0.25)
	
	_spawn_spark_and_free()

func _trigger_hit_stop(duration: float = 0.04, time_scale_val: float = 0.15) -> void:
	var tree := get_tree() if is_inside_tree() else (shooter.get_tree() if (shooter and shooter.is_inside_tree()) else null)
	if not tree:
		var ml = Engine.get_main_loop()
		if ml is SceneTree:
			tree = ml as SceneTree
	Engine.time_scale = time_scale_val
	if tree:
		# Use timer signal with CONNECT_ONE_SHOT so projectile queue_free() cannot cancel the restoration
		tree.create_timer(duration, true, false, true).timeout.connect(func():
			Engine.time_scale = 1.0
		, CONNECT_ONE_SHOT)
	else:
		Engine.time_scale = 1.0

func _on_area_entered(area: Area3D) -> void:
	if area == self or area == shooter:
		return
	if is_explosive:
		_explode()

func _explode() -> void:
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# Audio
	var tree := get_tree() if is_inside_tree() else null
	var audio = tree.get_first_node_in_group("audio_manager") if tree else null
	if audio and audio.has_method("play_explosion"):
		audio.play_explosion()
		
	# Screen shake if near player
	var player = tree.get_first_node_in_group("player") if tree else null
	if player and player.has_method("add_camera_shake"):
		var dist: float = global_position.distance_to(player.global_position)
		if dist < 18.0:
			var shake_pwr: float = clampf(1.0 - (dist / 18.0), 0.1, 0.75)
			player.add_camera_shake(shake_pwr)
	
	# AoE Damage
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 1 | 2 | 4 | 8 # Walls, Player, Bots, Barrels
	
	var results = space_state.intersect_shape(query, 32)
	for res in results:
		var target = res.collider
		if target and target != shooter and target.has_method("take_damage"):
			var target_pos: Vector3 = target.global_position
			var dist: float = global_position.distance_to(target_pos)
			var falloff: float = clampf(1.0 - (dist / explosion_radius), 0.25, 1.0)
			target.take_damage(damage * falloff, shooter)
			
	_spawn_explosion_vfx()
	queue_free()

func _spawn_spark_and_free() -> void:
	if is_inside_tree() and get_parent():
		var spark := OmniLight3D.new()
		spark.light_color = Color(1.0, 0.92, 0.5)
		spark.light_energy = 3.5
		spark.omni_range = 2.2
		get_parent().add_child(spark)
		spark.global_position = global_position
		var tw := spark.create_tween()
		tw.tween_property(spark, "light_energy", 0.0, 0.08)
		tw.tween_callback(spark.queue_free)
	queue_free()

func _spawn_explosion_vfx() -> void:
	# Create transient flash burst
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.5, 0.1)
	flash.light_energy = 5.0
	flash.omni_range = explosion_radius * 1.5
	get_parent().add_child(flash)
	flash.global_position = global_position
	
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
