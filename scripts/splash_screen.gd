extends Control
##
## Startup splash screen — shows the studio name at launch,
## then transitions to the main menu.
##

onready var _fade: ColorRect = $Fade
onready var _title_lbl: Label = $Title
onready var _tag_lbl: Label = $Tagline

var _in_timer: float = 0.0
var _hold_timer: float = 0.0
var _out_timer: float = 0.0
var _transitioning: bool = false

var FADE_SPEED := 1.6
var FADE_OUT_DELAY := 2.2


func _ready() -> void:
	Engine.time_scale = 1.0

	# Style the title with horror font
	var horror_font := load("res://assets/FONTS/HelpMe.ttf") as Font
	if horror_font:
		_title_lbl.add_theme_font_override("font", horror_font)
	_title_lbl.add_theme_font_size_override("font_size", 96)
	_title_lbl.add_theme_color_override("font_color", Color(0.88, 0.12, 0.12))
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))

	# Style the tagline
	var ui_font := load("res://assets/FONTS/GrimoireOfDeath-Regular.ttf") as Font
	if ui_font:
		_tag_lbl.add_theme_font_override("font", ui_font)
	_tag_lbl.add_theme_font_size_override("font_size", 28)
	_tag_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.74))
	_tag_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))

	# Start fully covered, fade in reveals the text
	_fade.color.a = 1.0


func _process(delta: float) -> void:
	if _in_timer < 1.0:
		_in_timer = minimax(_in_timer + delta * FADE_SPEED, 0.0, 1.0)
		_fade.color.a = 1.0 - _in_timer
		if _in_timer >= 1.0:
			_hold_timer = 0.0
	elif _hold_timer < FADE_OUT_DELAY:
		_hold_timer += delta
	else:
		_out_timer = minimax(_out_timer + delta * FADE_SPEED, 0.0, 1.0)
		_fade.color.a = _out_timer
		if _out_timer >= 1.0 and not _transitioning:
			_transitioning = true
			get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
