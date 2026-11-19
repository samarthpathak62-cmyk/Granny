extends Control
##
## Startup splash screen — shows VELCRYN STUDIOS, then goes to main menu.
##

var _timer: float = 0.0
var _show_delay := 0.3
var _hold_time := 2.5


func _ready() -> void:
	# Style the title label with horror font
	var title_lbl := get_node_or_null("Title") as Label
	if title_lbl:
		var horror_font := load("res://assets/FONTS/HelpMe.ttf") as Font
		if horror_font:
			title_lbl.add_theme_font_override("font", horror_font)
		title_lbl.add_theme_font_size_override("font_size", 88)
		title_lbl.add_theme_color_override("font_color", Color(0.88, 0.12, 0.12))
		title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))

	# Style the tagline
	var tag_lbl := get_node_or_null("Tagline") as Label
	if tag_lbl:
		var ui_font := load("res://assets/FONTS/GrimoireOfDeath-Regular.ttf") as Font
		if ui_font:
			tag_lbl.add_theme_font_override("font", ui_font)
		tag_lbl.add_theme_font_size_override("font_size", 26)
		tag_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.74))


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _show_delay + _hold_time:
		get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
