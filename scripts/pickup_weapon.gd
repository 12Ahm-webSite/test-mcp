class_name PickupWeapon
extends Area3D

enum PickupType {
	SMG,
	GRENADE,
	MEDKIT
}

@export var pickup_type: PickupType = PickupType.SMG
@export var respawn_time: float = 14.0
@export var rotate_speed: float = 2.2
@export var bob_speed: float = 3.2
@export var bob_height: float = 0.15

var _base_y: float = 0.0
var _time: float = 0.0
var _is_active: bool = true

@onready var model_smg: Node3D = $ModelSMG
@onready var model_grenade: Node3D = $ModelGrenade
@onready var model_medkit: Node3D = $ModelMedKit
@onready var halo_light: OmniLight3D = $OmniLight3D
@onready var beacon_beam: MeshInstance3D = $BeaconBeam if has_node("BeaconBeam") else null
@onready var ground_ring: MeshInstance3D = $GroundRing if has_node("GroundRing") else null
@onready var billboard_label: Label3D = $BillboardLabel if has_node("BillboardLabel") else null

func _ready() -> void:
	add_to_group("pickups")
	_base_y = position.y
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_update_visuals()

func _update_visuals() -> void:
	if model_smg:
		model_smg.visible = (pickup_type == PickupType.SMG)
	if model_grenade:
		model_grenade.visible = (pickup_type == PickupType.GRENADE)
	if model_medkit:
		model_medkit.visible = (pickup_type == PickupType.MEDKIT)
		
	var theme_color := Color(0.2, 0.85, 1.0)
	var label_text := "[ 💥 PLASMA SMG ]"
	
	match pickup_type:
		PickupType.SMG:
			theme_color = Color(0.2, 0.85, 1.0)
			label_text = "[ 💥 PLASMA SMG ]"
		PickupType.GRENADE:
			theme_color = Color(1.0, 0.5, 0.1)
			label_text = "[ 💣 CHRONO GRENADE ]"
		PickupType.MEDKIT:
			theme_color = Color(0.2, 1.0, 0.45)
			label_text = "[ ❤️ NANO-MEDKIT (+35 HP) ]"

	if halo_light:
		halo_light.light_color = theme_color
	if billboard_label:
		billboard_label.text = label_text
		billboard_label.modulate = theme_color
	if beacon_beam:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(theme_color.r, theme_color.g, theme_color.b, 0.38)
		beacon_beam.material_override = mat
	if ground_ring:
		var ring_mat := StandardMaterial3D.new()
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(theme_color.r, theme_color.g, theme_color.b, 0.65)
		ground_ring.material_override = ring_mat

func _process(delta: float) -> void:
	if not _is_active:
		return
	_time += delta
	rotation.y += rotate_speed * delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if not _is_active:
		return
		
	var collected: bool = false
	var audio = get_tree().get_first_node_in_group("audio_manager")
	
	match pickup_type:
		PickupType.SMG:
			if body.has_method("pickup_weapon"):
				body.pickup_weapon(WeaponData.WeaponType.SMG, 60)
				collected = true
				if audio and audio.has_method("play_weapon_pickup"):
					audio.play_weapon_pickup()
		PickupType.GRENADE:
			if body.has_method("pickup_weapon"):
				body.pickup_weapon(WeaponData.WeaponType.GRENADE, 3)
				collected = true
				if audio and audio.has_method("play_weapon_pickup"):
					audio.play_weapon_pickup()
		PickupType.MEDKIT:
			if body.has_method("heal"):
				# Only pick up if health < max_health or for bots needing HP
				var current_hp: float = body.health if "health" in body else 100.0
				var max_hp: float = body.max_health if "max_health" in body else 100.0
				if current_hp < max_hp:
					body.heal(35.0)
					collected = true
					if audio and audio.has_method("play_medkit"):
						audio.play_medkit()
						
	if collected:
		_consume()

func _consume() -> void:
	_is_active = false
	visible = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# Respawn timer
	await get_tree().create_timer(respawn_time).timeout
	if is_instance_valid(self) and is_inside_tree():
		_respawn()

func _respawn() -> void:
	_is_active = true
	visible = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	
	# Spawn scale pop (avoid singular zero scale)
	scale = Vector3(0.01, 0.01, 0.01)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

