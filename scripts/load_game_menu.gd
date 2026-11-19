extends Control


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_horror_header()
	_style_buttons()
	_apply_dark_mode(_get_dark_mode())


func _get_dark_mode() -> bool:
	if has_node("/root/GameSettings"):
		return bool(get_node("/root/GameSettings").dark_mode)
	return false


func _apply_dark_mode(is_dark: bool) -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.color = Color(0.01, 0.008, 0.012, 0.90) if is_dark else Color(0.03, 0.02, 0.03, 0.45)
	add_child(scrim)
	move_child(scrim, 0)

	var panel_style := StyleBoxFlat.new()
	panel_style.set_corner_radius_all(5)
	panel_style.set_border_width_all(2)
	panel_style.set_content_margin_all(12)
	if is_dark:
		panel_style.bg_color = Color(0.025, 0.02, 0.025, 0.95)
		panel_style.border_color = Color(0.45, 0.08, 0.08, 0.9)
	else:
		panel_style.bg_color = Color(0.08, 0.06, 0.07, 0.92)
		panel_style.border_color = Color(0.55, 0.14, 0.14, 0.9)

	var vb := get_node_or_null("VBoxContainer")
	if vb:
		vb.add_theme_stylebox_override("panel", panel_style)

	var norm := _make_granny_button_style(Color(0.08, 0.06, 0.07, 0.92), Color(0.55, 0.14, 0.14, 0.9))
	var hov := _make_granny_button_style(Color(0.28, 0.05, 0.05, 0.98), Color(0.95, 0.25, 0.25, 1.0))
	if is_dark:
		norm = _make_granny_button_style(Color(0.03, 0.025, 0.03, 0.95), Color(0.24, 0.10, 0.10, 0.9))
		hov = _make_granny_button_style(Color(0.10, 0.03, 0.03, 0.98), Color(0.70, 0.16, 0.16, 0.98))
	if vb:
		for c in vb.get_children():
			if c is Button:
				var b: Button = c as Button
				b.add_theme_stylebox_override("normal", norm)
				b.add_theme_stylebox_override("hover", hov)
				b.add_theme_stylebox_override("pressed", hov)


func _make_granny_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 24
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _load_texture_safe(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var res: Resource = ResourceLoader.load(res_path)
		if res is Texture2D:
			return res as Texture2D
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.new()
		if img.load(abs_path) == OK:
			return ImageTexture.create_from_image(img)
	return null


func _build_horror_header() -> void:
	var horror_font: Font = load("res://assets/FONTS/HelpMe.ttf") as Font

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vbox.offset_left = -260.0
	vbox.offset_right = 260.0
	vbox.offset_top = 48.0
	vbox.offset_bottom = 290.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var center := CenterContainer.new()
	vbox.add_child(center)

	var logo := TextureRect.new()
	logo.custom_minimum_size = Vector2(128, 128)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	logo.texture = _load_texture_safe("res://assets/clown_logo.png")
	center.add_child(logo)

	var title := Label.new()
	title.text = "SELECT HOUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if horror_font:
		title.add_theme_font_override("font", horror_font)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.86, 0.14, 0.14))
	vbox.add_child(title)


func _style_buttons() -> void:
	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0.08, 0.06, 0.07, 0.92)
	norm.border_color = Color(0.55, 0.14, 0.14, 0.9)
	norm.set_border_width_all(2)
	norm.set_corner_radius_all(5)
	norm.set_content_margin_all(12)

	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(0.28, 0.05, 0.05, 0.98)
	hov.border_color = Color(0.95, 0.25, 0.25, 1.0)
	hov.set_border_width_all(2)
	hov.set_corner_radius_all(5)
	hov.set_content_margin_all(12)

	var vb := get_node_or_null("VBoxContainer")
	if vb == null:
		return
	for c in vb.get_children():
		if c is Button:
			var b: Button = c as Button
			b.add_theme_stylebox_override("normal", norm)
			b.add_theme_stylebox_override("hover", hov)
			b.add_theme_stylebox_override("pressed", hov)
			b.add_theme_color_override("font_color", Color(0.90, 0.85, 0.80))
			b.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))


func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		_on_back_pressed()


func _on_save_01_pressed():
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -3.0)
	get_tree().change_scene_to_file("res://scenes/Main House/house-2.tscn")


func _on_save_02_pressed():
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -3.0)
	get_tree().change_scene_to_file("res://scenes/Main House/house.tscn")


func _on_back_pressed():
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -3.0)
	get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
