extends Node3D

signal portal_entered

@export var portal_color: Color = Color(0.2, 0.95, 1.0)
var is_active: bool = false

@onready var area: Area3D = $Area3D
@onready var energy_core: MeshInstance3D = $Model/EnergyCore
@onready var beacon_light: OmniLight3D = $BeaconLight
@onready var sky_beam: SpotLight3D = $SkyBeam
@onready var particles: GPUParticles3D = $PortalParticles

var _time: float = 0.0

func _ready() -> void:
	if area:
		area.body_entered.connect(_on_body_entered)
		area.monitoring = false
	if energy_core:
		energy_core.visible = false
	if beacon_light:
		beacon_light.visible = false
	if sky_beam:
		sky_beam.visible = false
	if particles:
		particles.emitting = false

func _process(delta: float) -> void:
	if not is_active:
		return
	_time += delta
	if energy_core:
		energy_core.rotation.y += delta * 1.5
		var pulse: float = 1.0 + sin(_time * 4.0) * 0.15
		energy_core.scale = Vector3(pulse, 1.0, pulse)

func activate() -> void:
	if is_active:
		return
	is_active = true
	
	if area:
		area.monitoring = true
	if energy_core:
		energy_core.visible = true
	if beacon_light:
		beacon_light.visible = true
		beacon_light.light_energy = 5.0
	if sky_beam:
		sky_beam.visible = true
		sky_beam.light_energy = 8.0
	if particles:
		particles.emitting = true
		
	# Trigger nice flare animation
	var tween := create_tween()
	tween.tween_property(beacon_light, "light_energy", 3.5, 1.0)

func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
	if body.is_in_group("player") or body.name == "Player":
		portal_entered.emit()
		var gm = get_tree().get_first_node_in_group("game_manager")
		if gm and gm.has_method("on_portal_reached"):
			gm.on_portal_reached()
