class_name BattleHUD
extends Control

@onready var health_bar: ProgressBar = $BottomLeft/VBox/HealthBar
@onready var health_label: Label = $BottomLeft/VBox/HealthBar/Label
@onready var shield_label: Label = $BottomLeft/VBox/ShieldLabel

@onready var slot_1: PanelContainer = $BottomRight/HBox/Slot1
@onready var slot_2: PanelContainer = $BottomRight/HBox/Slot2
@onready var slot_3: PanelContainer = $BottomRight/HBox/Slot3
@onready var ammo_1: Label = $BottomRight/HBox/Slot1/VBox/Ammo
@onready var ammo_2: Label = $BottomRight/HBox/Slot2/VBox/Ammo
@onready var ammo_3: Label = $BottomRight/HBox/Slot3/VBox/Ammo

@onready var sector_title_label: Label = $TopCenter/Panel/VBox/SectorTitle
@onready var quota_label: Label = $TopCenter/Panel/VBox/QuotaLabel
@onready var leader_label: Label = $TopCenter/Panel/VBox/LeaderLabel

@onready var killfeed_container: VBoxContainer = $TopRight/KillfeedContainer
@onready var alert_banner: Label = $CenterAlert/AlertBanner

@onready var end_screen: PanelContainer = $EndScreen
@onready var end_title: Label = $EndScreen/VBox/Title
@onready var end_subtitle: Label = $EndScreen/VBox/Subtitle
@onready var btn_restart: Button = $EndScreen/VBox/HBox/BtnRestart
@onready var btn_menu: Button = $EndScreen/VBox/HBox/BtnMenu

var _alert_tween: Tween = null

func _ready() -> void:
	if alert_banner:
		alert_banner.modulate.a = 0.0
	if end_screen:
		end_screen.visible = false
		
	if btn_restart:
		btn_restart.pressed.connect(_on_restart_pressed)
	if btn_menu:
		btn_menu.pressed.connect(_on_menu_pressed)
		
	_connect_signals()

func _connect_signals() -> void:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm:
		bm.scores_updated.connect(_on_scores_updated)
		bm.kill_feed_announced.connect(_on_killfeed_event)
		bm.quota_updated.connect(_on_quota_updated)
		bm.alliance_announced.connect(_on_alliance_event)
		bm.battle_ended.connect(_on_battle_ended)
		
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.health_changed.connect(_on_health_changed)
		player.shield_changed.connect(_on_shield_changed)
		player.weapon_swapped.connect(_on_weapon_swapped)
		player.ammo_updated.connect(_on_ammo_updated)
		
		# Initial state sync
		_on_health_changed(player.health, player.max_health)
		_on_weapon_swapped(player.current_weapon, WeaponData.get_weapon(player.current_weapon))

func _on_health_changed(current: float, max_hp: float) -> void:
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current
	if health_label:
		health_label.text = "%d / %d HP" % [int(current), int(max_hp)]

func _on_shield_changed(active: bool, _duration: float) -> void:
	if shield_label:
		shield_label.visible = active

func _on_weapon_swapped(type: int, _w_dict: Dictionary) -> void:
	_highlight_slot(slot_1, type == WeaponData.WeaponType.PISTOL)
	_highlight_slot(slot_2, type == WeaponData.WeaponType.SMG)
	_highlight_slot(slot_3, type == WeaponData.WeaponType.GRENADE)

func _highlight_slot(slot: PanelContainer, is_active: bool) -> void:
	if not slot:
		return
	var style: StyleBoxFlat = slot.get_theme_stylebox("panel")
	if style:
		style.border_color = Color(0.2, 0.9, 1.0, 1.0) if is_active else Color(0.3, 0.35, 0.4, 0.5)
		style.border_width_left = 3 if is_active else 1
		style.border_width_right = 3 if is_active else 1
		style.border_width_top = 3 if is_active else 1
		style.border_width_bottom = 3 if is_active else 1

func _on_ammo_updated(type: int, current_ammo: int) -> void:
	match type:
		WeaponData.WeaponType.PISTOL:
			if ammo_1: ammo_1.text = "∞"
		WeaponData.WeaponType.SMG:
			if ammo_2: ammo_2.text = str(current_ammo)
		WeaponData.WeaponType.GRENADE:
			if ammo_3: ammo_3.text = str(current_ammo)

func _on_quota_updated(player_kills: int, quota: int, s_title: String) -> void:
	if sector_title_label:
		sector_title_label.text = s_title
	if quota_label:
		quota_label.text = "YOUR KILLS: %d / %d" % [player_kills, quota]

func _on_scores_updated(_scores: Dictionary, l_name: String, l_score: int) -> void:
	if leader_label:
		if l_name == "Unit-07":
			leader_label.text = "👑 YOU ARE LEADING! (%d Kills)" % l_score
			leader_label.modulate = Color(1.0, 0.85, 0.2)
		else:
			leader_label.text = "MATCH LEADER: %s (%d Kills)" % [l_name, l_score]
			leader_label.modulate = Color(0.85, 0.9, 0.95)

func _on_killfeed_event(killer: String, victim: String, icon: String) -> void:
	if not killfeed_container:
		return
		
	var entry := Label.new()
	entry.text = "%s  %s  %s" % [killer, icon, victim]
	if killer == "Unit-07":
		entry.modulate = Color(0.2, 1.0, 0.5)
	elif victim == "Unit-07":
		entry.modulate = Color(1.0, 0.3, 0.3)
	else:
		entry.modulate = Color(0.8, 0.85, 0.9)
		
	killfeed_container.add_child(entry)
	
	# Limit to 5 entries
	while killfeed_container.get_child_count() > 5:
		killfeed_container.get_child(0).queue_free()
		
	# Fade out after 4 seconds
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(entry):
			var tw := entry.create_tween()
			tw.tween_property(entry, "modulate:a", 0.0, 0.5)
			tw.tween_callback(entry.queue_free)
	)

func _on_alliance_event(message: String, is_positive: bool) -> void:
	if not alert_banner:
		return
		
	if _alert_tween and _alert_tween.is_valid():
		_alert_tween.kill()
		
	alert_banner.text = message
	alert_banner.modulate = Color(0.2, 1.0, 0.5, 0.0) if is_positive else Color(1.0, 0.4, 0.2, 0.0)
	
	_alert_tween = create_tween()
	_alert_tween.tween_property(alert_banner, "modulate:a", 1.0, 0.25)
	_alert_tween.tween_interval(2.5)
	_alert_tween.tween_property(alert_banner, "modulate:a", 0.0, 0.4)

func _on_battle_ended(player_won: bool, winner_name: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not end_screen:
		return
		
	end_screen.visible = true
	if player_won:
		end_title.text = "🏆 CHAMPIONSHIP VICTORY!"
		end_title.modulate = Color(1.0, 0.85, 0.2)
		end_subtitle.text = "You conquered all 3 sectors and claimed the championship!"
	else:
		end_title.text = "💀 DEFEAT - %s WINS" % winner_name
		end_title.modulate = Color(1.0, 0.3, 0.3)
		end_subtitle.text = "%s reached the championship kill quota first." % winner_name

func _on_restart_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/battle_1_ruins.tscn")

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

