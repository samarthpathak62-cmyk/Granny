extends Node

enum Difficulty {
	EASY,
	NORMAL,
	HARD,
	EXTREME,
}

var difficulty: Difficulty = Difficulty.NORMAL
var dark_mode: bool = false
var watch_mode: bool = false


func get_difficulty_name() -> String:
	match difficulty:
		Difficulty.EASY:
			return "EASY"
		Difficulty.NORMAL:
			return "NORMAL"
		Difficulty.HARD:
			return "HARD"
		Difficulty.EXTREME:
			return "EXTREME"
	return "NORMAL"


func get_difficulty_description() -> String:
	match difficulty:
		Difficulty.EASY:
			return "EASY: Slow clown, shorter sight, quiet footsteps, no bear traps. Relaxed Granny escape."
		Difficulty.NORMAL:
			return "NORMAL: Balanced Granny AI. Fair speed & sight, max 2 bear traps, smart but outsmartable."
		Difficulty.HARD:
			return "HARD: Ruthless Predator Director AI! Stalks, ambushes, tracks doors, fast chase & 3 bear traps."
		Difficulty.EXTREME:
			return "EXTREME: NIGHTMARE CLOWN! Faster than sprint bursts, hyper senses, 5 traps, zero mercy."
	return ""


func get_difficulty_color() -> Color:
	match difficulty:
		Difficulty.EASY:
			return Color(0.45, 0.90, 0.52)
		Difficulty.NORMAL:
			return Color(0.95, 0.85, 0.42)
		Difficulty.HARD:
			return Color(0.95, 0.45, 0.22)
		Difficulty.EXTREME:
			return Color(0.92, 0.12, 0.16)
	return Color.WHITE


func get_difficulty_script_path() -> String:
	match difficulty:
		Difficulty.EASY:
			return "res://scripts/enemy_clown/ai_easy.gd"
		Difficulty.NORMAL:
			return "res://scripts/enemy_clown/ai_normal.gd"
		Difficulty.HARD:
			return "res://scripts/enemy_clown/ai_hard.gd"
		Difficulty.EXTREME:
			return "res://scripts/enemy_clown/ai_extreme.gd"
	return "res://scripts/enemy_clown/ai_normal.gd"
