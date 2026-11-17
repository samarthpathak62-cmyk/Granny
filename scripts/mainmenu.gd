extends Control

var mainhouse = preload("res://scenes/Main House/house.tscn")

@onready var menu = $menu
@onready var options = $options
@onready var audio = $Audio
@onready var graphics = $graphics
@onready var fullscreen_check: CheckBox = $graphics/HBoxContainer/Checks/FullScreen
@onready var vsync_check: CheckBox = $graphics/HBoxContainer/Checks/VSync
@onready var master_slider: HSlider = $Audio/HBoxContainer/slider/master
@onready var music_slider: HSlider = $Audio/HBoxContainer/slider/music
@onready var sfx_slider: HSlider = $"Audio/HBoxContainer/slider/sound fx"

var mode_panel: PanelContainer = null
var title_lbl: Label = null
var diff_buttons: Array[Button] = []
var dark_mode_btn: Button = null
var mode_desc_label: Label = null
var dark_desc_label: Label = null


func _ready():
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.set_chase_intensity(0.0)
		am.start_menu_music(-10.0)

	menu.visible = true
	options.visible = false
	audio.visible = false
	graphics.visible = false

	_build_mode_selector_ui()
	_connect_button_hover_sfx(self)

	if fullscreen_check:
		fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if vsync_check:
		vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED

	_sync_slider(0, master_slider)
	_sync_slider(1, music_slider)
	_sync_slider(2, sfx_slider)


func _build_mode_selector_ui() -> void:
	var ui_font: Font = load("res://assets/FONTS/GrimoireOfDeath-Regular.ttf") as Font
	var horror_font: Font = load("res://assets/FONTS/HelpMe.ttf") as Font

	# Shift main menu buttons slightly higher to make room for Granny Difficulty + Dark Mode panel
	menu.offset_top = -280.0
	menu.offset_bottom = -20.0

	title_lbl = Label.new()
	title_lbl.text = "ROBERT THE CLOWN"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if horror_font:
		title_lbl.add_theme_font_override("font", horror_font)
	title_lbl.add_theme_font_size_override("font_size", 58)
	title_lbl.add_theme_color_override("font_color", Color(0.86, 0.14, 0.14))
	title_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_lbl.offset_left = -420.0
	title_lbl.offset_right = 420.0
	title_lbl.offset_top = 44.0
	title_lbl.offset_bottom = 124.0
	add_child(title_lbl)

	mode_panel = PanelContainer.new()
	mode_panel.set_anchors_preset(Control.PRESET_CENTER)
	mode_panel.offset_left = -430.0
	mode_panel.offset_right = 430.0
	mode_panel.offset_top = 35.0
	mode_panel.offset_bottom = 325.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.88)
	style.border_color = Color(0.55, 0.12, 0.12, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	mode_panel.add_theme_stylebox_override("panel", style)
	add_child(mode_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	mode_panel.add_child(vbox)

	var diff_header := Label.new()
	diff_header.text = "SELECT DIFFICULTY"
	diff_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ui_font:
		diff_header.add_theme_font_override("font", ui_font)
	diff_header.add_theme_font_size_override("font_size", 32)
	diff_header.add_theme_color_override("font_color", Color(0.92, 0.85, 0.72))
	vbox.add_child(diff_header)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)

	var diff_defs: Array[Dictionary] = [
		{"id": 0, "label": "EASY"},
		{"id": 1, "label": "NORMAL"},
		{"id": 2, "label": "HARD"},
		{"id": 3, "label": "EXTREME"},
	]
	diff_buttons.clear()
	for d in diff_defs:
		var btn := Button.new()
		btn.text = str(d["label"])
		btn.custom_minimum_size = Vector2(175, 50)
		if ui_font:
			btn.add_theme_font_override("font", ui_font)
		btn.add_theme_font_size_override("font_size", 30)
		var diff_id: int = int(d["id"])
		btn.pressed.connect(func(): _on_difficulty_selected(diff_id))
		btn_row.add_child(btn)
		diff_buttons.append(btn)

	mode_desc_label = Label.new()
	mode_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc_label.add_theme_font_size_override("font_size", 17)
	mode_desc_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
	vbox.add_child(mode_desc_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var dark_row := HBoxContainer.new()
	dark_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dark_row.add_theme_constant_override("separation", 18)
	vbox.add_child(dark_row)

	dark_mode_btn = Button.new()
	dark_mode_btn.custom_minimum_size = Vector2(310, 48)
	if ui_font:
		dark_mode_btn.add_theme_font_override("font", ui_font)
	dark_mode_btn.add_theme_font_size_override("font_size", 28)
	dark_mode_btn.pressed.connect(_on_dark_mode_toggled)
	dark_row.add_child(dark_mode_btn)

	dark_desc_label = Label.new()
	dark_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dark_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dark_desc_label.add_theme_font_size_override("font_size", 16)
	dark_desc_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	vbox.add_child(dark_desc_label)

	_refresh_mode_ui()


func _on_difficulty_selected(diff_id: int) -> void:
	_play_click()
	if has_node("/root/GameSettings"):
		var gs = get_node("/root/GameSettings")
		gs.difficulty = diff_id
	_refresh_mode_ui()


func _on_dark_mode_toggled() -> void:
	_play_click()
	if has_node("/root/GameSettings"):
		var gs = get_node("/root/GameSettings")
		gs.dark_mode = not bool(gs.dark_mode)
	_refresh_mode_ui()


func _refresh_mode_ui() -> void:
	var cur_diff: int = 1
	var is_dark: bool = false
	var desc_text: String = ""
	if has_node("/root/GameSettings"):
		var gs = get_node("/root/GameSettings")
		cur_diff = int(gs.difficulty)
		is_dark = bool(gs.dark_mode)
		desc_text = str(gs.get_difficulty_description())

	var colors: Array[Color] = [
		Color(0.45, 0.90, 0.52),
		Color(0.95, 0.85, 0.42),
		Color(0.95, 0.45, 0.22),
		Color(0.95, 0.14, 0.18),
	]

	for i in range(diff_buttons.size()):
		var b: Button = diff_buttons[i]
		var selected: bool = (i == cur_diff)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(6)
		st.set_border_width_all(2 if selected else 1)
		if selected:
			st.bg_color = Color(colors[i].r * 0.35, colors[i].g * 0.35, colors[i].b * 0.35, 0.95)
			st.border_color = colors[i]
			b.add_theme_color_override("font_color", colors[i])
		else:
			st.bg_color = Color(0.12, 0.12, 0.15, 0.8)
			st.border_color = Color(0.32, 0.32, 0.36, 0.8)
			b.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("pressed", st)

	if mode_desc_label:
		mode_desc_label.text = desc_text
		mode_desc_label.add_theme_color_override("font_color", colors[clampi(cur_diff, 0, 3)])

	if dark_mode_btn:
		dark_mode_btn.text = "DARK MODE: ON" if is_dark else "DARK MODE: OFF"
		var dst := StyleBoxFlat.new()
		dst.set_corner_radius_all(6)
		dst.set_border_width_all(2)
		if is_dark:
			dst.bg_color = Color(0.22, 0.06, 0.08, 0.95)
			dst.border_color = Color(0.90, 0.22, 0.25)
			dark_mode_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		else:
			dst.bg_color = Color(0.14, 0.18, 0.22, 0.9)
			dst.border_color = Color(0.55, 0.72, 0.85)
			dark_mode_btn.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98))
		dark_mode_btn.add_theme_stylebox_override("normal", dst)
		dark_mode_btn.add_theme_stylebox_override("hover", dst)
		dark_mode_btn.add_theme_stylebox_override("pressed", dst)

	if dark_desc_label:
		if is_dark:
			dark_desc_label.text = "DARK MODE ON: Pitch-dark house, Torch [RMB/T] enabled, EXTREME gritty PSX horror shader!"
			dark_desc_label.add_theme_color_override("font_color", Color(0.95, 0.58, 0.58))
		else:
			dark_desc_label.text = "DARK MODE OFF: Clear Granny-style indoor visibility, no torch needed, clean normal PSX shader."
			dark_desc_label.add_theme_color_override("font_color", Color(0.78, 0.88, 0.94))


