extends Control
##
## Animated splash screen — VELCRYN STUDIOS logo with fade-in + scale animation,
## then transitions to the main menu.
##

var _fade: ColorRect
var _logo: TextureRect

var _transitioning: bool = false

var FADE_IN_TIME := 0.6
var HOLD_TIME := 2.0
var FADE_OUT_TIME := 0.5


func _ready() -> void:
	_fade = get_node_or_null("Fade") as ColorRect
	_logo = get_node_or_null("Logo") as TextureRect

	if _fade == null or _logo == null:
		push_error("Splash: missing nodes — check scene")
		get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
		return

	# Start covered
	_fade.color.a = 1.0
	# Start small for scale-in animation
	var start_scale := 0.6
	_logo.scale = Vector2(start_scale, start_scale)
	_logo.modulate.a = 0.0

	# Fade in overlay
	var fade_tween := create_tween()
	fade_tween.tween_property(_fade, "color:a", 0.0, FADE_IN_TIME)

	# Scale up logo
	var scale_tween := create_tween()
	scale_tween.tween_property(_logo, "scale", Vector2(1.0, 1.0), FADE_IN_TIME)

	# Fade in logo alpha
	var alpha_tween := create_tween()
	alpha_tween.tween_property(_logo, "modulate:a", 1.0, FADE_IN_TIME)

	# Wait, then fade out and go to main menu
	var out_tween := create_tween()
	out_tween.delay(FADE_IN_TIME + HOLD_TIME)
	out_tween.tween_property(_fade, "color:a", 1.0, FADE_OUT_TIME)
	out_tween.tween_callback(func():
		if not _transitioning:
			_transitioning = true
			get_tree().change_scene_to_file("res://scenes/mainmenu.tscn"))
