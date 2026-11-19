extends Control
##
## Startup splash screen — shows the studio logo at launch,
## then transitions to the main menu.
##

var _fade: ColorRect
var _logo_rect: TextureRect
var _fallback_lbl: Label

var _in_timer: float = 0.0
var _hold_timer: float = 0.0
var _out_timer: float = 0.0
var _transitioning: bool = false

var FADE_SPEED := 1.6
var FADE_OUT_DELAY := 2.2


func _ready() -> void:
	_fade = get_node_or_null("Fade") as ColorRect
	_logo_rect = get_node_or_null("Logo") as TextureRect
	_fallback_lbl = get_node_or_null("FallbackText") as Label

	if _fade == null or _logo_rect == null or _fallback_lbl == null:
		push_error("Splash: required nodes not found — check scene tree")
		return

	# Always show fallback text first — hide it only if logo image loads correctly
	_fallback_lbl.visible = true

	# Try to load the logo texture at runtime
	var logo_tex := load("res://assets/logos/velcryn_studios_logo.png") as Texture2D
	if logo_tex and logo_tex.get_size() > Vector2(1, 1):
		_logo_rect.texture = logo_tex
		_fallback_lbl.visible = false
	else:
		# Texture is null or empty — keep text fallback visible
		_logo_rect.visible = false
		push_warning("Splash: logo texture failed to load — showing text fallback")

	_fade.color.a = 1.0


func _process(delta: float) -> void:
	if _in_timer < 1.0:
		_in_timer = clamp(_in_timer + delta * FADE_SPEED, 0.0, 1.0)
		if _fade:
			_fade.color.a = 1.0 - _in_timer
		if _in_timer >= 1.0:
			_hold_timer = 0.0
	elif _hold_timer < FADE_OUT_DELAY:
		_hold_timer += delta
	else:
		_out_timer = clamp(_out_timer + delta * FADE_SPEED, 0.0, 1.0)
		if _fade:
			_fade.color.a = _out_timer
		if _out_timer >= 1.0 and not _transitioning:
			_transitioning = true
			get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
