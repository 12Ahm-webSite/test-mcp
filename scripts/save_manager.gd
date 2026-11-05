extends Node

const SAVE_PATH := "user://crystal_rush_save.json"

var unlocked_levels: int = 1
var high_scores: Dictionary = {"level_1": 0, "level_2": 0, "level_3": 0}
var best_times: Dictionary = {"level_1": 999.0, "level_2": 999.0, "level_3": 999.0}
var best_ranks: Dictionary = {"level_1": "-", "level_2": "-", "level_3": "-"}
var settings: Dictionary = {
	"mouse_sensitivity": 0.003,
	"ssao_enabled": true,
	"glow_enabled": true,
	"master_volume": 1.0,
	"touch_controls_enabled": false
}

const RANK_ORDER := {"S": 4, "A": 3, "B": 2, "C": 1, "-": 0}

func is_rank_better(new_rank: String, old_rank: String) -> bool:
	return RANK_ORDER.get(new_rank, 0) > RANK_ORDER.get(old_rank, 0)

func get_best_rank(level_key: String) -> String:
	return str(best_ranks.get(level_key, "-"))

func _ready() -> void:
	load_game()

func save_game() -> bool:
	var data := {
		"version": 1,
		"unlocked_levels": unlocked_levels,
		"high_scores": high_scores,
		"best_times": best_times,
		"best_ranks": best_ranks,
		"settings": settings
	}
	var json_str := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(json_str)
	file.close()
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
		
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
		
	var content := file.get_as_text()
	file.close()
	
	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary):
		return false
		
	unlocked_levels = int(parsed.get("unlocked_levels", 1))
	high_scores = parsed.get("high_scores", high_scores)
	best_times = parsed.get("best_times", best_times)
	best_ranks = parsed.get("best_ranks", best_ranks)
	settings = parsed.get("settings", settings)
	return true

func is_level_unlocked(level_key: String) -> bool:
	match level_key:
		"level_1":
			return true
		"level_2":
			return unlocked_levels >= 2
		"level_3":
			return unlocked_levels >= 3
		_:
			return false

func get_high_score(level_key: String) -> int:
	return int(high_scores.get(level_key, 0))

func get_best_time(level_key: String) -> float:
	return float(best_times.get(level_key, 999.0))

func get_setting(key: String, default_value: Variant) -> Variant:
	return settings.get(key, default_value)

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_game()

func register_level_completion(level_key: String, score: int, time_taken: float, rank: String = "") -> void:
	if score > high_scores.get(level_key, 0):
		high_scores[level_key] = score
	if time_taken < best_times.get(level_key, 999.0):
		best_times[level_key] = time_taken
	if rank != "" and is_rank_better(rank, best_ranks.get(level_key, "-")):
		best_ranks[level_key] = rank
		
	var next_level_idx := 1
	if level_key == "level_1":
		next_level_idx = 2
	elif level_key == "level_2":
		next_level_idx = 3
	elif level_key == "level_3":
		next_level_idx = 4
		
	if next_level_idx > unlocked_levels and next_level_idx <= 4:
		unlocked_levels = next_level_idx
		
	save_game()
