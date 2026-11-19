extends Control
##
## Startup splash screen — shows the studio name at launch,
## then transitions to the main menu.
##

var _fade: ColorRect
var _logo: TextureRect

var _in_timer: float = 0.0
var _hold_timer: float = 0.0
var _out_timer: float = 0.0
var _transitioning: bool = false

var FADE_SPEED := 1.6
var FADE_OUT_DELAY := 2.2


func _ready() -> void:
	# Dark base background
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Fade overlay (starts opaque so text fades in from black)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.03)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)

	# Studio logo image
	_logo = TextureRect.new()
	var logo_tex := load("res://assets/logos/velcryn_studios_logo.png") as Texture2D
	if logo_tex:
		_logo.texture = logo_tex
		_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_logo.anchor_left = 0.5
		_logo.anchor_right = 0.5
		_logo.anchor_top = 0.32
		_logo.anchor_bottom = 0.72
		_logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		add_child(_logo)

	# Keep audio from playing before the menu
	Engine.time_scale = 1.0
	# Start the fade-in immediately
	_fade.color.a = 1.0
	_in_timer = 0.0


func _process(delta: float) -> void:
	if _in_timer < 1.0:
		# Fade in: push the black overlay alpha down
		_in_timer = minimax(_in_timer + delta * FADE_SPEED, 0.0, 1.0)
		_fade.color.a = 1.0 - _in_timer
		if _in_timer >= 1.0:
			_hold_timer = 0.0
	elif _hold_timer < FADE_OUT_DELAY:
		_hold_timer += delta
	else:
		# Fade out to black, then go to main menu
		_out_timer = minimax(_out_timer + delta * FADE_SPEED, 0.0, 1.0)
		_fade.color.a = _out_timer
		if _out_timer >= 1.0 and not is_instance_valid(_fade):
			pass
		if _out_timer >= 1.0 and not _transitioning:
			_transitioning = true
			get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
