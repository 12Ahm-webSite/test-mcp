extends Area3D

signal datapad_accessed(archive_id: String, archive_title: String, message: String)

@export var archive_id: String = "DATA-01"
@export var archive_title: String = "Ruins of the Core"
@export_multiline var lore_text: String = "ARCHIVE #01: The ancient builders used these crystals to power the Great Aegis before the robotic sentinels went rogue..."
@export var bonus_score: int = 250

var _is_accessed: bool = false
var _anim_time: float = 0.0
var _base_y: float = 0.0

@onready var light: OmniLight3D = $OmniLight3D if has_node("OmniLight3D") else null
@onready var model: Node3D = $Model if has_node("Model") else null
@onready var holographic_ring: MeshInstance3D = $Model/HoloRing if has_node("Model/HoloRing") else null

func _ready() -> void:
	add_to_group("lore_datapads")
	_base_y = position.y
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_anim_time += delta
	if model:
		model.rotation.y += 1.8 * delta
		model.position.y = _base_y + sin(_anim_time * 3.0) * 0.12
	if holographic_ring:
		holographic_ring.rotation.x = sin(_anim_time * 2.5) * 0.4
		holographic_ring.rotation.z = cos(_anim_time * 2.5) * 0.4

func _on_body_entered(body: Node3D) -> void:
	var is_player := body.is_in_group("player") or body.name.begins_with("Player") or (body is CharacterBody3D and not body.is_in_group("enemy"))
	if not is_player:
		return

	if not _is_accessed:
		_is_accessed = true
		
		# Award bonus discovery score
		var tree := get_tree() if is_inside_tree() else null
		var gm = tree.get_first_node_in_group("game_manager") if tree else null
		if gm and gm.has_method("add_score"):
			gm.add_score(bonus_score)
		
		# Broadcast atmospheric story toast
		if gm and gm.has_signal("toast_announced"):
			gm.toast_announced.emit("📜 [%s] %s" % [archive_title, lore_text])

		# Audio chime
		var audio = tree.get_first_node_in_group("audio_manager") if tree else null
		if audio and audio.has_method("play_datapad"):
			audio.play_datapad()
		elif audio and audio.has_method("play_pickup_weapon"):
			audio.play_pickup_weapon()

		datapad_accessed.emit(archive_id, archive_title, lore_text)

		# Visual reward pulse
		if light:
			light.light_energy = 5.0
			var tw := create_tween()
			tw.tween_property(light, "light_energy", 2.2, 0.6)
