class_name WeaponData
extends RefCounted

enum WeaponType {
	PISTOL,
	SMG,
	GRENADE
}

const WEAPONS := {
	WeaponType.PISTOL: {
		"id": WeaponType.PISTOL,
		"name": "ZC57 Tactical Pistol",
		"short_name": "ZC57",
		"slot": 1,
		"damage": 25.0,
		"fire_rate": 0.28, # seconds between shots
		"projectile_speed": 55.0,
		"gravity_scale": 0.0,
		"is_explosive": false,
		"explosion_radius": 0.0,
		"max_ammo": 999, # Infinite sidearm
		"starting_ammo": 999,
		"is_automatic": false,
		"spread": 0.015,
		"model_path": "res://assets/models/weapons/Guns/ZC57/ZC57_Rigged.glb",
		"scale": Vector3(0.4, 0.4, 0.4),
		"offset": Vector3(0.28, -0.15, -0.42),
		"sfx_method": "play_pistol"
	},
	WeaponType.SMG: {
		"id": WeaponType.SMG,
		"name": "MGP7 Rapid SMG",
		"short_name": "MGP7",
		"slot": 2,
		"damage": 14.0,
		"fire_rate": 0.11, # ~9 rounds/sec
		"projectile_speed": 60.0,
		"gravity_scale": 0.0,
		"is_explosive": false,
		"explosion_radius": 0.0,
		"max_ammo": 150,
		"starting_ammo": 60,
		"is_automatic": true,
		"spread": 0.045,
		"model_path": "res://assets/models/weapons/Guns/MGP7/MGP7_Rigged.glb",
		"scale": Vector3(0.35, 0.35, 0.35),
		"offset": Vector3(0.28, -0.16, -0.44),
		"sfx_method": "play_smg"
	},
	WeaponType.GRENADE: {
		"id": WeaponType.GRENADE,
		"name": "M67 Frag Grenade",
		"short_name": "M67",
		"slot": 3,
		"damage": 85.0,
		"fire_rate": 0.9,
		"projectile_speed": 22.0,
		"gravity_scale": 1.2, # Arcs in air
		"is_explosive": true,
		"explosion_radius": 5.0,
		"max_ammo": 8,
		"starting_ammo": 3,
		"is_automatic": false,
		"spread": 0.02,
		"model_path": "res://assets/models/weapons/Guns/Grenades/M67V1_Rigged.glb",
		"scale": Vector3(0.45, 0.45, 0.45),
		"offset": Vector3(0.24, -0.12, -0.36),
		"sfx_method": "play_grenade_throw"
	}
}

static func get_weapon(type: WeaponType) -> Dictionary:
	return WEAPONS.get(type, WEAPONS[WeaponType.PISTOL])