func _sync_slider(bus_index: int, slider: HSlider) -> void:
	if slider == null or bus_index >= AudioServer.bus_count:
		return
	if AudioServer.is_bus_mute(bus_index):
		slider.set_value_no_signal(0.0)
	else:
		var lin := db_to_linear(AudioServer.get_bus_volume_db(bus_index))
		slider.set_value_no_signal(clampf(lin, 0.0, 1.0))


func _process(_delta):
	if mode_panel:
		mode_panel.visible = menu.visible
	if title_lbl:
		title_lbl.visible = menu.visible
	if Input.is_action_just_pressed("ui_cancel"):
		if graphics.visible:
			showandhide(options, graphics)
		elif audio.visible:
			showandhide(options, audio)
		elif options.visible:
			showandhide(menu, options)


func _play_click() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click", -3.0)


func _play_hover() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_hover", -10.0, 1.0)


func _connect_button_hover_sfx(root: Node) -> void:
	for child in root.get_children():
		if child is BaseButton:
			var btn: BaseButton = child as BaseButton
			if not btn.mouse_entered.is_connected(_play_hover):
				btn.mouse_entered.connect(_play_hover)
		_connect_button_hover_sfx(child)


func _on_new_game_pressed():
	_play_click()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_packed(mainhouse)


func _on_options_pressed():
	_play_click()
	showandhide(options, menu)


func _on_exit_pressed():
	_play_click()
	get_tree().quit()


func _on_graphics_pressed():
	_play_click()
	showandhide(graphics, options)


func _on_audio_pressed():
	_play_click()
	showandhide(audio, options)


func _on_full_screen_toggled(button_pressed):
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_v_sync_toggled(button_pressed):
	if button_pressed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func showandhide(first, second):
	first.visible = true
	second.visible = false


func _on_master_value_changed(value):
	volume(0, value)


func volume(bus_index: int, value: float):
	if bus_index >= AudioServer.bus_count:
		return
	if value <= 0.001:
		AudioServer.set_bus_mute(bus_index, true)
	else:
		AudioServer.set_bus_mute(bus_index, false)
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))


func _on_music_value_changed(value):
	volume(1, value)


func _on_sound_fx_value_changed(value):
	volume(2, value)


func _on_backfrom_audio_pressed():
	_play_click()
	showandhide(options, audio)


func _on_backfrom_graphics_pressed():
	_play_click()
	showandhide(options, graphics)


func _on_backfrom_options_pressed():
	_play_click()
	showandhide(menu, options)


func _on_load_game_pressed():
	_play_click()
	get_tree().change_scene_to_file("res://scenes/load_game_menu.tscn")
