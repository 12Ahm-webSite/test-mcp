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
@onready var crosshair_label: Label = $Crosshair/Label if has_node("Crosshair/Label") else null

var _alert_tween: Tween = null

func _process(_delta: float) -> void:
	if crosshair_label:
		var player = get_tree().get_first_node_in_group("player")
		if player and "is_aiming" in player:
			if player.is_aiming:
				crosshair_label.text = "•"
				crosshair_label.modulate = Color(0.2, 1.0, 0.7, 0.95)
			else:
				crosshair_label.text = "+"
				crosshair_label.modulate = Color(1.0, 1.0, 1.0, 0.75)

func _ensure_nodes() -> void:
	if not quota_label:
		quota_label = get_node_or_null("TopCenter/Panel/VBox/QuotaLabel")
	if not sector_title_label:
		sector_title_label = get_node_or_null("TopCenter/Panel/VBox/SectorTitle")
	if not leader_label:
		leader_label = get_node_or_null("TopCenter/Panel/VBox/LeaderLabel")
	if not health_bar:
		health_bar = get_node_or_null("BottomLeft/VBox/HealthBar")
	if not health_label:
		health_label = get_node_or_null("BottomLeft/VBox/HealthBar/Label")
	if not shield_label:
		shield_label = get_node_or_null("BottomLeft/VBox/ShieldLabel")
	if not slot_1:
		slot_1 = get_node_or_null("BottomRight/HBox/Slot1")
	if not slot_2:
		slot_2 = get_node_or_null("BottomRight/HBox/Slot2")
	if not slot_3:
		slot_3 = get_node_or_null("BottomRight/HBox/Slot3")
	if not ammo_1:
		ammo_1 = get_node_or_null("BottomRight/HBox/Slot1/VBox/Ammo")
	if not ammo_2:
		ammo_2 = get_node_or_null("BottomRight/HBox/Slot2/VBox/Ammo")
	if not ammo_3:
		ammo_3 = get_node_or_null("BottomRight/HBox/Slot3/VBox/Ammo")
	if not killfeed_container:
		killfeed_container = get_node_or_null("TopRight/KillfeedContainer")
	if not alert_banner:
		alert_banner = get_node_or_null("CenterAlert/AlertBanner")
	if not end_screen:
		end_screen = get_node_or_null("EndScreen")
	if not end_title and end_screen:
		end_title = get_node_or_null("EndScreen/VBox/Title")
	if not end_subtitle and end_screen:
		end_subtitle = get_node_or_null("EndScreen/VBox/Subtitle")
	if not btn_restart and end_screen:
		btn_restart = get_node_or_null("EndScreen/VBox/HBox/BtnRestart")
	if not btn_menu and end_screen:
		btn_menu = get_node_or_null("EndScreen/VBox/HBox/BtnMenu")
	if not crosshair_label:
		crosshair_label = get_node_or_null("Crosshair/Label")

func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	_ensure_nodes()
	if alert_banner:
		alert_banner.modulate.a = 0.0
	if end_screen:
		end_screen.visible = false
		
	var mobile_ctrl := get_node_or_null("MobileTouchControls") as Control
	var bottom_rt := get_node_or_null("BottomRight") as Control
	if mobile_ctrl and mobile_ctrl.visible and bottom_rt:
		bottom_rt.offset_top = -280.0
		bottom_rt.offset_bottom = -210.0
		
	if btn_restart:
		btn_restart.pressed.connect(_on_restart_pressed)
	if btn_menu:
		btn_menu.pressed.connect(_on_menu_pressed)
		
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	_ensure_nodes()
	var tree := get_tree() if is_inside_tree() else null
	var bm = tree.get_first_node_in_group("battle_manager") if tree else null
	if not bm:
		bm = get_parent()
	if not bm:
		bm = owner
		
	if bm and bm.has_signal("scores_updated"):
		if not bm.scores_updated.is_connected(_on_scores_updated):
			bm.scores_updated.connect(_on_scores_updated)
		if not bm.kill_feed_announced.is_connected(_on_killfeed_event):
			bm.kill_feed_announced.connect(_on_killfeed_event)
		if not bm.quota_updated.is_connected(_on_quota_updated):
			bm.quota_updated.connect(_on_quota_updated)
		if not bm.alliance_announced.is_connected(_on_alliance_event):
			bm.alliance_announced.connect(_on_alliance_event)
		if not bm.battle_ended.is_connected(_on_battle_ended):
			bm.battle_ended.connect(_on_battle_ended)
			
		# Immediate sync
		_on_quota_updated(bm.scores.get("Unit-07", 0), bm.kill_quota, bm.sector_title)
		_on_scores_updated(bm.scores, bm.leader_name, bm.leader_score)
		
	var player = tree.get_first_node_in_group("player") if tree else null
	if player:
		if not player.health_changed.is_connected(_on_health_changed):
			player.health_changed.connect(_on_health_changed)
		if not player.shield_changed.is_connected(_on_shield_changed):
			player.shield_changed.connect(_on_shield_changed)
		if not player.weapon_swapped.is_connected(_on_weapon_swapped):
			player.weapon_swapped.connect(_on_weapon_swapped)
		if not player.ammo_updated.is_connected(_on_ammo_updated):
			player.ammo_updated.connect(_on_ammo_updated)
		
		# Initial state sync
		_on_health_changed(player.health, player.max_health)
		_on_weapon_swapped(player.current_weapon, WeaponData.get_weapon(player.current_weapon))
		_on_ammo_updated(player.current_weapon, player.ammo.get(player.current_weapon, 0))

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
	_ensure_nodes()
	if sector_title_label:
		sector_title_label.text = s_title
	if quota_label:
		quota_label.text = "🎯 YOUR KILLS: %d / %d" % [player_kills, quota]
		quota_label.modulate = Color(0.3, 1.0, 0.5) if player_kills >= quota else Color(0.9, 0.95, 1.0)

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
	
	# Limit to 5 entries (remove immediately from container, then queue_free)
	while killfeed_container.get_child_count() > 5:
		var oldest := killfeed_container.get_child(0)
		killfeed_container.remove_child(oldest)
		oldest.queue_free()
		
	# Fade out after 4 seconds
	if is_inside_tree() and get_tree():
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

