extends Control
##
## Startup splash screen — shows the studio name at launch,
## then transitions to the main menu.
##

var _fade: ColorRect
var _stud_lbl: Label
var _tag_lbl: Label

var _in_timer: float = 0.0
var _hold_timer: float = 0.0
var _out_timer: float = 0.0

var FADE_SPEED := 1.6
var FADE_OUT_DELAY := 2.2


func _ready() -> void:
	# Dark base background
	set_camera_3d_ignore(true)
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

	# Studio name
	_stud_lbl = Label.new()
	_stud_lbl.text = "VELCRYN STUDIOS"
	_stud_lbl.anchor_left = 0.5
	_stud_lbl.anchor_right = 0.5
	_stud_lbl.anchor_top = 0.42
	_stud_lbl.anchor_bottom = 0.58
	_stud_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stud_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var horror_font := load("res://assets/FONTS/HelpMe.ttf") as Font
	if horror_font:
		_stud_lbl.add_theme_font_override("font", horror_font)
	_stud_lbl.add_theme_font_size_override("font_size", 110)
	_stud_lbl.add_theme_color_override("font_color", Color(0.88, 0.12, 0.12))
	_stud_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	add_child(_stud_lbl)

	# Tagline under the name
	_tag_lbl = Label.new()
	_tag_lbl.text = "PRESENTS"
	_tag_lbl.anchor_left = 0.5
	_tag_lbl.anchor_right = 0.5
	_tag_lbl.anchor_top = 0.60
	_tag_lbl.anchor_bottom = 0.68
	_tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ui_font := load("res://assets/FONTS/GrimoireOfDeath-Regular.ttf") as Font
	if ui_font:
		_tag_lbl.add_theme_font_override("font", ui_font)
	_tag_lbl.add_theme_font_size_override("font_size", 32)
	_tag_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.74))
	_tag_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	add_child(_tag_lbl)

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
		if _out_timer >= 1.0:
			get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
