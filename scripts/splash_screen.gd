extends Control
##
## Startup splash screen — shows the studio name at launch,
## then transitions to the main menu.
##

var _fade: ColorRect

var _in_timer: float = 0.0
var _hold_timer: float = 0.0
var _out_timer: float = 0.0
var _transitioning: bool = false

var FADE_SPEED := 1.6
var FADE_OUT_DELAY := 2.2


func _ready() -> void:
	_fade = $Fade
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
